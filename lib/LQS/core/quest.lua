-----------------------------------
-- LQS: LQS.npc and LQS.add
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

-----------------------------------
-- LQS.npc - Standalone NPC (no quest steps)
-- Usage:
--   LQS.npc(m, {
--       ["Zone_Name"] = {
--           { name = "NPC", look = 1234, pos = { x, y, z, rot }, onTrigger = func },
--       },
--   })
-----------------------------------
function P.registerNpc(source, zoneName, entity)
    local flags = entity.flags or 0
    if entity.size and entity.size >= LQS.LARGE then
        flags = bit.bor(flags, 0x04)
    end

    local dynamicEntity =
    {
        name        = entity.name,
        packetName  = entity.packetName or entity.name,
        objtype     = xi.objType.NPC,
        namevis     = entity.namevis or 0,
        entityFlags = flags,
        x           = entity.pos[1],
        y           = entity.pos[2],
        z           = entity.pos[3],
        rotation    = entity.pos[4] or 0,
        widescan    = 1,
        onTrigger   = entity.onTrigger,
        onTrade     = entity.onTrade,
    }

    if entity.look ~= nil then
        dynamicEntity.look = entity.look
    end

    -- Live reload (re-register handlers on file reload)
    if
        xi ~= nil and
        xi.zones ~= nil and
        xi.zones[zoneName] ~= nil and
        xi.zones[zoneName].npcs ~= nil
    then
        local de = xi.zones[zoneName].npcs["DE_" .. entity.name]

        if de ~= nil then
            local lookupName = "DE_" .. entity.name
            local cacheEntry = xi.zones[zoneName].npcs[lookupName]

            if entity.onTrigger then
                cacheEntry.onTrigger = entity.onTrigger
            end

            if entity.onTrade then
                cacheEntry.onTrade = entity.onTrade
            end

            local underscoreZoneName = string.gsub(zoneName, "-", "_")
            local zone = GetZone(xi.zone[string.upper(underscoreZoneName)])

            if zone ~= nil then
                local result = zone:queryEntitiesByName("DE_" .. entity.name)
                if result ~= nil then
                    for _, npc in pairs(result) do
                        npc:setPos(entity.pos[1], entity.pos[2], entity.pos[3], entity.pos[4])
                        if type(entity.look) == "string" then
                            npc:setLookString(entity.look)
                        elseif entity.look ~= nil then
                            npc:setModelId(entity.look)
                        end
                        P.entityAfter(npc, entity)
                    end
                end
            end
        end
    end

    -- First time load
    source:addOverride(string.format("xi.zones.%s.Zone.onInitialize", zoneName), function(zone)
        super(zone)

        local de = zone:insertDynamicEntity(dynamicEntity)
        P.entityAfter(de, entity)
    end)
end

LQS.npc = function(source, tbl)
    for zoneName, entityList in pairs(tbl) do
        for _, entity in pairs(entityList) do
            P.registerNpc(source, zoneName, entity)
        end
    end
end

-----------------------------------
-- LQS.add - Initialise new quest
-----------------------------------
function P.getStepHint(tbl, step, entityZone, entityType)
    local hint = "Unknown"

    for entityName, stepInfo in pairs(step) do
        if entityName ~= "check" then
            local detail = fmt("{} in {}", string.gsub(entityName, "_", " "), entityZone[entityName])

            if entityType[entityName] == xi.objType.MOB then
                return "Defeat " .. detail
            else
                if
                    type(step[entityName]) == "table" and
                    step[entityName].onTrade ~= nil
                then
                    return "Trade " .. detail
                else
                    hint = "Interact with " .. detail
                end
            end
        end
    end

    return hint
end

