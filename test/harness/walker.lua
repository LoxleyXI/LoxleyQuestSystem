-----------------------------------
-- LQS test harness: the quest walker
-----------------------------------
-- Plays a quest from its own steps table: for each step it finds the handlers,
-- meets the step's checks, then talks, picks menu options, trades the required
-- items and kills spawned mobs until the quest var moves on. Then it checks the
-- quest finished, every reward arrived once, and nothing raised an error.
-----------------------------------
local S = require("harness.server")

local W = {}

-----------------------------------
-- Tagging: remember what built each handler so the walker knows how to play it
-----------------------------------
local tags = setmetatable({}, { __mode = "k" })
W.tags     = tags

local function tagged(kind, builder)
    return function(obj, ...)
        local handler = builder(obj, ...)

        if handler ~= nil then
            local tag = { kind = kind, obj = obj }
            tags[handler] = tag

            -- 3.0 builders return a handler table: tag its functions too
            if type(handler) == "table" then
                for _, event in ipairs({ "onTrigger", "onTrade", "onMobDeath" }) do
                    if type(handler[event]) == "function" then
                        tags[handler[event]] = tag
                    end
                end
            end
        end

        return handler
    end
end

W.quests = {}

-- For harness extensions (LQS_HARNESS_EXT): tag a handler built by some other
-- quest system, and hand the walker a quest table in LQS's shape
function W.tag(handler, kind, obj)
    if handler ~= nil then
        tags[handler] = { kind = kind, obj = obj }
    end

    return handler
end

function W.addQuest(quest)
    table.insert(W.quests, quest)
end

W.tagged = tagged

function W.instrument()
    LQS.dialog = tagged("dialog", LQS.dialog)
    LQS.trade  = tagged("trade",  LQS.trade)
    LQS.menu   = tagged("menu",   LQS.menu)
    LQS.defeat = tagged("defeat", LQS.defeat)
    -- LQS.checks is a callable table (it carries define): keep it one
    local checks = LQS.checks
    LQS.checks = setmetatable({ define = type(checks) == "table" and checks.define or nil }, {
        __call = function(_, tbl)
            local fn = checks(tbl)
            tags[fn] = { kind = "checks", obj = tbl }
            return fn
        end,
    })

    local add = LQS.add
    LQS.add = function(source, tbl)
        table.insert(W.quests, tbl)
        return add(source, tbl)
    end
end

-----------------------------------
-- Quest table helpers
-----------------------------------
-- Entities are found by key, else by name. The same NPC may stand in several
-- zones under one key: take one that starts visible, then the first zone by
-- name, so the choice never depends on table order
local function entityInfo(quest, name)
    local zones = {}

    for zoneName in pairs(quest.entities or {}) do
        table.insert(zones, zoneName)
    end

    table.sort(zones)

    local fallback, fallbackZone

    for _, zoneName in ipairs(zones) do
        for _, e in ipairs(quest.entities[zoneName]) do
            if (e.key or e.name) == name then
                if not e.hidden then
                    return e, zoneName
                end

                fallback, fallbackZone = fallback or e, fallbackZone or zoneName
            end
        end
    end

    return fallback, fallbackZone
end

local function findLive(zoneName, name)
    local zone = S.world.zonesByName[zoneName]

    if not zone then
        return nil
    end

    return zone:queryEntitiesByName("DE_" .. name)[1]
end

