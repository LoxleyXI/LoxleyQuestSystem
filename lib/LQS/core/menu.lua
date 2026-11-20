-----------------------------------
-- LQS: LQS.menu
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
--
-- LQS.menu({
--     title    = "Pick up the helmet?",
--     before   = { ... },            -- event before the menu opens
--     check    = { ... },            -- else `declined`, or `default`
--     options  =
--     {
--         { "No way!" },                                  -- no event: nothing happens
--         { "Let's look...", spawn = true },              -- spawns the menu's `spawn` group
--         { "Yes please.", event = { ... }, reward = spec },
--         { "Sure.", { "Event", "lines" } },              -- positional: label, event, reward
--     },
--     spawn    = { "Mob" },  levelCap, partySize, scaleVar, nextPos, flag, setVar, setVarAll
--     step     = false,
--     accept   = "Quest Name",       -- or complete = / mission =
--     after    = function(ctx) end,
--     onChoice = function(ctx, index) end,  -- or handle every pick yourself
-- })
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

-- An option in either form, as { label, event, reward, spawn }
local function optionOf(opt)
    return {
        label  = opt.label or opt[1],
        event  = opt.event or ((type(opt[2]) == "table" or type(opt[2]) == "function") and opt[2] or nil),
        reward = opt.reward or opt[3],
        spawn  = opt.spawn or opt[2] == true,
        step   = opt.step,
    }
end

local function spawnGroup(ctx, obj)
    local player, npc = ctx.player, ctx.npc
    local mobs        = obj.spawn

    if obj.flag ~= nil then
        player:setLocalVar(obj.flag, 1)
    end

    if mobs.hq ~= nil then
        mobs = { mobs.nq }

        if math.random(0, 100) < obj.spawn.rate then
            mobs = { obj.spawn.hq }
        end
    end

    if P.delaySpawn(player, npc, 0, mobs, ctx.entities, obj.hideSpawner ~= false, {
        setPos       = npc:getPos(),
        nextPos      = obj.nextPos,
        levelCap     = obj.levelCap,
        raiseAllowed = obj.raiseAllowed,
        partySize    = obj.partySize,
        scaleVar     = obj.scaleVar,
        job          = obj.job,
        subjob       = obj.subjob,
    }) then
        if obj.setVar ~= nil then
            for _, varInfo in pairs(obj.setVar) do
                player:setCharVar(varInfo[1], varInfo[2])
            end
        end
    end

    if obj.setVarAll ~= nil then
        P.allPlayers(player, function(member)
            member:setCharVar(obj.setVarAll[1], obj.setVarAll[2])
        end)
    end
end

local function choose(ctx, obj, opt)
    local player, npc = ctx.player, ctx.npc

    if opt.spawn then
        -- The option's event first, then the encounter
        local delay = 0

        if opt.event ~= nil then
            local event = P.eventOf(ctx, opt.event)
            LQS.event(player, npc, event, ctx)
            delay = LQS.eventDelay(event)
        end

        if obj.spawn ~= nil then
            player:timer(delay, function()
                spawnGroup(ctx, obj)
            end)
        end

        return
    end

    -- No event: a "no" option
    if opt.event == nil then
        return
    end

    local event = P.eventOf(ctx, opt.event)

    LQS.event(player, npc, event, ctx)

    -- step = false on the option: it only talks
    if opt.step == false then
        return
    end

    ctx:lockedAfter(LQS.eventDelay(event), function()
        if opt.reward ~= nil and not ctx:reward(opt.reward) then
            return
        end

        if obj.step ~= false then
            ctx:advance()
        end

        P.questMessage(player, obj, ctx.quest.info)

        if obj.after ~= nil then
            obj.after(ctx)
        end
    end)
end

LQS.menu = function(obj)
    local check = P.compileCheck(obj.check)

    return P.handler("menu", { obj = obj,
        onTrigger = function(ctx)
            local player, npc = ctx.player, ctx.npc

            -- Not while a dialog is still playing
            if ctx:busy() then
                return
            end

            if check ~= nil and not check(player) then
                if obj.declined ~= nil then
                    LQS.event(player, npc, P.eventOf(ctx, obj.declined), ctx)
                elseif obj.default == nil then
                    P.showDefault(ctx)
                elseif
                    obj.default.condition ~= nil and
                    player:getCharVar(obj.default.condition[1]) == obj.default.condition[2]
                then
                    LQS.event(player, npc, P.eventOf(ctx, obj.default.dialog), ctx)
                else
                    LQS.event(player, npc, P.eventOf(ctx, obj.default), ctx)
                end

                return
            end

            local options = {}

            for i = 1, #obj.options do
                local opt = optionOf(obj.options[i])

                table.insert(options, {
                    opt.label,
                    function()
                        -- onChoice takes every pick (index of the option)
                        if obj.onChoice ~= nil then
                            obj.onChoice(ctx, i)
                        else
                            choose(ctx, obj, opt)
                        end
                    end,
                })
            end

            local delay = 0

            if obj.before ~= nil then
                local before = P.eventOf(ctx, obj.before)
                LQS.event(player, npc, before, ctx)
                delay = LQS.eventDelay(before)
            end

            player:timer(delay, function()
                player:customMenu({
                    title   = obj.title,
                    options = options,
                })
            end)
        end,
    })
end

return {}
