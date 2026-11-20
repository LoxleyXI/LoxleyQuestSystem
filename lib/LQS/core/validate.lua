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
    "default", "dialog", "onTrigger", "entity", "key", "area",
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
    dialog = set({ "fail", unpack(COMMON) }),
    trade  = set({
        "required", "accepted", "declined", "increment", "keep", "spawn", "tally", "list",
        "exchange", "sellrate", "exclude", "replacements", "conditional", "points", "flag",
        "nextPos", "levelCap", "raiseAllowed", "partySize", "scaleVar", "setVar", "setVarAll",
        unpack(COMMON),
    }),
    menu   = set({
        "title", "before", "declined", "default", "options", "spawn", "flag", "nextPos",
        "levelCap", "raiseAllowed", "partySize", "scaleVar", "setVar", "setVarAll", "onChoice",
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

    for zoneName, list in pairs(tbl.entities or {}) do
        for i, e in ipairs(list) do
            local path = string.format("entities[%q][%d]", zoneName, i)

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
                    -- Quests keep their own data on entities too; a typo shows up here
                    warn(path .. "." .. key, "not an LQS entity field")
                end
            end

            if e.pos == nil then
                err(path, "has no pos")
            end

            local shown = e.packetName or e.name

            if type(shown) == "string" and #shown > 15 then
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

    local function markEvent(event, path)
        if type(event) ~= "table" then
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

    markUsed = function(obj, path)
        markNames(obj.as)
        markNames(obj.spawn)

        for _, key in ipairs({ "event", "accepted", "declined", "fail", "before" }) do
            markEvent(obj[key], path .. "." .. key)
        end

        for i, case in ipairs(obj.list or {}) do
            markUsed(case, path .. ".list[" .. i .. "]")
        end

        for i, opt in ipairs(obj.options or {}) do
            if type(opt) == "table" then
                markEvent(opt.event or (type(opt[2]) == "table" and opt[2] or nil), path .. ".options[" .. i .. "]")
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
                    markUsed(h.obj, where)
                end

                if type(entry) == "table" then
                    builder(entry, path)
                    checkTable(path .. ".check", entry.check)

                    for _, event in ipairs({ "onTrigger", "onTrade", "onMobDeath" }) do
                        builder(entry[event], path .. "." .. event)
                    end

                    for i, sub in ipairs(entry) do
                        builder(sub, path .. "[" .. i .. "]")
                    end
                end
            end
        end
    end

    for name, e in pairs(names) do
        if not (used[e.name] or (e.key and used[e.key])) and e.type ~= xi.objType.MOB and e.onTrigger == nil then
            -- A plain NPC with only a default is fine; note it in case it's a typo
            if e.default == nil and e.dialog == nil then
                warn(string.format("entities[%q]", name), "no step uses it and it has no default")
            end
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
