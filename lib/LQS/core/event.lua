-----------------------------------
-- LQS: Dialog events: LQS.event, LQS.eventDelay and the event commands
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

-----------------------------------
-- LQS.event
-----------------------------------
P.processString = function(player, prefix, str, delay)
    if str:sub(1, 1) == " " then
        -- Paragraph continue
        player:timer(delay, function(playerArg)
            playerArg:fmt(str)
        end)
    else
        -- New paragraph
        player:timer(delay, function(playerArg)
            playerArg:fmt(prefix .. str)
        end)
    end
end

P.applyEntities = function(player, entityList, func)
    local zone = player:getZone()

    for i = 1, #entityList do
        local entityName = entityList[i]
        local deEntity   = string.gsub(entityName, "_", " ")
        local result     = zone:queryEntitiesByName("DE_" .. deEntity)

        for j = 1, #result do
            func(result[j], player)
        end
    end
end

P.eventEntity = function(player, entityName)
    local zone     = player:getZone()
    local deEntity = string.gsub(entityName, "_", " ")
    local result   = zone:queryEntitiesByName("DE_" .. deEntity)

    return result[1]
end

-- `as`: swap this NPC for another quest entity while the event plays
function P.eventSpawn(obj, player, npc, event)
    if obj.as == nil then
        return false
    end

    local spawned = P.eventEntity(player, obj.as)

    npc:ceDespawn(player)
    spawned:ceSpawn(player)

    player:timer(750, function()
        spawned:ceFace(player)
        LQS.event(player, spawned, event)
    end)

    local delay = LQS.eventDelay(event)

    player:timer(delay + 1500, function()
        npc:ceSpawn(player)
        spawned:ceDespawn(player)
    end)

    return true
end

-- TODO: Should this be kept for LQS?
P.scriptedEvent = function(player, entities, events)
    local ents = {}

    for i = 1, #entities do
        ents[i] = P.eventEntity(player, entities[i])
        ents[i]:ceSpawn(player)
    end

    for i = 1, #events do
        local event = events[i]
        local delay = 5000 + i * 1000

        player:timer(delay, function()
            ents[event[1]]:entityAnimationPacket(event[2])
        end)
    end

    return 6000 + #events * 1000
end

-- 2.x row names: not run, and named once so the caller can update them
local renamedRows = { fmt = "say", emotion = "narrate" }
local renamedNoted = {}

