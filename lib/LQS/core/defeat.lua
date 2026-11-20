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

-- LQS.defeat({
--     mobs     = { "Mob", ... },   -- all must be dead
--     spawner  = "NPC",            -- shown again once the fight is over
--     event    = { ... },          -- shown to each credited member
--     step     = false, resetStep = true, flag = "[local var]",
--     cooldown = "[VAR]", helper = reward, var = "[VAR]", exp = n, raise = level,
--     points   = n or { min, max }, pointsVar, message, multiplier = { var, range },
--     setLocal = { var, val },
--     after    = function(ctx) end,
-- })
-- Runs once per credited member (LSB calls onMobDeath for each), at that
-- member's own step; the spawner comes back once.
LQS.defeat = function(params)
    return P.handler("defeat", { obj = params,
        onMobDeath = function(ctx)
            local mob, member = ctx.mob, ctx.player

            -- Every listed mob must be down
            if params.mobs ~= nil then
                for _, mobName in pairs(params.mobs) do
                    local ent = P.getEntity(member, P.nameOf(ctx.entities, mobName))

                    if ent ~= nil and ent:isAlive() then
                        return
                    end
                end
            end

            if params.step == nil or params.step == true then
                if params.flag == nil or member:getLocalVar(params.flag) == 1 then
                    if params.resetStep ~= nil then
                        -- true: back to the start; a number: to that value
                        ctx:setVar(type(params.resetStep) == "number" and params.resetStep or 0)
                    else
                        ctx:advance()
                    end

                    if params.flag ~= nil then
                        member:setLocalVar(params.flag, 0)
                    end
                end
            end

            if params.cooldown ~= nil then
                member:setCharVar(params.cooldown, 1, JstMidnight())
            end

            if params.setLocal ~= nil then
                member:setLocalVar(params.setLocal.var, params.setLocal.val)
            end

            if params.helper ~= nil then
                P.awardGive(member, params.var or (ctx.quest.var .. "_HELPER"), params.helper)
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
                    elseif type(params.points) == "table" then
                        total = math.random(params.points[1], params.points[2])
                    end

                    member:incrementCharVar(params.pointsVar, total)
                    member:sys(params.message, member:getName(), total)
                else
                    member:sys(params.message)
                end
            end

            if params.event ~= nil then
                LQS.event(member, nil, P.eventOf(ctx, params.event), ctx)
            end

            if params.after ~= nil then
                params.after(ctx)
            end

            if params.raise ~= nil then
                member:sendRaise(params.raise)
            end

            P.removeLevelCap(member)

            -- The spawner comes back once, not once per member
            if params.spawner ~= nil and mob:getLocalVar("[LQS]SPAWNER_BACK") == 0 then
                mob:setLocalVar("[LQS]SPAWNER_BACK", 1)

                local spawner = P.getEntity(member, P.nameOf(ctx.entities, params.spawner))

                if spawner ~= nil then
                    spawner:setStatus(xi.status.NORMAL)
                end
            end
        end,
    })
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
