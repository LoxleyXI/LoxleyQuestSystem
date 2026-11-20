-----------------------------------
-- LQS: step entries and dispatch
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
--
-- Every step entry is normalised once, at LQS.add, into a handler table:
--   { onTrigger = fn(ctx), onTrade = fn(ctx), onMobDeath = fn(ctx), check = fn(player), kinds = {} }
-- and every event goes through one dispatcher that builds ctx and picks the
-- handler for the player's own step.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

local EVENTS = { "onTrigger", "onTrade", "onMobDeath" }

-- Builders mark their output with the kind of handler it is
function P.handler(kind, tbl)
    tbl.kind = kind
    return tbl
end

-- A check: nil, a table of LQS.checks keys, or a function(player)
function P.compileCheck(check)
    if check == nil or type(check) == "function" then
        return check
    end

    return LQS.checks(check)
end

local function passes(check, player)
    return check == nil or check(player)
end

-----------------------------------
-- Normalise one step entry
-----------------------------------
function P.normalizeEntry(entry, isMob, path, errors)
    local h = { kinds = {} }

    local function fault(text)
        table.insert(errors, path .. ": " .. text)
    end

    local function absorb(part, where)
        if type(part) == "function" then
            -- A bare function is the obvious event for this entity
            h[isMob and "onMobDeath" or "onTrigger"] = part
            return
        end

        if type(part) ~= "table" then
            fault(where .. "is a " .. type(part) .. ", not a handler")
            return
        end

        if part.kind ~= nil then
            h.kinds[part.kind] = true
        end

        for _, event in ipairs(EVENTS) do
            local value = part[event]

            if type(value) == "function" then
                h[event] = value
            elseif type(value) == "table" then
                -- A builder placed under an event: take that event's handler from it
                if type(value[event]) == "function" then
                    h[event] = value[event]
                    h.kinds[value.kind or "custom"] = true
                else
                    fault(string.format("%s%s is a %s builder, which has no %s", where, event, tostring(value.kind or "table"), event))
                end
            elseif value ~= nil then
                fault(where .. event .. " is a " .. type(value))
            end
        end

        if part.check ~= nil then
            h.check = P.compileCheck(part.check)
        end

        -- { LQS.dialog{...}, LQS.trade{...} }: merged by kind
        for i, sub in ipairs(part) do
            absorb(sub, where .. "[" .. i .. "].")
        end
    end

    absorb(entry, "")

    if isMob and (h.onTrigger or h.onTrade) then
        fault("is a mob, so only onMobDeath applies")
    end

    return h
end

-- All steps: handlers[step][entityName], plus each step's own check
function P.normalizeSteps(tbl)
    local errors   = {}
    local handlers = {}
    local isMob    = {}

    for _, list in pairs(tbl.entities or {}) do
        for _, entity in ipairs(list) do
            isMob[entity.name] = entity.type == xi.objType.MOB
        end
    end

    for index, step in ipairs(tbl.steps or {}) do
        handlers[index] = {}

        for name, entry in pairs(step) do
            if name == "check" then
                handlers[index].check = P.compileCheck(entry)
            else
                handlers[index][name] = P.normalizeEntry(entry, isMob[name], string.format("steps[%d][%q]", index, name), errors)
            end
        end
    end

    return handlers, errors
end

-----------------------------------
-- Context and defaults
-----------------------------------
local function questCtx(tbl, entity, player, fields)
    fields = fields or {}
    fields.player   = player
    fields.quest    = tbl.quest
    fields.entity   = entity
    fields.entities = tbl.entities
    fields.step     = player:getCharVar(tbl.info.var) + 1
    return P.newCtx(fields)
end

-- The entity's default: `default`, or the older `dialog` (a list of lines, or a
-- table with DEFAULT)
local function defaultOf(entity)
    if entity.default ~= nil then
        return entity.default
    end

    if entity.dialog ~= nil then
        return entity.dialog.DEFAULT or (entity.dialog[1] ~= nil and entity.dialog) or nil
    end
end

function P.showDefault(ctx)
    local default = defaultOf(ctx.entity or {})

    if default ~= nil then
        LQS.event(ctx.player, ctx.npc, default, ctx)
    end
end

-- The whole-quest gate: info.check, the server's hook, and the registry override
local function questOpen(tbl, player)
    if tbl.infoCheck ~= nil and not tbl.infoCheck(player) then
        return false
    end

    if not LQS.hooks.questAvailable(player, tbl.info) then
        return false
    end

    local entry = LQS.registry[string.lower(tbl.info.name or "")]

    if entry ~= nil and entry.check ~= nil and not entry.check(player) then
        return false
    end

    return true