local function renamedRow(row)
    for old, new in pairs(renamedRows) do
        if row[old] ~= nil then
            if not renamedNoted[old] then
                renamedNoted[old] = true
                print(fmt("[LQS] event row '{}' is now '{}'; skipped", old, new))
            end

            return true
        end
    end

    -- `animation` is still a row (the NPC's); with a duration it was the player's pose
    if row.animation ~= nil and row.duration ~= nil then
        if not renamedNoted.animation then
            renamedNoted.animation = true
            print("[LQS] event row 'animation' with 'duration' is now 'pose'; skipped")
        end

        return true
    end

    return false
end

P.processTable = function(player, npc, prefix, row, delay)
    if renamedRow(row) then
        return
    end

    -- Face
    -- Turn entity to face target
    if row.face ~= nil then
        if row.entity == nil then
            if npc then
                npc:ceFace(player)
            end
        else
            local entity = P.eventEntity(player, row.entity)

            if entity == nil then
                return
            end

            if row.face == "player" then
                entity:ceFace(player)
            elseif type(row.face) == "number" then
                entity:ceTurn(player, row.face)
            else
                local otherEntity = P.eventEntity(player, row.face)

                if otherEntity then
                    entity:ceFaceNpc(player, otherEntity)
                end
            end
        end

    elseif row.removeEffect ~= nil then
        if player:hasStatusEffect(row.removeEffect) then
            player:delStatusEffect(row.removeEffect)
        end

    -- Add Status Effect
    -- Add a status effect to the player
    elseif row.addEffect ~= nil then
        if type(row.addEffect) == "number" then
            -- Simple effect with defaults
            player:addStatusEffect(row.addEffect, 0, 0, 3600)
        elseif type(row.addEffect) == "table" then
            local effect   = row.addEffect.effect
            local power    = row.addEffect.power or 0
            local tick     = row.addEffect.tick or 0
            local duration = row.addEffect.duration or 3600
            local subId    = row.addEffect.subId or 0
            local subPower = row.addEffect.subPower or 0
            local tier     = row.addEffect.tier or 0
            local flags    = row.addEffect.flags or 0

            -- Remove conflicting effects if requested (e.g., for Signet)
            if row.addEffect.removeConflicting then
                player:delStatusEffectsByFlag(xi.effectFlag.INFLUENCE, true)
            end

            if flags ~= 0 then
                player:addStatusEffectEx(effect, effect, power, tick, duration, subId, subPower, tier, flags)
            else
                player:addStatusEffect(effect, power, tick, duration, subId, subPower, tier)
            end
        end

    elseif row.charvar ~= nil then
        local expiry = type(row.expiry) == "function" and row.expiry() or row.expiry
        player:setCharVar(row.charvar, row.value, expiry)

    elseif row.costume ~= nil then
        player:setCostume(row.costume)

    elseif row.message ~= nil then
        if type(row.message) == "table" then
            if row.after ~= nil then
                player:timer(row.after, function()
                    for _, message in pairs(row.message) do
                        player:sys(message)
                    end
                end)
            else
                for _, message in pairs(row.message) do
                    player:sys(message)
                end
            end
        else
            player:sys(row.message)
        end

    elseif row.say ~= nil then
        local result = row.say

        if row.var ~= nil then
            local value = player:getCharVar(row.var)
            result = fmt(result, value)
        end

        player:fmt(result)

    -- Narrate: the third-person emote line ("Name looks around.")
    elseif row.narrate ~= nil then
        player:printToPlayer(row.narrate, 8, row.name)

    -- Menu: open a menu (title, options) once the event reaches this row
    elseif row.menu ~= nil then
        player:customMenu(row.menu)

    elseif row.special ~= nil then
        player:messageSpecial(row.special)

    elseif row.music ~= nil then
        player:changeMusic(0, row.music)
        player:changeMusic(1, row.music)

    elseif row.pos ~= nil then
        player:setPos(unpack(row.pos))

    elseif
        row.scripted_event ~= nil and
        row.scripted_event.events ~= nil and
        row.scripted_event.entities ~= nil
    then
        return P.scriptedEvent(player, row.scripted_event.entities, row.scripted_event.events)

    -- NPC Animation Packet
    -- Send an animation packet for the NPC
    elseif
        row.entity ~= nil and
        row.packet ~= nil
    then
        local entity = P.eventEntity(player, row.entity)

        if row.target == nil then
            entity:ceAnimationPacket(player, row.packet, entity)
        else
            local target = P.eventEntity(player, row.entity)
            entity:ceAnimationPacket(player, row.packet, target)
        end

    -- NPC Independent Animation Packet
    -- Send an independent animation packet for the NPC
    elseif
        row.animate ~= nil
    then
        if row.entity ~= nil then
            local entity = P.eventEntity(player, row.entity)

            if row.target == "player" then
                entity:ceAnimate(player, player, row.animate, row.mode or 0)
            else
                entity:ceAnimate(player, entity, row.animate, row.mode or 0)
            end
        else
            player:ceAnimate(player, player, row.animate, row.mode or 0)
        end

    -- Send an action packet (visible to all players, or only this player with row.playerOnly)
    -- row.action = { actionID, animationID }
    elseif
        row.action ~= nil and
        type(row.action) == "table"
    then
        if
            row.entity ~= nil
        then
            local entity   = P.eventEntity(player, row.entity)
            local targetID = row.target == "player" and player:getID() or entity:getID()

            -- playerOnly needs the ceActionPacket binding (lqs_util.cpp); without it, everyone sees it
            if row.playerOnly and type(entity.ceActionPacket) == "function" then
                entity:ceActionPacket(player, targetID, row.action[1], row.action[2])
            else
                entity:injectActionPacket(targetID, row.action[1], row.action[2], 0, 0, 0, 0, 0)
            end
        else
            player:injectActionPacket(player:getID(), row.action[1], row.action[2], 0, 0, 0, 0, 0)
        end

    -- Emote NPC
    -- Sends an emote from the source NPC onto the target NPC or player
    elseif row.emote  ~= nil then
        if row.entity == "player" then
            player:ceEmote(player, row.emote, xi.emoteMode.MOTION)

        elseif row.entity ~= nil then
            local entity = P.eventEntity(player, row.entity)
            entity:ceEmote(player, row.emote, xi.emoteMode.MOTION)

        elseif npc ~= nil then
            npc:ceEmote(player, row.emote, xi.emoteMode.MOTION)
        end

    -- Pose
    -- Hold the player in an animation for a while (crouch, sit)
    elseif row.pose ~= nil then
        if row.target and row.target == "player" then
            local anim = player:getAnimation()

            player:setAnimation(row.pose)

            player:timer(row.duration, function(player)
                player:setAnimation(anim)
            end)

            return row.duration
        end

    -- Spawn Dynamic Entities
    elseif row.spawn ~= nil then
        P.applyEntities(player, row.spawn, function(entity, playerArg)
            entity:ceSpawn(playerArg)
        end)

    -- Despawn Dynamic Entities
    elseif row.despawn ~= nil then
        P.applyEntities(player, row.despawn, function(entity, playerArg)
            entity:ceDespawn(playerArg)
        end)

    -- Glimpse
    -- Temporarily spawn NPCs then despawn after a short interval
    elseif row.glimpse ~= nil then
        P.applyEntities(player, row.glimpse[2], function(entity, playerArg)
            entity:ceSpawn(playerArg)
            -- On the player's timer so it dies with them if they leave first
            playerArg:timer(row.glimpse[1], function(playerTimerArg)
                entity:ceDespawn(playerTimerArg)
            end)
        end)

    -- Teleport
    -- Cross-zone or same-zone teleportation with optional delay
    elseif row.teleport ~= nil then
        local teleportDelay = row.teleportDelay or 0

        if type(row.teleport) == "number" then
            -- Using xi.teleport.id constant (e.g., xi.teleport.id.DEM, xi.teleport.id.OUTPOST)
            local teleportId = row.teleport
            local subPower   = row.region or 0

            player:timer(teleportDelay, function(playerArg)
                playerArg:addStatusEffectEx(xi.effect.TELEPORT, 0, teleportId, 0, 1, 0, subPower)
            end)

        elseif type(row.teleport) == "table" then
            -- Direct coordinates: { x, y, z, rotation, zoneID }
            player:timer(teleportDelay, function(playerArg)
                if row.teleport[5] ~= nil then
                    -- Cross-zone teleport
                    playerArg:setPos(row.teleport[1], row.teleport[2], row.teleport[3], row.teleport[4], row.teleport[5])
                else
                    -- Same-zone teleport
                    playerArg:setPos(row.teleport[1], row.teleport[2], row.teleport[3], row.teleport[4])
                end
            end)
        end
    end
end

-- Returns the total delay for event
LQS.eventDelay = function(tbl)
    -- A function in place of an event runs at once; it has no length of its own
    if type(tbl) == "function" then
        return 0
    end

    if type(tbl) ~= "table" then
        print("[LQS] Event table missing.")
        return 0
    end

    local total = 0

    for i = 1, #tbl do
        local row = tbl[i]
        local nextDelay = 1500

        if row.delay ~= nil then
            if row.skipDelayInternally then
                nextDelay = 0
            else
                nextDelay = row.delay
            end

        elseif row.duration ~= nil then
            nextDelay = row.duration

        elseif row.scripted_event then
            nextDelay = 5000 + 1000 * #row.scripted_event.events

        elseif type(row) == "table" then
            nextDelay = 0
        end

        total = total + nextDelay
    end

    return total
end

-- ctx is optional: handlers pass theirs; custom code calling LQS.event directly
-- gets a minimal one for any function in the event
LQS.event = function(player, npc, tbl, ctx)
    -- A key into the entity's dialog table
    if type(tbl) == "string" then
        tbl = P.eventOf(ctx, tbl)
    end

    if
        type(tbl) ~= "table" and
        type(tbl) ~= "function"
    then
        print(fmt("[LQS] event must be a table or a function. {}, {}", npc, tbl))
        return
    end

    if player:getLocalVar("[LQS]BLOCKING") == 1 then
        return
    end

    -- A function in place of an event (a default, say): called with the player,
    -- the npc and ctx
    if type(tbl) == "function" then
        tbl(player, npc, ctx or P.newCtx({ player = player, npc = npc }))
        return
    end

    local prefix = ""

    -- Objects should not have NPC names
    if
        npc ~= nil and
        tbl[1].object == nil
    then
        npc:ceFace(player)

        prefix = string.format("%s : ", npc:getPacketName())
        player:setLocalVar("[LQS]BLOCKING", 1)
    end

    if not tbl or #tbl == 0 then
        print(string.format("[LQS] Event table for (%s) missing or empty.", prefix))
        return
    end

    if #tbl == 1 then
        if type(tbl[1]) == "table" then
            P.processTable(player, npc, prefix, tbl[1], 0)
        else
            player:fmt(prefix .. tbl[1])
        end

        -- Reset NPC position after single line dialog
        if npc then
            player:timer(3000, function(playerArg)
                npc:ceReset(player)
                player:setLocalVar("[LQS]BLOCKING", 0)
            end)
        end

        return
    end

    local delay = 0

    for i = 1, #tbl do
        local row = tbl[i]
        local nextDelay = 1500

        if type(row) == "function" then
            -- Delayed function
            -- A function row: called with the player and ctx
            local row = tbl[i]
            player:timer(delay, function(playerArg)
                row(playerArg, ctx or P.newCtx({ player = playerArg, npc = npc }))
            end)

        elseif type(row) == "string" then
            P.processString(player, prefix, row, delay)

        -- Process tables
        else
            player:timer(delay, function(playerArg)
                P.processTable(player, npc, prefix, row, delay)
            end)

            if row.delay ~= nil then
                nextDelay = row.delay

            elseif row.duration ~= nil then
                nextDelay = row.duration

            elseif row.scripted_event ~= nil then
                nextDelay = 5000 + 1000 * #row.scripted_event.events

            else
                nextDelay = 0
            end
        end

        delay = delay + nextDelay
    end

    if npc then
        player:timer(delay + 3000, function(playerArg)
            npc:ceReset(player)
            player:setLocalVar("[LQS]BLOCKING", 0)
        end)
    end
end

return {}
