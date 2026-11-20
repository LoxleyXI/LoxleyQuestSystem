-----------------------------------
-- LQS: LQS.trade
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

-----------------------------------
-- LQS.trade
-----------------------------------
function P.performTrade(obj, player, var, count, increment, items, multiple)
    if
        (obj.reward == nil and items == nil) or
        (type(obj.reward) == "table" and P.giveReward(player, obj.reward, obj.quest and string.lower(obj.quest))) or
        npcUtil.giveItem(player, items or obj.reward, { multiple = multiple })
    then
        player:tradeComplete()

        if
            obj.step == nil or
            obj.step
        then
            player:incrementCharVar(var, increment or 1)
        end

        if
            obj.reward ~= nil and
            type(obj.reward) == "table" and
            obj.reward.after ~= nil
        then
            local result = obj.reward.after(player)

            if type(result) ~= "boolean" then
                print("[LQS] Reward \"after\" function did not return a boolean value.")
            end
        end

        if obj.quest ~= nil then
            LQS.questCompleted(player, obj.quest, false)
        elseif obj.mission ~= nil then
            LQS.newMission(player, obj.mission)
        end

        player:setLocalVar("[LQS]REWARD", 0)
    else
        player:tradeRelease()
        player:setLocalVar("[LQS]REWARD", 0)
    end
end

