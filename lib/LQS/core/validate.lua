-----------------------------------
-- LQS: quest validation, run by LQS.add
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
--
-- Faults are reported as "<path>: <problem>". Errors stop the quest loading
-- (a running version keeps working on reload); warnings are printed.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

local function set(list)
    local s = {}

    for _, v in ipairs(list) do
        s[v] = true
    end

    return s
end

local ENTITY_KEYS = set({
    "name", "packetName", "type", "look", "pos", "marker", "hidden", "hideName", "hideHP",
    "untargetable", "animation", "size", "hitbox", "flags", "namevis", "listener", "listeners",
    "default", "dialog", "onTrigger", "entity", "key", "zone", "widescan",
    -- mobs
    "base", "groupId", "groupZoneId", "level", "minLevel", "maxLevel", "hp", "mods", "mobMods",
    "effects", "immunities", "skillList", "spellList", "mixins", "jobSpecial", "detection",
    "aeffect", "loot", "pool", "points", "tally", "title", "restore", "delCap", "util", "dropID",
    "after", "onMobSpawn", "onMobFight", "onMobRoam", "onMobDisengage", "onMobDeath",
    "onMobInitialize", "onAdditionalEffect", "onMobSpellChoose", "onSpellPrecast", "job", "animationsub",
})

local COMMON = { "check", "event", "reward", "step", "accept", "complete", "mission", "music", "as", "object", "after", "obj" }

local BUILDER_KEYS =
{
    dialog = set({ "fail", "spawn", "hideSpawner", "levelCap", "raiseAllowed", "partySize", "scaleVar", "nextPos", "job", "subjob", unpack(COMMON) }),
    trade  = set({
        "required", "accepted", "declined", "increment", "keep", "spawn", "tally", "list",
        "exchange", "sellrate", "exclude", "replacements", "conditional", "points", "flag",
        "nextPos", "levelCap", "raiseAllowed", "partySize", "scaleVar", "setVar", "setVarAll",
        "hideSpawner", "job", "subjob", unpack(COMMON),
    }),
    menu   = set({
        "title", "before", "declined", "default", "options", "spawn", "flag", "nextPos",
        "levelCap", "raiseAllowed", "partySize", "scaleVar", "setVar", "setVarAll", "onChoice", "hideSpawner", "job", "subjob",
        unpack(COMMON),
    }),
    defeat = set({
        "mobs", "spawner", "event", "step", "resetStep", "flag", "cooldown", "setLocal", "helper",
        "var", "exp", "points", "pointsVar", "message", "multiplier", "after", "raise", "obj",
    }),
}

-- Event rows: one command plus its options (delay may ride on any row)
local EVENT_KEYS = set({
    "delay", "emote", "narrate", "face", "say", "message", "special", "music", "pos", "teleport",
    "spawn", "despawn", "glimpse", "animate", "pose", "action", "packet", "addEffect",
    "removeEffect", "charvar", "costume", "scripted_event", "menu", "object",
    -- options
    "entity", "target", "mode", "duration", "name", "var", "after", "playerOnly", "teleportDelay",
    "region", "value", "expiry", "skipDelayInternally",
})

local EVENT_RENAMED =
{
    emotion   = "narrate",
    animation = "pose",
    fmt       = "say (with var)",
    noturn    = "nothing (it never did anything)",
}

local RENAMED =
{
    quest      = "accept or complete (say which message)",
    beginQuest = "accept",
    func       = "after (it receives ctx)",
    finish     = "complete",
    chest      = "a server entity util",
}

