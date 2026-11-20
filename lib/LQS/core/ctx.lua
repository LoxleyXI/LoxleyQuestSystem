-----------------------------------
-- LQS: ctx, what every handler receives
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
--
-- Fields: player, npc, mob, trade, quest ({ name, var, info }), step (the
-- player's step: var + 1), entity (this entity's definition), isKiller.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

local Ctx   = {}
Ctx.__index = Ctx
P.Ctx       = Ctx

function P.newCtx(fields)
    return setmetatable(fields, Ctx)
end

-- For your own code: call a handler yourself, eg. onTrigger(LQS.ctx({ player = player, npc = npc }))
LQS.ctx = function(fields)
    return P.newCtx(fields or {})
end

-- An event, or the key of one in this entity's dialog table ("START").
-- A string is always a key (validation checks the key exists).
function P.eventOf(ctx, event)
    if type(event) == "string" then
        local dialog = ctx and ctx.entity and ctx.entity.dialog
        event = type(dialog) == "table" and dialog[event] or nil
    end

    -- { byJob = { [xi.job.WAR] = event, default = event } }: chosen by main job
    if type(event) == "table" and event.byJob ~= nil and ctx ~= nil and ctx.player ~= nil then
        event = event.byJob[ctx.player:getMainJob()] or event.byJob.default
        return P.eventOf(ctx, event)
    end

    return event
end

-- The quest var
function Ctx:var()
    return self.player:getCharVar(self.quest.var)
end

function Ctx:setVar(value)
    self.player:setCharVar(self.quest.var, value)
end

-- This step done (or n steps on): absolute, so a repeated call can't skip ahead
function Ctx:advance(n)
    self:setVar(self.step - 1 + (n or 1))
end

-- Run an event as this NPC (or as the mob, for mob handlers)
function Ctx:event(event)
    LQS.event(self.player, self.npc, event, self)
end

function Ctx:find(name)
    return P.getEntity(self.player, name)
end

-- In a dialog or menu right now
function Ctx:busy()
    return self.player:getLocalVar("[LQS]BLOCKING") == 1
end

-----------------------------------
-- The reward lock: one per player and quest, so a player can't collect a reward
-- twice by talking or trading again before the first one lands. Local vars are
-- numbers, so the quest var is part of the name.
-----------------------------------
local function lockName(ctx)
    return "[LQS]LOCK" .. (ctx.quest and ctx.quest.var or "")
end

function Ctx:isLocked()
    return self.player:getLocalVar(lockName(self)) == 1
end

function Ctx:lock()
    if self:isLocked() then
        return false
    end

    self.player:setLocalVar(lockName(self), 1)
    self.holding = true
    return true
end

function Ctx:unlock()
    self.player:setLocalVar(lockName(self), 0)
    self.holding = false
end

-- Run fn under the lock; the lock is always released, even if fn errors.
-- Returns fn's result, or false if the lock was already held.
function Ctx:locked(fn)
    if not self:lock() then
        return false
    end

    local ok, result = pcall(fn, self)
    self:unlock()

    if not ok then
        print(fmt("[LQS] {}: {}", self.quest and self.quest.name or "?", result))
        return false
    end

    return result
end

-- Take the lock now, run fn after delay ms, release when it's done (or errors).
-- For rewards that land after an event finishes. Returns false if already locked.
function Ctx:lockedAfter(delay, fn)
    if not self:lock() then
        return false
    end

    local ctx = self

    self.player:timer(delay, function()
        local ok, result = pcall(fn, ctx)
        ctx:unlock()

        if not ok then
            print(fmt("[LQS] {}: {}", ctx.quest and ctx.quest.name or "?", result))
        end
    end)

    return true
end

-- Give a reward spec, all or nothing; true only if all of it was given.
-- Takes the lock unless this ctx already holds it (as builders do).
function Ctx:reward(spec)
    local function give()
        return P.giveReward(self.player, spec, self.quest and string.lower(self.quest.name or ""), self)
    end

    if self.holding then
        return give()
    end

    return self:locked(give) == true
end

return {}
