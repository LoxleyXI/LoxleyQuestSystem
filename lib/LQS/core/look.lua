-----------------------------------
-- LQS: NPC looks: LQS.look, LQS.face
-----------------------------------
-- Part of the Loxley Quest System. LSB loads lib/LQS/ before lib/LQS.lua, and
-- the parts in name order, so nothing here may call another part while loading:
-- shared helpers live on LQS._ and are looked up when they run.
-----------------------------------
LQS   = LQS or {}
LQS._ = LQS._ or {}

local P = LQS._

-----------------------------------
-- Dynamic Entity Looks
-----------------------------------
local decToLE = function(num)
    local hex = string.format("%04x", num)
    return string.sub(hex, 3, 4) .. string.sub(hex, 1, 2)
end

local modelSlot = { "head", "body", "hand", "legs", "feet", "main", "offh" }

LQS.face =
{
    A1 = 0,
    B1 = 1,
    A2 = 2,
    B2 = 3,
    A3 = 4,
    B3 = 5,
    A4 = 6,
    B4 = 7,
    A5 = 8,
    B5 = 9,
    A6 = 10,
    B6 = 11,
    A7 = 12,
    B7 = 13,
    A8 = 14,
    B8 = 15,
}

LQS.look = function(tbl)
    local str = "00"  -- NPC or Mob

    if tbl.face then
        str = str .. string.format("%02x", tbl.face)
    else
        str = str .. "01"
    end

    if tbl.race then
        str = str .. string.format("%02x", tbl.race)
    else
        str = str .. "01"
    end

    for k, v in pairs(modelSlot) do
        if tbl[v] then
            str = str .. decToLE(tbl[v])
        else
            str = str .. "0000"
        end
    end

    str = str .. "0000" -- Ranged slot

    return "0x01" .. string.upper(str)
end

return {}
