-----------------------------------
-- LQS: LQS.dialog
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
--
-- LQS.dialog({
--     event    = { ... },          -- what the NPC says and does
--     check    = { level = 30 },   -- else `fail`, or the entity's default
--     fail     = { ... },
--     reward   = spec,             -- given once the event finishes
--     step     = false,            -- a hint: doesn't advance or reward
--     accept   = "Quest Name",     -- or complete = / mission = : the message
--     music    = id,               -- with the message
--     as       = "Other NPC",      -- swap this NPC for another during the event
--     object   = true,             -- no NPC name (signs, markers)
--     after    = function(ctx) end,
-- })
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

LQS.dialog = function(obj)
    local check = P.compileCheck(obj.check)

    return P.handler("dialog", { obj = obj,
        onTrigger = function(ctx)
            local player, npc = ctx.player, ctx.npc

            -- A reward from this quest is still on its way
            if ctx:isLocked() then
                return
            end

            if check ~= nil and not check(player) then
                if obj.fail ~= nil then
                    LQS.event(player, npc, obj.fail, ctx)
                else
                    P.showDefault(ctx)
                end

                return
            end

            local event = obj.event

            if not P.eventSpawn(obj, player, npc, event) then
                -- An object (sign, marker) speaks without a name
                local speaker = npc

                if obj.object then
                    speaker = nil
                end

                LQS.event(player, speaker, event, ctx)
            end

            -- A hint or reminder: nothing more
            if obj.step == false then
                return
            end

            ctx:lockedAfter(LQS.eventDelay(event), function()
                if obj.reward ~= nil and not ctx:reward(obj.reward) then
                    return
                end

                ctx:advance()
                P.questMessage(player, obj, ctx.quest.info)

                if obj.after ~= nil then
                    obj.after(ctx)
                end
            end)
        end,
    })
end

-----------------------------------
-- Extra helpers
-----------------------------------
LQS.nothingElse = function()
    return LQS.dialog({
        step   = false,
        object = true,
        event  =
        {
            "There is nothing else to do here.",
        },
    })
end

return {}