end

-- The handler for this player's step, if its checks pass
local function stepHandler(tbl, entity, ctx, event)
    local stepHandlers = tbl.handlers[ctx.step]
    local h            = stepHandlers and stepHandlers[entity.name]

    if
        h == nil or
        h[event] == nil or
        not passes(stepHandlers.check, ctx.player) or
        not passes(h.check, ctx.player)
    then
        return nil
    end

    return h[event]
end

-----------------------------------
-- Dispatchers
-----------------------------------
function P.triggerDispatcher(tbl, entity)
    return function(player, npc)
        -- Interactable entities have a default (or the older dialog table)
        if entity.default == nil and entity.dialog == nil then
            return
        end

        local ctx = questCtx(tbl, entity, player, { npc = npc })

        if not questOpen(tbl, player) then
            P.showDefault(ctx)
            return
        end

        local handler = stepHandler(tbl, entity, ctx, "onTrigger")

        if handler == nil then
            P.showDefault(ctx)
        else
            handler(ctx)
        end
    end
end

function P.tradeDispatcher(tbl, entity)
    return function(player, npc, trade)
        local ctx = questCtx(tbl, entity, player, { npc = npc, trade = trade })

        if not questOpen(tbl, player) then
            return
        end

        local handler = stepHandler(tbl, entity, ctx, "onTrade")

        if handler ~= nil then
            handler(ctx)
        end
    end
end

-- Loot, pools and points: once per mob, for the whole party
local function rollOnce(mob, player, entity)
    if mob:getLocalVar("LOOT_ROLLED") == 0 and (entity.loot ~= nil or entity.pool ~= nil) then
        mob:setLocalVar("LOOT_ROLLED", 1)

        local function drop(itemId, rate)
            if itemId == nil then
                print(fmt("[LQS] Missing item ID! Rolled loot is nil for {} (Player: {})", mob:getName(), player:getName()))
            elseif itemId ~= 0 then
                player:addTreasure(itemId, mob, rate)
            end
        end

        for _, itemInfo in pairs(entity.loot or {}) do
            drop(itemInfo[2], itemInfo[1])
        end

        for _, pool in pairs(entity.pool or {}) do
            for _ = 1, pool.quantity or 1 do
                drop(LQS.pickItem(pool)[2])
            end
        end
    end

    if entity.points ~= nil and mob:getLocalVar("POINTS_ROLLED") == 0 then
        mob:setLocalVar("POINTS_ROLLED", 1)

        P.allPlayers(player, function(member)
            if entity.points.exp ~= nil then
                member:addExp(entity.points.exp)
            end

            if entity.points.amount ~= nil then
                local amount = math.random(entity.points.amount[1], entity.points.amount[2])
                member:incrementCharVar(entity.points.var, amount)
                member:sys(entity.points.message, member:getName(), amount)
            end

            if entity.points.gil ~= nil then
                LQS.hooks.giveCurrency(member, "gil", entity.points.gil)
            end

            if
                entity.points.item ~= nil and
                not npcUtil.giveItem(member, entity.points.item) and
                entity.points.missed ~= nil
            then
                member:sys("Your missed item was stored at the relevant NPC.")
                member:incrementCharVar(fmt(entity.points.missed, entity.points.item))
            end
        end)
    end
end

-- LSB calls onMobDeath once per credited member: each is handled at their own step
function P.deathDispatcher(tbl, entity)
    return function(mob, player, optParams)
        if player == nil then
            return
        end

        local isKiller = optParams ~= nil and optParams.isKiller

        if player:isPC() then
            if entity.restore ~= nil and isKiller then
                player:addHP(player:getMaxHP())
                player:addMP(player:getMaxMP())
                player:setTP(3000)
            end

            if entity.title ~= nil then
                player:addTitle(entity.title)
            end

            if entity.tally ~= nil then
                player:incrementCharVar(entity.tally, 1)
            end

            if entity.delCap ~= nil then
                player:delStatusEffect(xi.effect.LEVEL_RESTRICTION)
            end
        end

        rollOnce(mob, player, entity)

        if entity.after ~= nil then
            entity.after(mob, player)
        end

        if player:isPC() then
            local ctx     = questCtx(tbl, entity, player, { mob = mob, npc = mob, isKiller = isKiller })
            local handler = stepHandler(tbl, entity, ctx, "onMobDeath")

            if handler ~= nil then
                handler(ctx)
            end
        end

        LQS.hooks.onMobDeath(mob, player, entity)
    end
end

return {}
