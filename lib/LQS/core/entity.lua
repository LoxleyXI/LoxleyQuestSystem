-----------------------------------
-- LQS: Dynamic entity setup, reload and refresh
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

-----------------------------------
-- Entity load and reload
-----------------------------------
function P.entitySetup(dynamicEntity, tbl, entity)
    local questName = string.lower(tbl.info.name)

    -- Chest NPCs get raw onTrigger (bypass step system)
    if entity._isChest then
        local chestName = entity.name
        local chestLoot = entity._chestLoot

        dynamicEntity.onTrigger = function(player, npc)
            cexi.loot_chest.open(player, npc, chestLoot, chestName)
        end

    elseif
        entity.type == xi.objType.NPC or
        entity.marker ~= nil
    then
        dynamicEntity.onTrigger = P.getSteps(tbl.info.var, entity, tbl.steps, tbl.entities, questName)
        dynamicEntity.onTrade   = P.getTradeSteps(tbl.info.var, entity, tbl.steps, tbl.entities)

    elseif entity.type == xi.objType.MOB then
        dynamicEntity.groupId     = entity.groupId
        dynamicEntity.groupZoneId = entity.groupZoneId

        if entity.base ~= nil then
            dynamicEntity.groupId     = entity.base[2]
            dynamicEntity.groupZoneId = entity.base[1]
        end

        -- This prevents quest mobs from spawning on their own if their base template mob
        -- has special spawn conditions (night, weather)
        dynamicEntity.spawnType = 128

        if entity.mixins ~= nil then
            dynamicEntity.mixins = entity.mixins
        end

        dynamicEntity.modelSize = entity.size
        dynamicEntity.modelHitboxSize = entity.hitbox

        -- Util hook runner: calls all matching util callbacks for a given hook
        local function runUtils(hookName, ...)
            if entity.util then
                for _, util in ipairs(entity.util) do
                    if util[hookName] then
                        util[hookName](...)
                    end
                end
            end
        end

        local stepDeath = P.getMobSteps("onMobDeath", tbl.info.var, entity, tbl.steps, tbl.entities)
        dynamicEntity.onMobDeath = function(mob, player, optParams)
            runUtils("onMobDeath", mob, player)
            stepDeath(mob, player, optParams)
        end

        dynamicEntity.onMobDisengage = function(mob)
            runUtils("onMobDisengage", mob)
            if entity.onMobDisengage ~= nil then
                entity.onMobDisengage(mob)
            else
                -- DespawnMob in onMobDisengage causes a server crash on a later LSB commit
                mob:setLocalVar("disengaged", 1)
            end
        end

        dynamicEntity.onMobInitialize = function(mob)
            mob:setMobMod(xi.mobMod.DETECTION, entity.detection or 0x08)
            mob:setMobMod(xi.mobMod.CHECK_AS_NM,  1)
            mob:setMobMod(xi.mobMod.CHARMABLE,    0)
            mob:setMobMod(xi.mobMod.ALLI_HATE,   30)

            if entity.aeffect ~= nil or entity.onAdditionalEffect ~= nil then
                mob:setMobMod(xi.mobMod.ADD_EFFECT, 1)
            end

            if entity.jobSpecial then
                g_mixins.job_special(mob)
            end

            if entity.immunities ~= nil then
                for _, immunity in pairs(entity.immunities) do
                    mob:addImmunity(immunity)
                end
            end

            if entity.skillList ~= nil then
                mob:setMobMod(xi.mobMod.SKILL_LIST, entity.skillList)
            end

            if entity.spellList ~= nil then
                mob:setMobMod(xi.mobMod.SPELL_LIST, entity.spellList)
            end

            if entity.mobMods ~= nil then
                for mobModID, mobModValue in pairs(entity.mobMods) do
                    mob:setMobMod(mobModID, mobModValue)
                end
            end

            runUtils("onMobInitialize", mob)
        end

        dynamicEntity.onMobSpawn = function(mob)
            runUtils("onMobSpawn", mob)
            if entity.onMobSpawn then
                entity.onMobSpawn(mob)
            end
        end

        dynamicEntity.onMobFight = function(mob, target)
            runUtils("onMobFight", mob, target)
            if entity.onMobFight then
                entity.onMobFight(mob, target)
            end
        end

        dynamicEntity.onMobRoam = function(mob)
            runUtils("onMobRoam", mob)
            if entity.onMobRoam ~= nil then
                entity.onMobRoam(mob)
            end

            if mob:getLocalVar("disengaged") > 0 then
                DespawnMob(mob:getID())
            end
        end

        if entity.onAdditionalEffect ~= nil then
            dynamicEntity.onAdditionalEffect = function(mob, target, damage)
                return entity.onAdditionalEffect(mob, target, damage)
            end
        end

        if entity.aeffect ~= nil then
            dynamicEntity.onAdditionalEffect = function(mob, target, damage)
                return LQS.addEffectFromSpec(mob, target, damage, entity.aeffect)
            end
        end
    end
end

function P.entityAfter(de, entity)
    if entity.animation then
        de:setAnimation(entity.animation)
    end

    if entity.hidden then
        de:setStatus(xi.status.DISAPPEAR)
    end

    if entity.hideName ~= nil then
        de:hideName(entity.hideName)
    end

    -- Hide names and HP for side-quest/sparkle markers
    if entity.marker ~= nil then
        de:hideName(true)
        de:hideHP(true)
    end

    if entity.hideHP ~= nil then
        de:hideHP(entity.hideHP)
    end

    if entity.untargetable ~= nil then
        de:setUntargetable(entity.untargetable)
    end

    if
        entity.type == xi.objType.MOB and
        entity.dialog ~= nil
    then
        printf("[LQS] %s is a mob but has been assigned dialog.", entity.name)
    end

    -- entity.listener syntax:
    -- { 'ENGAGE', 'NameOfEngageListener', function }
    if
        entity.listeners == nil and
        entity.listener ~= nil
    then
        entity.listeners = { entity.listener }
    end

    if entity.listeners ~= nil then
        for _, listener in pairs(entity.listeners) do
            de:removeListener(listener[2])
            de:addListener(listener[1], listener[2], listener[3])
        end
    end
end

function P.entityRefresh(dynamicEntity, zone, tbl, entity)
    local result = zone:queryEntitiesByName("DE_" .. entity.name)

    if result ~= nil then
        for _, de in pairs(result) do
            de:setPos(entity.pos[1], entity.pos[2], entity.pos[3], entity.pos[4])

            if type(entity.look) == "string" then
                de:setLookString(entity.look)

            -- TODO: Need extra packet to update without zoning
            elseif entity.marker == nil then
                de:setModelId(entity.look)
            end

            P.entityAfter(de, entity)
        end
        printf("[LQS] Entity DE_%s was updated.", entity.name)
    else
        printf("[LQS] Entity DE_%s not found.", entity.name)
    end
end

return {}
