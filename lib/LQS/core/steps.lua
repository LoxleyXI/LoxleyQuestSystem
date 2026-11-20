-----------------------------------
-- LQS: Step dispatch: which handler runs for a player's step
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

-----------------------------------
-- Step generators
-----------------------------------
function P.getStepFunctions(steps, name)
    local func = {}

    for i = 1, #steps do
        if steps[i][name] ~= nil then
            func[i] = steps[i][name]
        end
    end

    return func
end

P.getSteps = function(var, entity, steps, entities, questName)
    local func = P.getStepFunctions(steps, entity.name)

    return function(player, npc)
        -- Interactable NPCs must have a dialog table or default dialog
        if entity.dialog == nil and entity.default == nil then
            return
        end

        local defaultDialog = nil

        if entity.dialog ~= nil then
            defaultDialog = entity.dialog.DEFAULT
        elseif entity.default ~= nil then
            defaultDialog = entity.default
        else
            return
        end

        -- Check custom requirement overrides from quest registry
        if
            LQS.registry[questName] ~= nil and
            LQS.registry[questName].check ~= nil and
            not LQS.registry[questName].check(player)
        then
            LQS.event(player, npc, defaultDialog)
            return
        end

        local step    = player:getCharVar(var) + 1
        local npcName = entity.name

        if entity.marker ~= nil then
            npcName = ""
        elseif npcName == nil then
            npcName = npc:getPacketName()
        end

        if
            func[step] == nil or
            (
                steps[step].check and
                not steps[step].check(player)
            )
        then
            LQS.event(player, npc, defaultDialog)
        else
            if type(func[step]) == "table" then
                if func[step]["onTrigger"] ~= nil then
                    if
                        func[step].check and
                        not func[step].check(player)
                    then
                        LQS.event(player, npc, defaultDialog)
                        return
                    end

                    func[step]["onTrigger"](player, npc, entity, var, step, entities, questName)
                else
                    LQS.event(player, npc, defaultDialog)
                end
            else
                func[step](player, npc, entity, var, step, entities, questName)
            end
        end
    end
end

P.getTradeSteps = function(var, entity, steps, tbl)
    local func = P.getStepFunctions(steps, entity.name)

    return function(player, npc, trade)
        local step = player:getCharVar(var) + 1

        -- Do not attempt to call trade functions on dialog only step
        if
            func[step] ~= nil and
            type(func[step]) == "table" and
            func[step]["onTrade"]
        then
            if
                func[step].check and
                not func[step].check(player)
            then
                return
            end

            func[step]["onTrade"](player, npc, trade, entity, var, step, tbl)
        end
    end
end

P.getMobSteps = function(event, var, entity, steps, entities)
    local func = P.getStepFunctions(steps, entity.name)

    return function(mob, player, optParams)
        -- TODO:
        -- Can we respawn the marker if we don't know the step?
        if player == nil then
            return
        end

        if player:isPC() then
            if
                entity.restore ~= nil and
                optParams ~= nil and optParams.isKiller
            then
                player:addHP(player:getMaxHP())
                player:addMP(player:getMaxMP())
                player:setTP(3000)
            end

            if entity.title ~= nil then
                player:addTitle(entity.title)
            end
        end

        if mob:getLocalVar("LOOT_ROLLED") == 0 then
            if entity.loot ~= nil then
                mob:setLocalVar("LOOT_ROLLED", 1)

                for _, itemInfo in pairs(entity.loot) do
                    if itemInfo[2] == nil then
                        print(fmt("[LQS] Missing item ID! Rolled loot is nil for {} (Player: {})", mob:getName(), player:getName()))
                    elseif itemInfo[2] ~= 0 then
                        player:addTreasure(itemInfo[2], mob, itemInfo[1])
                    end
                end
            end

            -- TODO: Clean this up
            if entity.pool ~= nil then
                mob:setLocalVar("LOOT_ROLLED", 1)

                for _, pool in pairs(entity.pool) do
                    if pool.quantity ~= nil then
                        for _ = 1, pool.quantity do
                            local result = LQS.pickItem(pool)

                            if result[2] == nil then
                                print(fmt("[LQS] Missing item ID! Rolled loot is nil for {} (Player: {})", mob:getName(), player:getName()))
                            elseif result[2] ~= 0 then
                                player:addTreasure(result[2], mob)
                            end
                        end
                    else
                        local result = LQS.pickItem(pool)

                        if result[2] == nil then
                            print(fmt("[LQS] Missing item ID! Rolled loot is nil for {} (Player: {})", mob:getName(), player:getName()))
                        elseif result[2] ~= 0 then
                            player:addTreasure(result[2], mob)
                        end
                    end
                end
            end
        end

        if
            entity.points ~= nil and
            mob:getLocalVar("POINTS_ROLLED") == 0
        then
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
                    npcUtil.giveCurrency(member, "gil", entity.points.gil)
                end

                if entity.points.item ~= nil then
                    if 
                        not npcUtil.giveItem(member, entity.points.item) and
                        entity.points.missed ~= nil
                    then
                        member:sys("Your missed item was stored at the relevant NPC.")
                        member:incrementCharVar(fmt(entity.points.missed, entity.points.item))
                    end
                end
            end)
        end

        -- Chest: spawn personal loot chest on mob death
        if entity.chest ~= nil then
            local chestName = string.gsub(entity.name, " ", "_") .. "_Chest"
            cexi.loot_chest.spawn(mob, player, chestName, {
                modifier = entity.chest.modifier and entity.chest.modifier(mob) or 0,
            })
        end

        if entity.after ~= nil then
            entity.after(mob, player)
        end

        if entity.delCap ~= nil then
            P.allPlayers(player, function(member)
                member:delStatusEffect(xi.effect.LEVEL_RESTRICTION)
            end)
        end

        -- LSB calls onMobDeath once per credited member, so credit only this one
        -- (looping the party here counted each kill once per member, for everyone)
        if entity.tally ~= nil and player:isPC() then
            player:incrementCharVar(entity.tally, 1)
        end

        local step = player:getCharVar(var) + 1

        if func[step] == nil then
            return
        end

        if type(func[step]) == "table" then
            if
                func[step].check ~= nil and
                not func[step].check(player)
            then
                return
            end

            if func[step][event] ~= nil then
                func[step][event](mob, player, entity, var, step, entities, func[step].check)
            end
        elseif event == "onMobDeath" then
            func[step](mob, player, entity, var, step, entities, nil)
        end
    end
end

return {}
