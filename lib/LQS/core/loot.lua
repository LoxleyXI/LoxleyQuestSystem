-----------------------------------
-- LQS: Loot pools, additional effects and small helpers
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

-----------------------------------
-- Core utils
-----------------------------------
function P.delaySendMenu(player, menu)
    player:timer(300, function(playerArg)
        playerArg:customMenu(menu)
    end)
end

LQS.pickItem = function(items, mod)
    -- sum weights
    local sum = 0
    for i = 1, #items do
        if
            mod ~= nil and
            type(items[i][1]) == "table"
        then
            sum = sum + items[i][1][mod]
        else
            sum = sum + items[i][1]
        end
    end

    -- pick weighted result
    local item = items[1]
    local pick = math.random(1, sum)
    sum = 0

    for i = 1, #items do
        if
            mod ~= nil and
            type(items[i][1]) == "table"
        then
            sum = sum + items[i][1][mod]
        else
            sum = sum + items[i][1]
        end

        if sum >= pick then
            item = items[i]
            break
        end
    end

    return item
end

LQS.lootPool = function(player, pools)
    for _, pool in pairs(pools) do
        local result = LQS.pickItem(pool)
        local qty    = 1

        if result == nil then
            print(fmt("[LQS] pickItem returned a nil result in quest pool (Player: {}, Zone: {})", player:getName(), player:getZoneName()))
        else
            if result[4] ~= nil then
                qty = math.random(result[3], result[4])
            elseif result[3] ~= nil then
                qty = result[3]
            end

            if result[2] == nil then
                print(fmt("[LQS] pickItem returned a nil item ID in quest pool (Player: {}, Zone: {})", player:getName(), player:getZoneName()))
            elseif result[2] ~= 0 then
                npcUtil.giveItem(player, { { result[2], qty } })
            end
        end
    end
end

-----------------------------------
-- Treasure Pool (for party lotting)
-----------------------------------
LQS.treasurePool = function(player, pools, source)
    for _, pool in pairs(pools) do
        local result = LQS.pickItem(pool)

        if result == nil then
            print(fmt("[LQS] pickItem returned a nil result in treasure pool (Player: {}, Zone: {})", player:getName(), player:getZoneName()))
        elseif result[2] == nil then
            print(fmt("[LQS] pickItem returned a nil item ID in treasure pool (Player: {}, Zone: {})", player:getName(), player:getZoneName()))
        elseif result[2] ~= 0 then
            player:addTreasure(result[2], source)
        end
    end
end

-----------------------------------
-- Power for an additional effect whose caller didn't specify a power range. Averages half
-- the mob's level, so this scales.
-----------------------------------
LQS.defaultRiderPower = function(mob)
    local level = mob:getMainLvl()

    return math.random(math.max(1, math.floor(level / 3)), math.max(1, math.floor(level * 2 / 3)))
end

-----------------------------------
-- Additional effects - legacy content support
--
-- This function applies a damage addeffect with the power xi.mob.onAddEffect calculated before the
-- LSB refactor in 2026. Damage is resistable. actorStat is left unset on purpose.
-----------------------------------
LQS.addEffectDamage = function(mob, target, damage, element, params)
    params = params or {}

    local basePower = params.power

    if not basePower then
        local dMod = mob:getStat(xi.mod.INT) - target:getStat(xi.mod.INT)

        if dMod > 20 then
            dMod = 20 + (dMod - 20) / 2
        end

        basePower = math.max(dMod, 0) + target:getMainLvl() - mob:getMainLvl() + damage / 2
    end

    return xi.combat.action.executeAddEffectDamage(mob, target,
    {
        chance         = params.chance or 100,
        attackType     = params.attackType or xi.attackType.MAGICAL,
        magicalElement = element,
        basePower      = basePower,
        canMAB         = params.canMAB or false,
        canResist      = true,
    })
end

LQS.addEffectStatus = function(mob, target, effectId, params)
    params = params or {}

    return xi.combat.action.executeAddEffectEnfeeblement(mob, target,
    {
        chance   = params.chance or 100,
        effectId = effectId,
        power    = params.power or 0,
        duration = params.duration or 120,
        element  = params.element or xi.element.NONE,
    })
end

-----------------------------------
-- Reads an "aeffect" rider spec, in any of four shapes:
--   { element = xi.element.FIRE, minPower, maxPower }     damaging rider, power range optional
--   { effect = xi.effect.PARALYSIS, power =, duration = } status rider
--   { xi.mob.ae.POISON, minPower, maxPower }              a key xi.mob.onAddEffect still ships
--   xi.mob.ae.POISON                                      as above, with default power
-- A damaging AE with no set range falls back to LQS.defaultRiderPower.
-----------------------------------
LQS.addEffectFromSpec = function(mob, target, damage, spec, params)
    params = params or {}

    if type(spec) ~= "table" then
        return xi.mob.onAddEffect(mob, target, damage, spec, params)
    end

    if spec.element and not spec.effect then
        if not params.power then
            params.power = spec[1] and spec[2] and math.random(spec[1], spec[2]) or LQS.defaultRiderPower(mob)
        end

        return LQS.addEffectDamage(mob, target, damage, spec.element, params)
    end

    if spec.effect then
        return LQS.addEffectStatus(mob, target, spec.effect,
        {
            chance   = params.chance or spec.chance,
            power    = params.power or spec.power,
            duration = params.duration or spec.duration,
            element  = spec.element,
        })
    end

    if not params.power and spec[2] and spec[3] then
        params.power = math.random(spec[2], spec[3])
    end

    return xi.mob.onAddEffect(mob, target, damage, spec[1], params)
end

LQS.randomNoRepeat = function(size, exclude)
    local range = {}

    for i = 1, size do
        if i ~= exclude then
            table.insert(range, i)
        end
    end

    return range[math.random(1, #range)]
end

return {}
