-----------------------------------
-- LQS: hooks, where a server plugs in its own behaviour
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
--
-- A server replaces any of these after LQS loads (from its own lib or module):
--   LQS.hooks.onQuestCompleted = function(player, name, opts) ... end
-- opts: { mission = bool, music = id or nil, info = the quest's info or nil }
-----------------------------------
LQS       = LQS or {}
LQS._     = LQS._ or {}
LQS.hooks = LQS.hooks or {}

local P = LQS._
local H = LQS.hooks

-- Quest and mission messages. Only set when missing, so a server's hooks
-- survive a reload of this file.
H.onQuestAccepted = H.onQuestAccepted or function(player, name, opts)
    opts = opts or {}

    if opts.mission then
        player:sys("\129\158 New Mission: {}", name)
    else
        player:sys("\129\158 Quest Accepted: {}", name)
    end
end

H.onQuestCompleted = H.onQuestCompleted or function(player, name, opts)
    opts = opts or {}

    if opts.mission then
        player:sys("\129\159 Mission Completed: {}", name)
    else
        player:sys("\129\159 Quest Completed: {}", name)
    end

    if opts.music then
        player:changeMusic(0, opts.music)
        player:changeMusic(1, opts.music)
    end
end

-- Whole-quest gate: false shows the NPC's default instead of any step
H.questAvailable = H.questAvailable or function(player, info)
    return true
end

-- Called for each credited member when a quest mob dies, after LQS's own handling
H.onMobDeath = H.onMobDeath or function(mob, player, entity)
end

H.giveCurrency = H.giveCurrency or function(player, name, amount)
    return npcUtil.giveCurrency(player, name, amount)
end

-- The message a builder's accept / complete / mission keys ask for
function P.questMessage(player, obj, info)
    local opts = { music = obj.music, info = info }

    if obj.complete ~= nil then
        H.onQuestCompleted(player, obj.complete, opts)
    elseif obj.accept ~= nil then
        H.onQuestAccepted(player, obj.accept, opts)
    elseif obj.mission ~= nil then
        opts.mission = true
        H.onQuestAccepted(player, obj.mission, opts)
    end
end

-- 2.x names, kept as plain calls into the hooks (custom code calls these)
LQS.questAccepted = function(player, name, isMission)
    H.onQuestAccepted(player, name, { mission = isMission })
end

LQS.questCompleted = function(player, name, isMission)
    H.onQuestCompleted(player, name, { mission = isMission })
end

LQS.newMission = function(player, name)
    H.onQuestAccepted(player, name, { mission = true })
end

return {}