-- Quest names and vars across loaded quests, to catch duplicates (a reload of the
-- same quest replaces its own entry)
-- A known field this one is likely a misspelling of: same letters ignoring
-- case, or one or two edits away (for names long enough to tell)
P.nearField = function(key, known)
    if type(key) ~= "string" or #key < 4 then
        return nil
    end

    local function distance(a, b)
        if math.abs(#a - #b) > 2 then
            return 3
        end

        local prev = {}

        for j = 0, #b do
            prev[j] = j
        end

        for i = 1, #a do
            local cur = { [0] = i }

            for j = 1, #b do
                local cost = a:sub(i, i) == b:sub(j, j) and 0 or 1
                cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            end

            prev = cur
        end

        return prev[#b]
    end

    -- Short names allow one slip, longer ones two
    local best, bestDistance = nil, #key <= 5 and 2 or 3

    for field in pairs(known) do
        if type(field) == "string" and #field >= 4 then
            local d = string.lower(field) == string.lower(key) and 0 or distance(string.lower(key), string.lower(field))

            if d < bestDistance then
                best, bestDistance = field, d
            end
        end
    end

    return best
end

P.loadedVars  = P.loadedVars or {}
P.loadedNames = P.loadedNames or {}

function P.validateQuest(tbl)
    local errors, warnings = {}, {}

    local function err(path, text)
        table.insert(errors, path .. ": " .. text)
    end

    local function warn(path, text)
        table.insert(warnings, path .. ": " .. text)
    end

    local info = tbl.info

    if type(info) ~= "table" then
        err("info", "missing")
        return errors, warnings
    end

    if type(info.name) ~= "string" or info.name == "" then
        err("info.name", "missing")
    end

    if type(info.var) ~= "string" or info.var == "" then
        err("info.var", "missing")
    elseif P.loadedVars[info.var] ~= nil and P.loadedVars[info.var] ~= info.name then
        err("info.var", string.format("%s is already used by %s", info.var, P.loadedVars[info.var]))
    end

    if type(info.name) == "string" and P.loadedNames[info.name] ~= nil and P.loadedNames[info.name] ~= info.var then
        err("info.name", string.format("'%s' is already the name of the quest using %s", info.name, P.loadedNames[info.name]))
    end

    -- Entities
    local names = {}
    local keys  = {}

    for zoneName, list in pairs(tbl.entities or {}) do
        for i, e in ipairs(list) do
            local path = string.format("entities[%q][%d]", zoneName, i)

            -- A key names one entity per zone (the same NPC may stand in several zones)
            if e.key ~= nil then
                local zoneKey = zoneName .. "/" .. tostring(e.key)

                if keys[zoneKey] ~= nil then
                    err(path .. ".key", string.format("'%s' is also the key of %s", e.key, keys[zoneKey]))
                end

                keys[zoneKey] = path
            end

            if type(e.name) ~= "string" then
                err(path, "has no name")
            else
                -- Steps may name it by key or by name; events by name
                names[e.name] = e

                if e.key ~= nil then
                    names[e.key] = e
                end

                path = string.format("entities[%q]", e.key or e.name)
            end

            for key in pairs(e) do
                if RENAMED[key] then
                    err(path .. "." .. key, "moved to " .. RENAMED[key])
                elseif not ENTITY_KEYS[key] then
                    -- Quests keep their own data on entities; only a near miss of an
                    -- LQS field is worth a word (groupzoneId for groupZoneId, say)
                    local near = P.nearField(key, ENTITY_KEYS)

                    if near then
                        warn(path .. "." .. key, string.format("not an LQS entity field; did you mean '%s'?", near))
                    end
                end
            end

            if e.pos == nil then
                err(path, "has no pos")
            end

            local shown = e.packetName or e.name

            if type(shown) == "string" and #shown > 15 and not e.hideName then
                warn(path, string.format("name '%s' is %d characters; the client shows 15", shown, #shown))
            end

            if e.type == xi.objType.MOB and e.base == nil and e.groupId == nil then
                err(path, "a mob needs base or groupId")
            end
        end
    end

    -- Steps: entity names, builder options, checks
    local used = {}
    local markUsed

    local function checkTable(path, check)
        if type(check) == "table" then
            for key in pairs(check) do
                if not P.knownCheck(key) then
                    err(path .. "." .. key, "unknown check (a server can add one with LQS.checks.define)")
                end
            end
        end
    end

    -- Entities a builder brings in: `as` swaps, encounter spawns, names in event rows
    local function markNames(value)
        if type(value) == "string" then
            used[value] = true
        elseif type(value) == "table" then
            for _, v in ipairs(value) do
                if type(v) == "string" then
                    used[v] = true
                end
            end
        end
    end

    local function markEvent(event, path, entity)
        -- A string is a key into the entity's dialog table
        if type(event) == "string" then
            local dialog = entity and entity.dialog

            if type(dialog) ~= "table" or dialog[event] == nil then
                err(path, string.format("'%s' is not a key in this entity's dialog table", event))
            end

            return
        end

        if type(event) ~= "table" then
            return
        end

        -- A builder's handler where an event belongs (LQS.nothingElse() for LQS.NOTHING_ELSE, say)
        if event.kind ~= nil and (event.onTrigger ~= nil or event.onTrade ~= nil or event.onMobDeath ~= nil) then
            err(path, "is a handler from a builder, not an event")
            return
        end

        if event.byJob ~= nil then
            for job, sub in pairs(event.byJob) do
                markEvent(sub, path .. ".byJob[" .. tostring(job) .. "]", entity)
            end

            return
        end

        for i, row in ipairs(event) do
            if type(row) == "table" then
                for key in pairs(row) do
                    if EVENT_RENAMED[key] then
                        err(string.format("%s[%d].%s", path, i, key), "renamed to " .. EVENT_RENAMED[key])
                    elseif not EVENT_KEYS[key] then
                        err(string.format("%s[%d].%s", path, i, key), "unknown event command or option")
                    end
                end

                -- Named entities must be the quest's (or the player)
                local named = row.entity

                if type(named) == "string" and named ~= "player" and names[named] == nil and names[(named:gsub("_", " "))] == nil then
                    err(string.format("%s[%d].entity", path, i), string.format("'%s' is not one of the quest's entities", named))
                end

                markNames(row.entity)
                markNames(row.spawn)
                markNames(row.despawn)
                markNames(row.glimpse and row.glimpse[2])
            end
        end
    end

    markUsed = function(obj, path, entity)
        markNames(obj.as)
        markNames(obj.spawn)

        for _, key in ipairs({ "event", "accepted", "declined", "fail", "before" }) do
            markEvent(obj[key], path .. "." .. key, entity)
        end

        for i, case in ipairs(obj.list or {}) do
            markUsed(case, path .. ".list[" .. i .. "]", entity)
        end

        for i, opt in ipairs(obj.options or {}) do
            if type(opt) == "table" then
                local where = path .. ".options[" .. i .. "]"

                -- 2.x options were positional: { label, event or true, reward }
                if opt[2] ~= nil or opt[3] ~= nil then
                    err(where, "takes named fields after the label: event =, spawn = true, reward =")
                end

                markEvent(opt.event, where, entity)
            end
        end
    end

    for index, step in ipairs(tbl.steps or {}) do
        for name, entry in pairs(step) do
            local path = string.format("steps[%d][%q]", index, name)

            if name == "check" then
                checkTable(path, entry)
            elseif names[name] == nil then
                err(path, "is not one of the quest's entities")
            else
                used[name] = true

                local function builder(h, where)
                    if type(h) ~= "table" or h.kind == nil or h.obj == nil then
                        return
                    end

                    local allowed = BUILDER_KEYS[h.kind]

                    if allowed then
                        for key in pairs(h.obj) do
                            if RENAMED[key] then
                                err(where .. "." .. key, "moved to " .. RENAMED[key])
                            elseif not allowed[key] then
                                err(where .. "." .. key, "unknown " .. h.kind .. " option")
                            end
                        end
                    end

                    checkTable(where .. ".check", h.obj.check)
                    markUsed(h.obj, where, names[name])
                end

                -- A handler of your own takes ctx alone; (player, npc, ...) is the 2.x form
                local function ownHandler(fn, where)
                    if type(fn) ~= "function" then
                        return
                    end

                    local info = debug.getinfo(fn, "u")

                    if info and info.nparams and info.nparams > 1 then
                        err(where, string.format("takes %d parameters; a handler receives ctx (ctx.player, ctx.npc, ...)", info.nparams))
                    end
                end

                ownHandler(entry, path)

                if type(entry) == "table" then
                    builder(entry, path)
                    checkTable(path .. ".check", entry.check)

                    for _, event in ipairs({ "onTrigger", "onTrade", "onMobDeath" }) do
                        builder(entry[event], path .. "." .. event)
                        ownHandler(entry[event], path .. "." .. event)
                    end

                    for i, sub in ipairs(entry) do
                        builder(sub, path .. "[" .. i .. "]")
                    end
                end
            end
        end
    end

    local reported = {}

    for _, e in pairs(names) do
        if
            not reported[e] and
            not (used[e.name] or (e.key and used[e.key])) and
            e.type ~= xi.objType.MOB and
            e.onTrigger == nil and
            e.default == nil and
            e.dialog == nil and
            -- Scenery and extras that events or code bring out
            not (e.hidden or e.untargetable or e.hideName)
        then
            -- A plain NPC nobody can reach: likely a typo in a step
            reported[e] = true
            warn(string.format("entities[%q]", e.key or e.name), "no step uses it and it has no default")
        end
    end

    return errors, warnings
end

-- Remember a quest that loaded
function P.registerLoaded(tbl)
    P.loadedVars[tbl.info.var]   = tbl.info.name
    P.loadedNames[tbl.info.name] = tbl.info.var
end

return {}
