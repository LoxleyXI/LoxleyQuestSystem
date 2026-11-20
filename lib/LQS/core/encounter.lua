-----------------------------------
-- LQS: Entity lookup, level caps and spawning encounter mobs
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

-----------------------------------
-- Entity utils
-----------------------------------
function P.getEntity(player, entityName)
    local zone   = player:getZone()
    local result = zone:queryEntitiesByName("DE_" .. entityName)

    return result[1]
end

function P.getEntityInfo(entities, entityName)
    local entityInfo = nil

    for _, entity in pairs(entities) do
        if entity.name == entityName then
            entityInfo = entity
        end
    end

    if entityInfo == nil then
        print(string.format("[LQS] Unable to match mob %s with quest entities", entityName))
    end

    return entityInfo
end

function P.hideNPC(npc)
    npc:setStatus(xi.status.INVISIBLE)

    npc:timer(LQS.settings.RESPAWN, function(npcArg)
        npcArg:setStatus(xi.status.NORMAL)
    end)
end

-----------------------------------
-- Encounter utils
-----------------------------------
function P.setEncounter(entity, params)
    local flags = xi.effectFlag.DEATH + xi.effectFlag.ON_ZONE

    if params.raiseAllowed ~= nil then
        flags = xi.effectFlag.ON_ZONE
    end

    entity:addStatusEffectEx(
        xi.effect.LEVEL_RESTRICTION,
        xi.effect.LEVEL_RESTRICTION,
        params.levelCap,
        0,
        0,
        0,
        0,
        0,
        flags + xi.effectFlag.CONFRONTATION
    )

    if params.subjob ~= nil and params.subjob == false then
        entity:addStatusEffectEx(
            xi.effect.SJ_RESTRICTION,
            xi.effect.SJ_RESTRICTION,
            0,
            0,
            0,
            0,
            0,
            0,
            flags
        )
    end
end

P.levelCaps =
{
    16, -- Promyvion - Holla
    18, -- Promyvion - Dem
    20, -- Promyvion - Mea
    22, -- Promyvion-Vahzl
    28, -- Sacrarium
    29, -- Riverne Site B01
    30, -- Riverne Site A01
}

function P.isLevelCappedZone(zoneID)
    for k, v in pairs(P.levelCaps) do
        if v == zoneID then
            return true
        end
    end

    return false
end

function P.removeLevelCap(player)
    local zoneID   = player:getZoneID()

    -- Prevent removing level restriction inside intentionally capped areas
    if P.isLevelCappedZone(zoneID) then
        return
    end

    local alliance = player:getAlliance()

    for i = 1, #alliance do
        if alliance[i]:getZoneID() == zoneID then
            alliance[i]:delStatusEffect(xi.effect.LEVEL_RESTRICTION)

            local pet = alliance[i]:getPet()

            if pet ~= nil then
                pet:delStatusEffect(xi.effect.LEVEL_RESTRICTION)
            end
        end
    end
end

function P.allPlayers(player, func)
    local zoneID   = player:getZoneID()
    local alliance = player:getAlliance()

    for i = 1, #alliance do
        if
            alliance[i]:isPC() and
            alliance[i]:getZoneID() == zoneID
        then
            func(alliance[i])
        end
    end
end

function P.applyLevelCap(player, params)
    if
        params ~= nil and
        params.levelCap ~= nil
    then
        local zoneID   = player:getZoneID()
        local alliance = player:getAlliance()

        for i = 1, #alliance do
            if alliance[i]:getZoneID() == zoneID then
                P.setEncounter(alliance[i], params)

                local pet = alliance[i]:getPet()

                if pet ~= nil then
                    P.setEncounter(pet, params)
                end
            end
        end
    end
end

