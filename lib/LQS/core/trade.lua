-----------------------------------
-- LQS: LQS.trade
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
--
-- LQS.trade({
--     required  = items,            -- npcUtil format, or function(ctx, trade) -> true / count
--     accepted  = { ... },          -- event when the trade is taken
--     declined  = { ... },          -- event for anything else
--     reward    = spec,
--     step      = false,            -- doesn't advance
--     increment = n,                -- advance n steps (default 1)
--     keep      = true,             -- release the items instead of taking them
--     complete  = "Quest Name",     -- or accept = / mission = : the message
--     spawn     = { "Mob", ... },   -- spawn an encounter instead of rewarding
--     as        = "Other NPC",      -- swap this NPC for another during the event
--     tally     = "[VAR]",          -- add the number of items traded to a var
--     after     = function(ctx) end,
--     list      = { case, ... },    -- several trades: each case takes any of the keys above
-- })
-- exchange / sellrate / exclude / replacements / conditional / points: the
-- item exchange (each traded item rolls a reward from its own table).
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

-- Does the trade match a case's required items?
local function matches(ctx, required)
    if type(required) == "function" then
        return required(ctx, ctx.trade)
    end

    return npcUtil.tradeHasExactly(ctx.trade, required)
end

-- Hand out the result of a matched trade, then take (or release) the items
function P.performTrade(ctx, case, items, multiple)
    local player = ctx.player
    local given

    if items ~= nil then
        given = #items == 0 or npcUtil.giveItem(player, items, { multiple = multiple })
    else
        given = ctx:reward(case.reward)
    end

    if not given then
        player:tradeRelease()
        return false
    end

    if case.keep then
        player:tradeRelease()
    else
        player:tradeComplete()
    end

    if case.step ~= false then
        ctx:advance(case.increment or 1)
    end

    P.questMessage(player, case, ctx.quest.info)

    if case.after ~= nil then
        case.after(ctx)
    end

    return true
end

-- Spawn the case's encounter at the NPC; true if it began
local function startEncounter(ctx, case)
    local player, npc = ctx.player, ctx.npc
    local mobs        = case.spawn

    if case.flag ~= nil then
        player:setLocalVar(case.flag, 1)
    end

    if mobs.hq ~= nil then
        mobs = { mobs.nq }

        if math.random(0, 100) < case.spawn.rate then
            mobs = { case.spawn.hq }
        end
    end

    local started = P.delaySpawn(player, npc, 0, mobs, ctx.entities, true, {
        setPos       = npc:getPos(),
        nextPos      = case.nextPos,
        levelCap     = case.levelCap,
        raiseAllowed = case.raiseAllowed,
        partySize    = case.partySize,
        scaleVar     = case.scaleVar,
    })

    if started and case.setVar ~= nil then
        for _, varInfo in pairs(case.setVar) do
            player:setCharVar(varInfo[1], varInfo[2])
        end
    end

    if case.setVarAll ~= nil then
        P.allPlayers(player, function(member)
            member:setCharVar(case.setVarAll[1], case.setVarAll[2])
        end)
    end

    return started
end

-- Show an event as this NPC, or as the `as` NPC
local function show(ctx, case, event)
    if not P.eventSpawn(case, ctx.player, ctx.npc, event) then
        -- An object (sign, marker) speaks without a name
        local speaker = ctx.npc

        if case.object then
            speaker = nil
        end

        LQS.event(ctx.player, speaker, event, ctx)
    end
end

-- One trade case: items match, so run the accepted event, then the result
local function takeCase(ctx, obj, case)
    local player = ctx.player

    if case.tally ~= nil then
        player:incrementCharVar(case.tally, ctx.trade:getItemCount())
    end

    local delay = LQS.eventDelay(case.accepted)

    show(ctx, case, case.accepted)

    ctx:lockedAfter(delay, function()
        if case.spawn ~= nil then
            if startEncounter(ctx, case) then
                P.performTrade(ctx, case)
            else
                player:tradeRelease()
            end
        else
            P.performTrade(ctx, case)
        end
    end)
end