-----------------------------------
-- Meeting a step's checks
-----------------------------------
local satisfy =
{
    level    = function(p, v) p.level = math.max(p.level, v) end,
    job      = function(p, v) p.job = v end,
    jobvar   = function(p, v) p:setCharVar(v, p.job) end,
    gm       = function(p, v) p.gmLevel = v and 1 or 0 end,
    vareq    = function(p, v) p:setCharVar(v[1], v[2]) end,
    varin    = function(p, v) p:setCharVar(v[1], v[2][1]) end,
    vargt    = function(p, v) if p:getCharVar(v[1]) <= v[2] then p:setCharVar(v[1], v[2] + 1) end end,
    varlt    = function(p, v) if p:getCharVar(v[1]) >= v[2] then p:setCharVar(v[1], math.max(0, v[2] - 1)) end end,
    varlist  = function(p, v) for _, e in pairs(v) do if p:getCharVar(e[1]) < e[2] then p:setCharVar(e[1], e[2]) end end end,
    zero     = function(p, v) p:setCharVar(v, 0) end,
    allzero  = function(p, v) p:setCharVar(v, 0) end,
    cooldown = function(p, v) p:setCharVar(v, 0) end,
    timeout  = function(p, v) p:setCharVar(v, S.systemTime() + 3600) end,
    bool     = function() end,
    item     = function(p, v) if not p:hasItem(v) then S.walkerGiving = true; p:addItem(v, 1); S.walkerGiving = false end end,
    ki       = function(p, v) p.keyItems[v] = true end,
    skill    = function(p, v) p.skills[v[1]] = math.max(p.skills[v[1]] or 0, v[2]) end,
    quest    = function(p, v) p.quests[v[1] .. ":" .. v[2]] = true end,
    gil      = function(p, v) if p.gil < v then p.gil = v end end,
    cp       = function(p, v) if p.cp < v then p.cp = v end end,
    rank     = function(p, v) if type(v) == "number" then p.ranks[p.nation] = v else p.ranks[v[1]] = v[2] end end,
    currency = function(p, v) if p:getCurrency(v[1]) < v[2] then p.currencies[v[1]] = v[2] end end,
    hasTeleport = function(p, v)
        if type(v) == "number" then
            p.teleports[p.nation .. ":" .. (v + 5)] = true
        else
            p.teleports[v[1] .. ":" .. (v[2] + 5)] = true
        end
    end,
}

-- Extensions add ways to meet their own check keys here
W.satisfy = satisfy

-- Extensions prepare the walking player here: fn(player, quest), before the walk
-- (a server whose questAvailable hook gates quests by player type, say)
W.playerSetup = {}

-- Returns false with a reason when a check can't be met by the walker
local function meetChecks(player, checkFn)
    if checkFn == nil then
        return true
    end

    -- LQS.dialog takes a raw check table; steps and menus take an LQS.checks function.
    -- A quest from another system compiles its tables its own way (W.compileCheck).
    if type(checkFn) == "table" then
        local tbl = checkFn
        checkFn = (W.compileCheck or LQS.checks)(tbl)
        tags[checkFn] = tags[checkFn] or { kind = "checks", obj = tbl }
    end

    local tag = tags[checkFn]

    if not tag then
        -- A hand-written check function: hope it already passes
        return checkFn(player) and true or false, "custom check function"
    end

    for key, value in pairs(tag.obj) do
        local fn = satisfy[string.lower(key)]

        if fn then
            fn(player, value)
        elseif string.lower(key) ~= "eval" then
            return false, "unknown check '" .. key .. "'"
        end
    end

    local ok = checkFn(player)

    if not ok then
        return false, "checks still fail after meeting them (eval?)"
    end

    return true
end

-----------------------------------
-- Actions
-----------------------------------
local function itemsOf(required)
    local list = {}

    if type(required) == "number" then
        table.insert(list, { required, 1 })
    elseif type(required) == "table" then
        for _, v in pairs(required) do
            if type(v) == "number" then
                table.insert(list, { v, 1 })
            elseif type(v) == "table" and type(v[1]) == "number" then
                table.insert(list, { v[1], v[2] or 1 })
            elseif type(v) == "table" and type(v[1]) == "string" and v[1]:lower() == "gil" then
                table.insert(list, { 65535, v[2] })
            end
        end
    end

    return list
end