function P.spawnMob(player, npc, entities, mobName, params)
    local zone     = player:getZone()
    local zoneName = player:getZoneName()
    local mobInfo  = P.getEntityInfo(entities[zoneName], mobName)
    local result   = zone:queryEntitiesByName("DE_" .. mobName)

    for _, mob in pairs(result) do
        if mob ~= nil and not mob:isSpawned() then
            if
                params ~= nil and
                params.setPos ~= nil
            then
                mob:setSpawn(params.setPos.x, params.setPos.y, params.setPos.z, params.setPos.rot)
            else
                mob:setSpawn(mobInfo.pos[1], mobInfo.pos[2], mobInfo.pos[3], mobInfo.pos[4])
            end

            if mobInfo.dropID then
                mob:setDropID(mobInfo.dropID)
            else
                mob:setDropID(0)
            end

            local spawnLevel = mobInfo.level

            if
                params ~= nil and
                params.scaleVar ~= nil
            then
                local scaling = player:getCharVar(params.scaleVar)
                spawnLevel    = spawnLevel + scaling
            end

            mob:spawn()

            if spawnLevel ~= mobInfo.level then -- level is already set on DE initialization
                mob:setMobLevel(spawnLevel) -- This will wipe any mods or mobmods defined in onMobSpawn.
            end

            mob:updateClaim(player)
            mob:setLocalVar("NO_CASKET", 1)
            mob:setCallForHelpBlocked(true)

            -- Quest mobs should not respawn
            mob:setRespawnTime(0)
            DisallowRespawn(mob:getID(), true)

            if mobInfo.mods ~= nil then
                for mod, value in pairs(mobInfo.mods) do
                    mob:setMod(mod, value)
                end
            end

            if mobInfo.effects ~= nil then
                for effectID, effectTable in pairs(mobInfo.effects) do
                    mob:addStatusEffect(effectID, unpack(effectTable))
                end
            end

            -- Correct HP value based on mob params
            mob:setHP(mob:getMaxHP())
            mob:updateHealth()

            if mobInfo.hp ~= nil then
                mob:setMaxHP(mobInfo.hp)
                mob:setHP(mob:getMaxHP())
            end

            if params ~= nil then
                if params.levelCap ~= nil then
                    -- Draw-In was moved to Lua mixin:
                    -- https://github.com/LandSandBoat/server/pull/6566
                    g_mixins.draw_in(mob)
                    P.setEncounter(mob, params)
                end

                if params.nextPos ~= nil then
                    local pos = params.nextPos[math.random(1, #params.nextPos)]
                    npc:setPos(unpack(pos))
                end
            end
        end
    end
end

function P.mobsSpawned(player, mobName)
    local zone   = player:getZone()
    local result = zone:queryEntitiesByName("DE_" .. mobName)

    for _, mob in pairs(result) do
        if
            mob ~= nil and
            mob:isSpawned()
        then
            player:sys("An encounter is already in progress.")
            player:setLocalVar("[LQS]REWARD", 0)
            return true
        end
    end

    return false
end

function P.delaySpawn(player, npc, delay, mobs, entities, hideSpawner, params)
    if type(mobs) == "table" then
        for _, mobName in pairs(mobs) do
            if P.mobsSpawned(player, mobName) then
                return false
            end
        end
    else
        if P.mobsSpawned(player, mobs) then
            return false
        end
    end

    -- TODO: Can these be moved to checks?
    if params ~= nil then
        if
            params.partySize ~= nil and
            player:getPartySize() > params.partySize
        then
            player:sys("Your party is too large to begin this encounter.")
            return false
        end

        if
            params.job ~= nil and
            player:getMainJob() ~= params.job
        then
            player:sys("Your job is incorrect for this encounter.")
            return false
        end
    end

    -- Only skip this if hideSpawner is false
    if
        ((params == nil or params.nextPos == nil) and
        hideSpawner == nil) or
        hideSpawner
    then
        P.hideNPC(npc)
    end

    P.applyLevelCap(player, params)

    npc:timer(delay, function(npcArg)
        if type(mobs) == "table" then
            for _, mobName in pairs(mobs) do
                P.spawnMob(player, npc, entities, mobName, params)
            end
        else
            P.spawnMob(player, npc, entities, mobs, params)
        end
    end)

    return true
end

return {}
