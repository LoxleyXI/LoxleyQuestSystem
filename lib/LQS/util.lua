-----------------------------------
-- LQS Extension: Mob Utilities
-----------------------------------
-- Declarative utilities for mob entity definitions.
-- Add `util = { LQS.util.ignorePet, LQS.util.reqPenalty }` to a mob entity
-- and LQS will compose the callbacks automatically.
--
-- Simple utils are pre-built tables. Factory utils are functions that
-- return configured tables. Each table can have any combination of:
--   onMobInitialize, onMobSpawn, onMobFight, onMobDeath,
--   onMobDisengage, onMobRoam, entities
--
-- This file provides shared helpers. Individual utilities are loaded
-- from lib/LQS/util/*.lua and are fully self-contained.
-----------------------------------
require("modules/module_utils")
-----------------------------------
local m = Module:new("LQS_util")

LQS      = LQS or {}
LQS.util = LQS.util or {}

-----------------------------------
-- Shared Helpers
-----------------------------------

-- A weaponskill listener's skill as an id: LSB passes the id, or (newer LSB) the
-- skill itself. WEAPONSKILL_TAKE listeners receive (user, target, skill, tp, action).
LQS.util.skillId = function(skill)
    if type(skill) == "number" then
        return skill
    end

    if skill ~= nil and skill.getID then
        return skill:getID()
    end

    return skill
end

-- Iterate all players on the mob's enmity list
LQS.util.forEachEngaged = function(mob, func)
    local enmityList = mob:getEnmityList()
    if not enmityList then return end

    for _, entry in pairs(enmityList) do
        local entity = entry.entity
        if entity and entity:getObjType() == xi.objType.PC then
            func(entity)
        end
    end
end

-- Broadcast a message to all engaged players
LQS.util.shout = function(mob, message)
    LQS.util.forEachEngaged(mob, function(player)
        player:fmt(message)
    end)
end

-- Distance between two entities
LQS.util.distance = function(a, b)
    local aPos = a:getPos()
    local bPos = b:getPos()
    local dx = aPos.x - bPos.x
    local dz = aPos.z - bPos.z
    return math.sqrt(dx * dx + dz * dz)
end

-- Pick a random engaged player, optionally filtered
LQS.util.randomEngaged = function(mob, filterFn)
    local candidates = {}
    LQS.util.forEachEngaged(mob, function(player)
        if filterFn == nil or filterFn(player) then
            table.insert(candidates, player)
        end
    end)
    if #candidates == 0 then return nil end
    return candidates[math.random(1, #candidates)]
end

-- Wipe all enmity on the mob
LQS.util.resetEnmity = function(mob)
    LQS.util.forEachEngaged(mob, function(player)
        mob:resetEnmity(player)
    end)
end

return m
