-----------------------------------
-- LQS: LQS.defeat, LQS.npcSpawner
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

-----------------------------------
-- LQS.defeat
-----------------------------------
function P.awardGive(player, var, reward)
    local var = string.format("[HELPER]%s", string.upper(var))

    -- Make sure player can't claim reward more than once every 24 hours
    if player:getCharVar(var) == 0 then
        print(string.format("[HELPER] %s has claimed a reward for helping with %s.", player:getName(), var))
        player:setCharVar(var, 1, JstMidnight())

        -- Increment var for helper points and leaderboards
        player:incrementCharVar("[HELPER]POINTS", 1)

        -- If player's inventory is full, increment var to receive later
        if not npcUtil.giveItem(player, reward) then
            player:incrementCharVar("[HELPER]EXP_SCROLL", 1)
        end
    end
end

LQS.defeat = function(params)
    return function(mob, player, entity, var, step, entities, check)
        if mob:getLocalVar("KILLED") == 1 then
            return
        end

        mob:setLocalVar("KILLED", 1)

        if params.mobs ~= nil then
            for _, mobName in pairs(params.mobs) do
                local ent = P.getEntity(player, mobName)

                if ent:isAlive() then
                    return false
                end
            end
        end

        local nextStep = step

        if params.resetStep ~= nil then
            nextStep = 0
        end

        -- Increment player quest step
        P.allPlayers(player, function(member)
            -- Apply update for players on the current quest step
            if
                (params.step == nil or params.step == true) and
                (member:getCharVar(var) == (step - 1) and
                (check == nil or check(member)))
            then
                -- Apply var changes only for flagged players
                if
                    params ~= nil and
                    params.flag ~= nil
                then
                    if member:getLocalVar(params.flag) == 1 then
                        member:setCharVar(var, nextStep)
                        member:setLocalVar(params.flag, 0)
                    end
                else
                    member:setCharVar(var, nextStep)
                end
            end

            -- Apply optional cooldown or clear local var for all players
            if params ~= nil then
                if params.cooldown ~= nil then
                    member:setCharVar(params.cooldown, 1, JstMidnight())
                end

                if params.setLocal ~= nil then
                    member:setLocalVar(params.setLocal.var, params.setLocal.val)
                end

                if params.helper ~= nil then
                    local cooldownVar = var .. "_HELPER"

                    if params.var ~= nil then
                        cooldownVar = params.var
                    end

                    P.awardGive(member, cooldownVar, params.helper)
                end

                if params.exp ~= nil then
                    member:addExp(params.exp)
                end

                if params.message ~= nil then
                    if params.points ~= nil then
                        local total = params.points

                        if params.multiplier ~= nil then
                            local multiply = mob:getLocalVar(params.multiplier.var)
                            total = utils.clamp(params.points * multiply, params.multiplier.range[1], params.multiplier.range[2]) + math.random(1, params.points)
                        else
                            if type(params.points) == "table" then
                                total = math.random(params.points[1], params.points[2])
                            end
                        end

                        member:incrementCharVar(params.pointsVar, total)
                        member:sys(params.message, member:getName(), total)
                    else
                        member:sys(params.message)
                    end
                end

                if params.cooldown ~= nil then
                    member:setCharVar(params.cooldown, 1, JstMidnight())
                end

                if params.func ~= nil then
                    params.func(member, step - 1)
                end

                if params.raise ~= nil then
                    member:sendRaise(params.raise)
                end
            end

            -- Remove level cap
            P.removeLevelCap(member)
        end)

        -- Respawn spawner
        if params.spawner ~= nil then
            local spawner = P.getEntity(player, params.spawner)

            if spawner ~= nil then
                spawner:setStatus(xi.status.NORMAL)
            end
        end
    end
end

LQS.npcSpawner = function(tbl, npc, spawner, keepSpawner)
    local result = {}
    local before = {}
    local after  = {}

    local npcs = npc

    if type(npc) ~= "table" then
        npcs = { npc }
    end

    if keepSpawner then
        before =
        {
            { noturn  = true },
            { spawn   = npcs },
            { delay   = 500 },
            { entity  = npcs[1], face = "player" },
            { delay   = 500 },
        }

        after =
        {
            { delay   = 500 },
            { despawn = npcs },
        }
    else
        before =
        {
            { despawn = { spawner } },
            { spawn   = npcs },
            { delay   = 500 },
            { entity  = npcs[1], face = "player" },
            { delay   = 500 },
        }

        after =
        {
            { delay   = 500 },
            { despawn = npcs },
            { spawn   = { spawner } },
        }
    end

    for _, line in pairs(before) do
        table.insert(result, line)
    end

    for _, line in pairs(tbl) do
        table.insert(result, line)
    end

    for _, line in pairs(after) do
        table.insert(result, line)
    end

    return result
end

return {}