LQS.trade = function(obj)
    return function(player, npc, trade, entity, var, step, tbl)
        if player:getLocalVar("[LQS]REWARD") == 1 then
            return
        end

        if obj.list ~= nil then
            for _, tradeInfo in pairs(obj.list) do
                if npcUtil.tradeHasExactly(trade, tradeInfo.required) then
                    player:setLocalVar("[LQS]REWARD", 1)
                    local delay = LQS.eventDelay(tradeInfo.accepted)

                    if not P.eventSpawn(obj, player, npc, tradeInfo.accepted) then
                        LQS.event(player, npc, tradeInfo.accepted)
                    end

                    player:timer(delay, function(playerArg)
                        P.performTrade(obj, player, var, nil, tradeInfo.increment)
                    end)

                    return
                end
            end

        -- TODO: Refactor and make this more sensible
        elseif obj.exchange ~= nil then
            local totalQtyTraded = 0

            for i = 0, trade:getSlotCount()-1 do
                local itemID = trade:getItemId(i)

                if
                    (obj.exchange[itemID] == nil and
                    obj.sellrate == nil) or
                    (obj.exclude ~= nil and obj.exclude[itemID])
                then
                    if not P.eventSpawn(obj, player, npc, obj.declined) then
                        LQS.event(player, npc, obj.declined)
                    end

                    return
                end

                totalQtyTraded = totalQtyTraded + trade:getSlotQty(i)
            end

            if obj.sellrate == nil then
                if player:getFreeSlotsCount() < totalQtyTraded then
                    player:sys("You don't have enough inventory space.")
                    return
                end
            end

            player:setLocalVar("[LQS]REWARD", 1)

            local delay = LQS.eventDelay(obj.accepted)

            if not P.eventSpawn(obj, player, npc, obj.accepted) then
                LQS.event(player, npc, obj.accepted)
            end

            player:timer(delay, function(playerArg)
                local givenGil = 0
                local results  = {}

                for i = 0, trade:getSlotCount()-1 do
                    local slotID   = trade:getItemId(i)
                    local slotQty  = trade:getSlotQty(i)

                    for j = 1, slotQty do
                        if
                            obj.exchange[slotID] == nil and
                            obj.sellrate ~= nil
                        then
                            local item  = GetItemByID(slotID)
                            local value = item:getBasePrice()

                            if value == 0 then
                                value = 1
                            end

                            local total = math.floor(value * obj.sellrate) + 1
                            local flags = item:getFlag()

                            -- Ex items are worth an extra 10g
                            if bit.band(item:getFlag(), xi.itemFlag.EX) ~= 0 then
                                total = total + 10
                            end

                            -- Rare items are worth an extra 50g
                            if bit.band(item:getFlag(), xi.itemFlag.RARE) ~= 0 then
                                total = total + 50
                            end

                            givenGil = givenGil + total
                        else
                            local exchangeList = obj.exchange[slotID]

                            -- Allow the item table to be filtered by a P.conditional function
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

                                if
                                    result[4] ~= nil and
                                    type(result[4]) == "table"
                                then
                                    givenQty = math.random(result[4][1], result[4][2])
                                end

                                results[givenID] = (results[givenID] or 0) + givenQty
                            end
                        end
                    end
                end

                local items = {}

                for itemID, itemQty in pairs(results) do
                    -- This will preventing locking the trade container when it fails to give an item
                    if player:canObtainItem(itemID) then
                        table.insert(items, { itemID, itemQty })
                    elseif
                        -- if the exchange defines a replcement for this itemid if it's unobtainable (player already has)
                        obj.replacements ~= nil and
                        obj.replacements[itemID]
                    then
                        table.insert(items, obj.replacements[itemID])
                    else
                        -- otherwise just replace it with a cluster, everyone loves clusters
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

                P.performTrade(obj, player, var, totalQtyTraded, nil, items, true)

                if givenGil > 0 then
                    npcUtil.giveCurrency(player, "gil", givenGil)

                    if obj.points ~= nil then
                        local givenPts = math.floor(givenGil / 10) + 1
                        player:incrementCharVar(obj.points.var, givenPts)
                        player:sys("{} gains {} {}.", player:getName(), givenPts, obj.points.name)
                    end
                end
            end)

            return
        else
            local count = trade:getItemCount()
            local total = count

            if npcUtil.tradeHasExactly(trade, obj.required) then
                player:setLocalVar("[LQS]REWARD", 1)

                if obj.tally ~= nil then
                    player:incrementCharVar(obj.tally, count)
                end

                local delay = LQS.eventDelay(obj.accepted)

                if
                    obj.spawn == nil or
                    type(obj.spawn) == "table" or
                    not P.eventSpawn(obj, player, npc, obj.accepted)
                then
                    LQS.event(player, npc, obj.accepted)
                end

                player:timer(delay, function(playerArg)
                    if
                        obj.spawn == nil or
                        type(obj.spawn) == "string"
                    then
                        P.performTrade(obj, player, var, count)
                    else
                        if obj.flag ~= nil then
                            player:setLocalVar(obj.flag, 1)
                        end

                        local mobs = obj.spawn

                        if obj.spawn.hq ~= nil then
                            mobs = { obj.spawn.nq }

                            if math.random(0, 100) < obj.spawn.rate then
                                mobs = { obj.spawn.hq }
                            end
                        end

                        -- P.delaySpawn spawns the whole group, so call it once
                        if P.delaySpawn(player, npc, 0, mobs, tbl, true, {
                            setPos       = npc:getPos(),
                            nextPos      = obj.nextPos,
                            levelCap     = obj.levelCap,
                            raiseAllowed = obj.raiseAllowed,
                            partySize    = obj.partySize,
                            scaleVar     = obj.scaleVar,
                        }) then
                            P.performTrade(obj, player, var, count)

                            if obj.setVar ~= nil then
                                for _, varInfo in pairs(obj.setVar) do
                                    player:setCharVar(varInfo[1], varInfo[2])
                                end
                            end
                        else
                            player:tradeRelease()
                            player:setLocalVar("[LQS]REWARD", 0)
                        end

                        if obj.setVarAll ~= nil then
                            P.allPlayers(player, function(member)
                                member:setCharVar(obj.setVarAll[1], obj.setVarAll[2])
                            end)
                        end
                    end
                end)

                return
            end
        end

        if not P.eventSpawn(obj, player, npc, obj.declined) then
            LQS.event(player, npc, obj.declined)
        end
    end
end

return {}