local function newTrade(items)
    local slots = {}

    for _, it in ipairs(items) do
        table.insert(slots, { id = it[1], qty = it[2] })
    end

    local trade = { slots = slots, confirmed = {} }

    function trade:getSlotCount() return #self.slots end
    function trade:getItemId(i) return self.slots[i + 1] and self.slots[i + 1].id or 0 end
    function trade:getSlotQty(i) return self.slots[i + 1] and self.slots[i + 1].qty or 0 end
    function trade:getSlotItem(i) return S.newEntity({ name = "item" }) end
    function trade:getItemCount()
        local n = 0
        for _, s in ipairs(self.slots) do n = n + s.qty end
        return n
    end
    function trade:getItemQty(id)
        local n = 0
        for _, s in ipairs(self.slots) do if s.id == id then n = n + s.qty end end
        return n
    end
    function trade:hasItemQty(id, qty) return self:getItemQty(id) >= qty end
    function trade:confirmItem(id, qty) self.confirmed[id] = (self.confirmed[id] or 0) + (qty or 1) end
    function trade:confirmSlot(i, qty) local s = self.slots[i + 1]; if s then self:confirmItem(s.id, qty or s.qty) end end
    function trade:getGil() return self:getItemQty(65535) end

    return trade
end

-- Items a trade handler wants, from its LQS.trade table
local function tradeItems(obj)
    if obj.required ~= nil then
        return itemsOf(obj.required)
    end

    if obj.list ~= nil and obj.list[1] ~= nil then
        return itemsOf(obj.list[1].required)
    end

    if obj.exchange ~= nil then
        for itemId in pairs(obj.exchange) do
            return { { itemId, 1 } }
        end
    end

    return nil
end

local function giveForTrade(player, items)
    S.walkerGiving = true

    for _, it in ipairs(items) do
        if it[1] == 65535 then
            player.gil = player.gil + it[2]
        else
            player:addItem(it[1], it[2])
        end
    end

    S.walkerGiving = false
end

-- Pick a menu option: the first that does something (has an event or spawns)
local function chooseOption(menu, tagObj)
    -- A menu that names its advancing option
    if tagObj and tagObj.select ~= nil then
        return tagObj.select
    end

    if tagObj and tagObj.options then
        for i, opt in ipairs(tagObj.options) do
            -- positional { label, event }, or named: spawn = true, or an event that advances
            if
                (opt[2] ~= nil and opt[2] ~= false) or
                opt.spawn or
                (opt.event ~= nil and opt.step ~= false)
            then
                return i
            end
        end
    end

    return nil
end

local function answerMenu(player, tagObj, optionIndex)
    local menu = player.openMenu

    if not menu then
        return false
    end

    player.openMenu = nil
    local index     = optionIndex or chooseOption(menu, tagObj) or #menu.options
    local opt       = menu.options[index]

    if not opt then
        S.fail("menu has no option " .. tostring(index))
        return false
    end

    S.record("choose", { title = menu.title, option = opt[1] })

    if type(opt[2]) == "function" then
        S.protect("menu option '" .. tostring(opt[1]) .. "'", opt[2], player)
    end

    return true
end

-----------------------------------
-- The walk
-----------------------------------
local function classify(quest, name, handler)
    local info = entityInfo(quest, name)
    local isMob = info and info.type == xi.objType.MOB
    local actions = {}

    if isMob then
        table.insert(actions, { kind = "kill", name = name })
        return actions
    end

    if type(handler) == "table" then
        if handler.onTrade then
            local tag = tags[handler.onTrade]
            table.insert(actions, { kind = "trade", name = name, obj = tag and tag.obj })
        end

        if handler.onTrigger then
            local tag = tags[handler.onTrigger]
            table.insert(actions, { kind = tag and tag.kind == "menu" and "menu" or "talk", name = name, obj = tag and tag.obj, step = tag and tag.obj and tag.obj.step })
        end
    else
        local tag = tags[handler]
        table.insert(actions, { kind = tag and tag.kind == "menu" and "menu" or "talk", name = name, obj = tag and tag.obj, step = tag and tag.obj and tag.obj.step })
    end

    return actions
end

