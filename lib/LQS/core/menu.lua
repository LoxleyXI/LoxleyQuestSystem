-----------------------------------
-- LQS: LQS.menu
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

-----------------------------------
-- LQS.menu
-----------------------------------
LQS.menu = function(obj)
    return function(player, npc, tbl, var, step, entities)
        -- Prevent players opening menu while in dialog
        if player:getLocalVar("[LQS]BLOCKING") == 1 then
            return
        end

        if
            obj.check ~= nil and
            not obj.check(player)
        then
            if obj.declined ~= nil then
                LQS.event(player, npc, obj.declined)
            else
                if obj.default == nil then
                    printf("[LQS] Default event does not exist for (%s)", npc:getPacketName())
                    return
                end

                if
                    obj.default.condition ~= nil and
                    player:getCharVar(obj.default.condition[1]) == obj.default.condition[2]
                then
                    LQS.event(player, npc, obj.default.dialog)
                else
                    if type(obj.default) == "table" then
                        LQS.event(player, npc, obj.default)
                    else
                        LQS.event(player, npc, { obj.default })
                    end
                end
            end

            return
        end

        local options = {}
        local i = 1

        for i = 1, #obj.options do
            table.insert(options, {
                obj.options[i][1],
                function()
                    if obj.options[i][2] ~= nil then
                        if type(obj.options[i][2]) == "boolean" then
                            if obj.spawn ~= nil then
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
                                if P.delaySpawn(player, npc, 0, mobs, entities, true, {
                                    setPos       = npc:getPos(),
                                    nextPos      = obj.nextPos,
                                    levelCap     = obj.levelCap,
                                    raiseAllowed = obj.raiseAllowed,
                                    partySize    = obj.partySize,
                                    scaleVar     = obj.scaleVar,
                                }) then
                                    if obj.setVar ~= nil then
                                        for _, varInfo in pairs(obj.setVar) do
                                            player:setCharVar(varInfo[1], varInfo[2])
                                        end
                                    end
                                end

                                if obj.setVarAll ~= nil then
                                    P.allPlayers(player, function(member)
                                        member:setCharVar(obj.setVarAll[1], obj.setVarAll[2])
                                    end)
                                end
                            end

                            return
                        end

                        local delay = LQS.eventDelay(obj.options[i][2])
                        LQS.event(player, npc, obj.options[i][2])

                        if obj.options[i][3] ~= nil then
                            if player:getLocalVar("[LQS]REWARD") == 1 then
                                return
                            end

                            player:setLocalVar("[LQS]REWARD", 1)
                        end

                        npc:timer(delay, function(playerArg)
                            -- Optionally give item after dialog
                            if obj.options[i][3] ~= nil then
                                if npcUtil.giveItem(player, obj.options[i][3]) then

                                    if
                                        obj.step == nil or
                                        obj.step
                                    then
                                        player:setCharVar(var, step)
                                    end

                                    if obj.quest ~= nil then
                                        LQS.questAccepted(player, obj.quest, false)
                                    elseif obj.mission ~= nil then
                                        LQS.newMission(player, obj.mission)
                                    end
                                end
                            else
                                if
                                    obj.step == nil or
                                    obj.step
                                then
                                    player:setCharVar(var, step)
                                end

                                if obj.quest ~= nil then
                                    if obj.finish ~= nil then
                                        LQS.questCompleted(player, obj.quest, false)
                                    else
                                        LQS.questAccepted(player, obj.quest, false)
                                    end
                                elseif obj.mission ~= nil then
                                   LQS.newMission(player, obj.mission)
                                end
                            end

                            player:setLocalVar("[LQS]REWARD", 0)
                        end)
                    end
                end,
            })
        end

        local delay = 0

        if obj.before ~= nil then
            if type(obj.before) == "table" then
                LQS.event(player, npc, obj.before)
                delay = LQS.eventDelay(obj.before)
            else
                LQS.event(player, npc, { obj.before })
                delay = LQS.eventDelay({ obj.before })
            end
        end

        player:timer(delay, function()
            player:customMenu({
                title   = obj.title,
                options = options,
            })
        end)
    end
end

return {}
