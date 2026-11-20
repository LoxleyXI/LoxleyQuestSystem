-----------------------------------
-- LQS: Quest accepted / completed messages
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

-----------------------------------
-- Quest tracker
-----------------------------------
LQS.newMission = function(player, missionName)
    player:sys("\129\158 New Mission: {}", missionName)
end

LQS.questAccepted = function(player, questName, isMission)
    local text = "\129\158 Quest Accepted: {}"

    if isMission then
        text = "\129\158 Mission Accepted: {}"
    end

    player:sys(text, questName)
end

LQS.questCompleted = function(player, questName, isMission)
    local text = "\129\159 Quest Completed: {}"

    if isMission then
        text = "\129\159 Mission Completed: {}"
    end

    player:sys(text, questName)
end

return {}