local function stepActions(quest, step)
    local talks, kills = {}, {}

    -- Stable order: entity names sorted, trades and menus before talk, kills last
    local names = {}
    for name in pairs(step) do
        if name ~= "check" then
            table.insert(names, name)
        end
    end
    table.sort(names)

    for _, name in ipairs(names) do
        for _, action in ipairs(classify(quest, name, step[name])) do
            if action.kind == "kill" then
                table.insert(kills, action)
            else
                table.insert(talks, action)
            end
        end
    end

    -- Non-advancing dialog (step = false) last among talks
    table.sort(talks, function(a, b)
        local order = { trade = 1, menu = 2, talk = 3 }
        local ao = order[a.kind] + (a.step == false and 3 or 0)
        local bo = order[b.kind] + (b.step == false and 3 or 0)

        if ao == bo then
            return a.name < b.name
        end

        return ao < bo
    end)

    for _, k in ipairs(kills) do
        table.insert(talks, k)
    end

    return talks
end

-- Answer the menus an action opened (a talk, or a trade that offers a choice).
-- A script may name the options to pick, in order, by label prefix
local function answerMenus(quest, player, action)
    local perStep = W.script and W.script.steps and W.script.steps[player:getCharVar(quest.info.var) + 1]
    local choose  = perStep and perStep.choose or {}
    local menus   = 0

    while player.openMenu and menus < 8 do
        local index  = nil
        local wanted = choose[menus + 1]

        if wanted ~= nil then
            for i, opt in ipairs(player.openMenu.options) do
                if tostring(opt[1]):sub(1, #wanted) == wanted then
                    index = i
                end
            end
        end

        answerMenu(player, action.obj, index)
        S.clock.run()
        menus = menus + 1
    end
end

local function perform(quest, player, action, opts)
    local info, zoneName = entityInfo(quest, action.name)

    if not info then
        S.fail(string.format("step names '%s', which is not one of the quest's entities", action.name))
        return
    end

    local live = findLive(zoneName, info.name)

    if not live then
        S.fail(string.format("entity '%s' was never created in %s", action.name, zoneName))
        return
    end

    S.moveTo(player, zoneName)

    if action.kind == "kill" then
        if not live:isSpawned() then
            return "not spawned"
        end

        S.killMob(live, player)
        S.clock.run()
        return
    end

    if action.kind == "trade" then
        local script  = W.script or {}
        local perStep = script.steps and script.steps[player:getCharVar(quest.info.var) + 1]
        local items   = (perStep and perStep.trades and perStep.trades[action.name])
            or (script.trades and script.trades[action.name])
            or (action.obj and tradeItems(action.obj))

        if not items then
            return "trade with no known items"
        end

        giveForTrade(player, items)
        local trade = newTrade(items)
        player.currentTrade = trade
        S.record("trade", { entity = action.name, items = items })
        S.protect("onTrade " .. action.name, live.def.onTrade, player, live, trade)
        S.clock.run()
        player.currentTrade = nil
        answerMenus(quest, player, action)
        return
    end

    -- talk or menu
    S.record("trigger", { entity = action.name })
    S.protect("onTrigger " .. action.name, live.def.onTrigger, player, live)

    -- Spam test: trigger again at once, before any timers run (the reward lock's job)
    if opts and opts.spam then
        S.protect("onTrigger " .. action.name, live.def.onTrigger, player, live)
    end

    S.clock.run()
    answerMenus(quest, player, action)
end

-- Walk a quest to the end. Returns a result table.
function W.walk(quest, player)
    local var     = quest.info.var
    local steps   = quest.steps or {}
    local result  = { name = quest.info.name, var = var, steps = #steps, reached = 0, notes = {} }
    local guard   = 0
    local stuckAt = nil

    while guard < #steps * 4 + 4 do
        guard = guard + 1

        local value = player:getCharVar(var)
        local step  = steps[value + 1]
        result.reached = value

        -- Past the script's finish, the rest of the quest belongs to other systems
        if step == nil or (W.script and W.script.finish and value >= W.script.finish) then
            result.complete = true
            break
        end

        -- A quest script's setup for this step (for eval checks and the like)
        if W.script and W.script.setup then
            S.protect("script setup", W.script.setup, player, value + 1, S)
        end

        -- A script's own action for this step (a switch outside the quest's entities, say)
        local perStepScript = W.script and W.script.steps and W.script.steps[value + 1]

        if perStepScript and perStepScript.before then
            S.protect("script before", perStepScript.before, player, S)
            S.clock.run()
        end

        local ok, why = meetChecks(player, step.check)

        if not ok then
            table.insert(result.notes, string.format("step %d: %s", value + 1, why))
        end

        local advanced = false

        for _, action in ipairs(stepActions(quest, step)) do
            -- Each handler's own check (table form)
            local handler = step[action.name]

            if type(handler) == "table" and handler.check then
                meetChecks(player, handler.check)
            end

            if action.obj and action.obj.check then
                meetChecks(player, action.obj.check)
            end

            local before = player:getCharVar(var)
            local note   = perform(quest, player, action, { spam = true })

            if note then
                table.insert(result.notes, string.format("step %d: %s %s: %s", value + 1, action.kind, action.name, note))
            end

            local now = player:getCharVar(var)

            if now ~= before then
                advanced = true

                -- The var went back down after progress: one full run of a repeatable quest
                if now < before then
                    result.complete   = true
                    result.repeatable = true
                end

                break
            end
        end

        if result.repeatable then
            -- Finish the fight the last step started, so its kill rewards run too
            for zoneName, list in pairs(quest.entities or {}) do
                for _, info in ipairs(list) do
                    local live = info.type == xi.objType.MOB and findLive(zoneName, info.name)

                    if live and live:isSpawned() then
                        S.moveTo(player, zoneName)
                        S.killMob(live, player)
                    end
                end
            end

            S.clock.run()
            break
        end

        -- Still not advanced: fight whatever the step spawned (waves, adds), a few rounds
        if not advanced then
            for _ = 1, 10 do
                local killed = 0

                for zoneName, list in pairs(quest.entities or {}) do
                    for _, info in ipairs(list) do
                        if info.type == xi.objType.MOB then
                            local live = findLive(zoneName, info.name)

                            if live and live:isSpawned() then
                                S.moveTo(player, zoneName)
                                S.killMob(live, player)
                                killed = killed + 1
                            end
                        end
                    end
                end

                S.clock.run()

                if player:getCharVar(var) ~= value then
                    advanced = true
                    break
                end

                if killed == 0 then
                    break
                end
            end
        end

        -- A script's stand-in for what moves this step on elsewhere (another system)
        if not advanced and perStepScript and perStepScript.after then
            S.protect("script after", perStepScript.after, player, S)
            S.clock.run()
            advanced = player:getCharVar(var) ~= value
        end

        if not advanced then
            -- A step made only of hints (step = false talk) is after-completion chatter
            local idle = true

            for _, action in ipairs(stepActions(quest, step)) do
                if not (action.kind == "talk" and action.step == false) then
                    idle = false
                end
            end

            if idle and value > 0 then
                result.complete      = true
                result.finalStepIdle = true
            end

            stuckAt = value + 1
            break
        end
    end

    -- A quest whose last step is only after-completion talk finishes one short
    if not result.complete and stuckAt == #steps then
        result.complete = true
        result.finalStepIdle = true
    end

    result.stuckAt = not result.complete and stuckAt or nil
    return result
end

-- Talk to every NPC again after the quest; nothing should change
function W.revisit(quest, player)
    local var    = quest.info.var
    local before = player:getCharVar(var)
    local items  = 0

    for _, entry in ipairs(S.log) do
        if entry.kind == "item" then items = items + 1 end
    end

    local zoneNames = {}
    for zoneName in pairs(quest.entities or {}) do
        table.insert(zoneNames, zoneName)
    end
    table.sort(zoneNames)

    for _, zoneName in ipairs(zoneNames) do
        local list = quest.entities[zoneName]

        for _, info in ipairs(list) do
            if info.type ~= xi.objType.MOB then
                local live = findLive(zoneName, info.name)

                if live and live.def.onTrigger then
                    S.moveTo(player, zoneName)
                    S.protect("revisit " .. info.name, live.def.onTrigger, player, live)
                    S.clock.run()

                    if player.openMenu then
                        player.openMenu = nil
                    end
                end
            end
        end
    end

    local after = 0
    for _, entry in ipairs(S.log) do
        if entry.kind == "item" then after = after + 1 end
    end

    return player:getCharVar(var) == before, after - items
end

return W