LQS.add = function(source, tbl)
    -----------------------------------
    -- Create quest registry for !quest command
    -----------------------------------
    if #tbl.steps > 0 and not tbl.info.hidden then
        local registryName = string.lower(tbl.info.name)
        local entry =
        {
            name        = tbl.info.name,
            author      = tbl.info.author,
            var         = tbl.info.var,
            finish      = #tbl.steps - 1,
            hint        = {},
            reward      = {},
            feature     = nil,
            category    = tbl.info.category or "quest",
            subcategory = tbl.info.subcategory,
        }

        -- Reuse existing overrides to prevent them being wiped on reload
        if LQS.registry[registryName] ~= nil then
            entry.check = LQS.registry[registryName].check
            entry.after = LQS.registry[registryName].after
        end

        LQS.registry[registryName] = entry

        local entityZone = {}
        local entityType = {}

        for zoneName, entityList in pairs(tbl.entities) do
            for _, entityInfo in pairs(entityList) do
                entityZone[entityInfo.name] = string.gsub(zoneName, "_", " ")
                entityType[entityInfo.name] = entityInfo.type or xi.objType.NPC
            end
        end

        for _, step in pairs(tbl.steps) do
            table.insert(LQS.registry[registryName].hint, P.getStepHint(tbl, step, entityZone, entityType))
        end

        if tbl.info.reward ~= nil then
            local features = {}

            local function collectFeatures(rewardInfo)
                if type(rewardInfo) ~= "table" then return end

                -- Explicit feature (string or table of strings)
                if rewardInfo.feature then
                    if type(rewardInfo.feature) == "table" then
                        for _, f in ipairs(rewardInfo.feature) do
                            table.insert(features, f)
                        end
                    else
                        table.insert(features, rewardInfo.feature)
                    end
                end

                -- Auto-infer from slots
                if rewardInfo.slots then
                    local bag     = rewardInfo.slots[1]
                    local amount  = rewardInfo.slots[2]
                    local bagName = P.bagNames[bag] or "Unknown"
                    table.insert(features, fmt("{} x{}", bagName, amount))
                end
            end

            if
                type(tbl.info.reward) == "table" and
                tbl.info.reward[1] ~= nil
            then
                for _, rewardInfo in pairs(tbl.info.reward) do
                    table.insert(LQS.registry[registryName].reward, rewardInfo)
                    collectFeatures(rewardInfo)
                end
            else
                table.insert(LQS.registry[registryName].reward, tbl.info.reward)
                collectFeatures(tbl.info.reward)
            end

            if #features > 0 then
                entry.feature = features
            end
        end
    end

    -----------------------------------
    -- Auto-create chest NPCs for mobs with chest = { loot = {...} }
    -----------------------------------
    for zoneName, zoneEntities in pairs(tbl.entities) do
        local chests = {}
        for _, entity in pairs(zoneEntities) do
            if entity.type == xi.objType.MOB and entity.chest ~= nil then
                local chestName = string.gsub(entity.name, " ", "_") .. "_Chest"
                table.insert(chests, {
                    name       = chestName,
                    packetName = entity.chest.name or "Treasure Chest",
                    type       = xi.objType.NPC,
                    look       = entity.chest.look or 966,
                    pos        = { 1, 1, 1, 0 },
                    hidden     = true,
                    hideName   = true,
                    _isChest   = true,
                    _chestLoot = entity.chest.loot,
                })
            end
        end
        for _, chest in ipairs(chests) do
            table.insert(zoneEntities, chest)
        end
    end

    -----------------------------------
    -- Auto-create companion entities from mob utils (gyves, safe zones, etc.)
    -----------------------------------
    for zoneName, zoneEntities in pairs(tbl.entities) do
        local utilEntities = {}
        for _, entity in pairs(zoneEntities) do
            if entity.type == xi.objType.MOB and entity.util ~= nil then
                for _, util in ipairs(entity.util) do
                    if util.entities ~= nil then
                        local companions = util.entities(entity)
                        for _, companion in ipairs(companions) do
                            table.insert(utilEntities, companion)
                        end
                    end
                end
            end
        end
        for _, companion in ipairs(utilEntities) do
            table.insert(zoneEntities, companion)
        end
    end

    -----------------------------------
    -- Create quest entities
    -----------------------------------
    for zoneName, zoneEntities in pairs(tbl.entities) do
        -- Live reload of dynamic entities
        for _, entityInfo in pairs(zoneEntities) do
            if
                xi ~= nil and
                xi.zones ~= nil and
                xi.zones[zoneName] ~= nil and
                xi.zones[zoneName].npcs ~= nil
            then
                local dynamicEntity = xi.zones[zoneName].npcs["DE_" .. entityInfo.name]

                if dynamicEntity ~= nil then
                    P.entitySetup(dynamicEntity, tbl, entityInfo)
                    local underscoreZoneName = string.gsub(zoneName, "-", "_")
                    local zone = GetZone(xi.zone[string.upper(underscoreZoneName)])

                    if zone ~= nil then
                        P.entityRefresh(dynamicEntity, zone, tbl, entityInfo)
                    end
                end
            end
        end

        -- First time load of dynamic entities
        source:addOverride(string.format("xi.zones.%s.Zone.onInitialize", zoneName), function(zone)
            super(zone)

            for index, entity in pairs(zoneEntities) do
                if LQS.settings.DEBUG then
                    printf("[LQS] Added entity %s to %s (%s)", entity.name, zoneName, tbl.info.name)
                end

                local flags = entity.flags or 0
                if entity.size and entity.size >= LQS.LARGE then
                    flags = bit.bor(flags, 0x04)
                end

                local dynamicEntity =
                {
                    name        = entity.name,
                    packetName  = entity.packetName or entity.name,
                    objtype     = entity.type or xi.objType.NPC,
                    namevis     = entity.namevis or 0,
                    entityFlags = flags,
                    x           = entity.pos[1],
                    y           = entity.pos[2],
                    z           = entity.pos[3],
                    rotation    = entity.pos[4] or 0,
                    widescan    = 1,
                }

                if entity.marker ~= nil then
                    if entity.marker == LQS.MAIN_QUEST then
                        dynamicEntity.look = LQS.marker.SHIMMER
                    else
                        dynamicEntity.look = LQS.marker.SPARKLE
                    end
                end

                if entity.look ~= nil then 
                    dynamicEntity.look = entity.look
                end

                P.entitySetup(dynamicEntity, tbl, entity)

                if entity.level ~= nil then
                    dynamicEntity.minLevel = entity.level
                    dynamicEntity.maxLevel = entity.level
                else
                    -- these can be nil for NPCs, but
                    -- minLevel/maxLevel *must* be set for mobs.
                    dynamicEntity.minLevel = entity.minLevel
                    dynamicEntity.maxLevel = entity.maxLevel
                end

                tbl.entities[zoneName][index].entity = zone:insertDynamicEntity(dynamicEntity)

                P.entityAfter(tbl.entities[zoneName][index].entity, entity)
            end
        end)
    end
end

return {}
