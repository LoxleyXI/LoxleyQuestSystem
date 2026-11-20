-----------------------------------
-- LQS: Step requirements: LQS.checks
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

-----------------------------------
-- LQS.checks
-----------------------------------
P.checkList =
{
    eval = function(player, val)
        return val(player, val)
    end,

    gm = function(player, val)
        return (player:getGMLevel() > 0) == val
    end,

    level = function(player, val)
        return player:getMainLvl() >= val
    end,

    job  = function(player, val)
        return player:getMainJob() == val
    end,

    jobvar = function(player, var)
        return player:getMainJob() == player:getCharVar(var)
    end,

    vareq = function(player, val)
        return player:getCharVar(val[1]) == val[2]
    end,

    varin = function(player, tbl)
        local val = player:getCharVar(tbl[1])

        for _, varVal in pairs(tbl[2]) do
            if val == varVal then
                return true
            end
        end

        return false
    end,

    vargt = function(player, val)
        return player:getCharVar(val[1]) > val[2]
    end,

    varlt = function(player, val)
        return player:getCharVar(val[1]) < val[2]
    end,

    varlist = function(player, val)
        for _, varInfo in pairs(val) do
            if player:getCharVar(varInfo[1]) < varInfo[2] then
                return false
            end
        end

        return true
    end,

    zero = function(player, variable)
        return player:getCharVar(variable) == 0
    end,

    allzero = function(player, variable)
        local zoneID   = player:getZoneID()
        local alliance = player:getAlliance()

        for _, member in pairs(alliance) do
            if
                member ~= nil and
                member:isPC() and
                member:getZoneID() == zoneID
            then
                if member:getCharVar(variable) ~= 0 then
                    return false
                end
            end
        end

        return true
    end,

    timeout = function(player, variable)
        return GetSystemTime() < player:getCharVar(variable)
    end,

    cooldown = function(player, variable)
        return GetSystemTime() > player:getCharVar(variable)
    end,

    bool = function(player, val)
        return val
    end,

    item = function(player, item)
        return player:hasItem(item)
    end,

    ki = function(player, keyItem)
        return player:hasKeyItem(keyItem)
    end,

    skill = function(player, skillInfo)
        return player:getCharSkillLevel(skillInfo[1]) >= skillInfo[2]
    end,

    quest = function(player, questInfo)
        return player:hasCompletedQuest(questInfo[1], questInfo[2])
    end,

    -----------------------------------
    -- Teleporter-related checks
    -----------------------------------
    gil = function(player, val)
        return player:getGil() >= val
    end,

    cp = function(player, val)
        return player:getCP() >= val
    end,

    rank = function(player, val)
        if type(val) == "number" then
            return player:getRank(player:getNation()) >= val
        elseif type(val) == "table" then
            return player:getRank(val[1]) >= val[2]
        end
        return false
    end,

    hasTeleport = function(player, val)
        if type(val) == "number" then
            return player:hasTeleport(player:getNation(), val + 5)
        elseif type(val) == "table" then
            return player:hasTeleport(val[1], val[2] + 5)
        end
        return false
    end,

    currency = function(player, val)
        return player:getCurrency(val[1]) >= val[2]
    end,
}

LQS.checks = function(tbl)
    return function(player)
        local pass = true

        for k, v in pairs(tbl) do
            local check = P.checkList[k] or P.checkList[string.lower(k)]

            if check == nil then
                print(fmt("[LQS] Unknown check '{}' (it always fails)", k))
                pass = false
            elseif not check(player, v) then
                pass = false
            end
        end

        return pass
    end
end

P.conditional =
{
    ["job"] = function(player, tbl)
        return tbl[player:getMainJob()]
    end,
}

return {}
