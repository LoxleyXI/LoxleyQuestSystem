-----------------------------------
-- LQS: LQS.dialog
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

-----------------------------------
-- LQS.dialog
-----------------------------------
LQS.dialog = function(obj)
    return function(player, npc, tbl, var, step, questName)
        -----------------------------------
        -- Prevent players spamming dialog and duplicating rewards
        -----------------------------------
        if player:getLocalVar("[LQS]REWARD") > 0 then
            return
        end

        -----------------------------------
        -- Player does not meet requirements
        -- Show default dialog or "fail" dialog
        -----------------------------------
        if
            obj.check ~= nil and
            not LQS.checks(obj.check)(player)
        then
            if obj.fail ~= nil then
                LQS.event(player, npc, obj.fail)
            else
                LQS.event(player, npc, tbl.dialog.DEFAULT)
            end

            return
        end

        -----------------------------------
        -- Setup P.conditional dialog events
        -----------------------------------
        local event = obj.event

        if obj.conditionalDialog ~= nil then
            event = P.conditional[obj.conditionalDialog](player, obj.event)
        end

        -----------------------------------
        -- If spawned, despawn marker and spawn NPC
        -----------------------------------
        if not P.eventSpawn(obj, player, npc, event) then
            if obj.name == "" then
                LQS.event(player, nil, event)
            else
                LQS.event(player, npc, event)
            end
        end

        -- If not a step, stop here
        -- eg. Hint/Reminder dialog
        if
            obj.step ~= nil and
            not obj.step
        then
            return
        end

        -----------------------------------
        -- Prevent spamming events with local var
        -----------------------------------
        local delay = LQS.eventDelay(event)
        player:setLocalVar("[LQS]REWARD", 1)

        player:timer(delay, function(playerArg)
            -----------------------------------
            -- No reward, give Quest/Mission accepted message
            -----------------------------------
            if obj.reward == nil then
                player:setCharVar(var, step)

                if obj.quest ~= nil then
                    LQS.questAccepted(player, obj.quest, false)
                elseif obj.mission ~= nil then
                    LQS.newMission(player, obj.mission)
                end

                player:setLocalVar("[LQS]REWARD", 0)
                return
            end

            -----------------------------------
            -- Setup P.conditional rewards
            -----------------------------------
            local reward = obj.reward

            if obj.conditionalReward ~= nil then
                reward = P.conditional[obj.conditionalReward](player, obj.reward)
            end

            -----------------------------------
            -- Reward handling
            -----------------------------------
            if P.giveReward(player, reward, questName) then
                -- If the reward was succesfully given, advance the step
                player:setCharVar(var, step)

                -- If not explicitly beginQuest, assume Quest/Mission complete
                if obj.beginQuest ~= nil then
                    LQS.questAccepted(player, obj.beginQuest)
                elseif obj.quest ~= nil then
                    LQS.questCompleted(player, obj.quest, false)
                elseif obj.mission ~= nil then
                    LQS.newMission(player, obj.mission)
                end

                -- Call optional after function
                -- Older quest style
                if
                    type(reward) == "table" and
                    reward.after ~= nil
                then
                    reward.after(player)
                end

                -- Newer quest style
                if obj.after ~= nil then
                    obj.after(player)
                end

                -----------------------------------
                -- Clear locking var
                -----------------------------------
                player:setLocalVar("[LQS]REWARD", 0)
                return true
            else
                player:setLocalVar("[LQS]REWARD", 0)
                return false
            end
        end)
    end
end


-----------------------------------
-- Extra helpers
-----------------------------------
LQS.nothingElse = function()
    return LQS.dialog({
        step  = false,
        name  = "",
        event =
        {
            "There is nothing else to do here.",
        },
    })
end

return {}