-- Item exchange: each traded item rolls a reward from its own table
local function exchange(ctx, obj)
    local player, npc, trade = ctx.player, ctx.npc, ctx.trade
    local totalQtyTraded     = 0

    for i = 0, trade:getSlotCount() - 1 do
        local itemID = trade:getItemId(i)

        if
            (obj.exchange[itemID] == nil and obj.sellrate == nil) or
            (obj.exclude ~= nil and obj.exclude[itemID])
        then
            show(ctx, obj, obj.declined)
            return
        end

        totalQtyTraded = totalQtyTraded + trade:getSlotQty(i)
    end

    if obj.sellrate == nil and player:getFreeSlotsCount() < totalQtyTraded then
        player:sys("You don't have enough inventory space.")
        return
    end

    show(ctx, obj, obj.accepted)

    ctx:lockedAfter(LQS.eventDelay(obj.accepted), function()
        local givenGil = 0
        local results  = {}

        for i = 0, trade:getSlotCount() - 1 do
            local slotID  = trade:getItemId(i)
            local slotQty = trade:getSlotQty(i)

            for _ = 1, slotQty do
                if obj.exchange[slotID] == nil and obj.sellrate ~= nil then
                    local item  = GetItemByID(slotID)
                    local value = item:getBasePrice()

                    if value == 0 then
                        value = 1
                    end

                    local total = math.floor(value * obj.sellrate) + 1

                    -- Ex items are worth an extra 10g, rare items 50g
                    if bit.band(item:getFlag(), xi.itemFlag.EX) ~= 0 then
                        total = total + 10
                    end

                    if bit.band(item:getFlag(), xi.itemFlag.RARE) ~= 0 then
                        total = total + 50
                    end

                    givenGil = givenGil + total
                else
                    local exchangeList = obj.exchange[slotID]

                    if obj.conditional ~= nil then
                        exchangeList = obj.conditional(player, obj.exchange[slotID])
                    end

                    local result  = LQS.pickItem(exchangeList)
                    local givenID = result[2]

                    if type(givenID) == "table" then
                        if givenID.gil ~= nil then
                            givenGil = givenGil + givenID.gil
                        end
                    else
                        local givenQty = 1

                        if result[4] ~= nil and type(result[4]) == "table" then
                            givenQty = math.random(result[4][1], result[4][2])
                        end

                        results[givenID] = (results[givenID] or 0) + givenQty
                    end
                end
            end
        end

        local items = {}

        for itemID, itemQty in pairs(results) do
            -- An item the player can't hold: its replacement, or a cluster
            if player:canObtainItem(itemID) then
                table.insert(items, { itemID, itemQty })
            elseif obj.replacements ~= nil and obj.replacements[itemID] then
                table.insert(items, obj.replacements[itemID])
            else
                local clusters =
                {
                    xi.item.FIRE_CLUSTER,
                    xi.item.ICE_CLUSTER,
                    xi.item.WIND_CLUSTER,
                    xi.item.EARTH_CLUSTER,
                    xi.item.LIGHTNING_CLUSTER,
                    xi.item.WATER_CLUSTER,
                    xi.item.LIGHT_CLUSTER,
                    xi.item.DARK_CLUSTER,
                }
                table.insert(items, clusters[math.random(#clusters)])
            end
        end

        P.performTrade(ctx, obj, items, true)

        if givenGil > 0 then
            LQS.hooks.giveCurrency(player, "gil", givenGil)

            if obj.points ~= nil then
                local givenPts = math.floor(givenGil / 10) + 1
                player:incrementCharVar(obj.points.var, givenPts)
                player:sys("{} gains {} {}.", player:getName(), givenPts, obj.points.name)
            end
        end
    end)
end

LQS.trade = function(obj)
    return P.handler("trade", {
        onTrade = function(ctx)
            -- A reward from this quest is still on its way
            if ctx:isLocked() then
                return
            end

            if obj.exchange ~= nil then
                exchange(ctx, obj)
                return
            end

            -- Cases take the trade's own options as defaults
            local cases = obj.list or { obj }

            for _, case in ipairs(cases) do
                if case ~= obj then
                    setmetatable(case, { __index = obj })
                end

                if case.required ~= nil and matches(ctx, case.required) then
                    takeCase(ctx, obj, case)
                    return
                end
            end

            show(ctx, obj, obj.declined)
        end,
    })
end

return {}
