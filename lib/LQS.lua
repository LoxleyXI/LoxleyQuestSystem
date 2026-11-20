-----------------------------------
-- Loxley Quest System (LQS)
-----------------------------------
-- Copyright (c) 2025 LoxleyXI
--
-- https://github.com/LoxleyXI/LoxleyQuestSystem
-----------------------------------
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see http://www.gnu.org/licenses/
-----------------------------------
local m = Module:new("LQS_Loxley_Quest_System")
-----------------------------------
-- Define globally for reloads and persistence between files
LQS          = LQS or {}
LQS.registry = LQS.registry or {}
LQS.VERSION  = "2.4.0"

LQS.settings =
{
    -- Respawn of spawners
    RESPAWN = 180000, -- 3 minutes
    DEBUG   = false,  -- Enable debugging mode
    -- "refuse": a quest with faults doesn't load. "warn": it loads anyway (faults printed)
    VALIDATE = "refuse",
}

-- Pull optional setting overrides from LSB map settings
if xi.settings.main.LQS ~= nil then
    LQS.settings.RESPAWN = xi.settings.main.LQS.RESPAWN or LQS.settings.RESPAWN
    LQS.settings.DEBUG   = xi.settings.main.LQS.DEBUG   or LQS.settings.DEBUG
end

LQS.marker =
{
    SPARKLE  = 1382,
    BLUE     = 2424,
    FRAGMENT = 2357,
    SHIMMER  = 2326,
}

LQS.MAIN_QUEST   = "MAIN_QUEST"
LQS.SIDE_QUEST   = "SIDE_QUEST"
LQS.NOTHING      = { { object = true }, "You see nothing out of the ordinary." }
LQS.NOTHING_ELSE = { { object = true }, "There is nothing else to do here."    }
LQS.LOCKED       = { { object = true }, "It's locked." }

LQS.standardImmunities =
{
    xi.immunity.DARK_SLEEP,
    xi.immunity.GRAVITY,
    xi.immunity.LIGHT_SLEEP,
    xi.immunity.PETRIFY,
    xi.immunity.SILENCE,
    xi.immunity.TERROR,
}

-- Entity size
LQS.LARGE       = 2
LQS.EXTRA_LARGE = 3

-- Rates
LQS.GUARANTEED  = 1000 -- 100%
LQS.VERY_COMMON =  240 --  24%
LQS.COMMON      =  150 --  15%
LQS.UNCOMMON    =  100 --  10%
LQS.RARE        =   50 --   5%
LQS.VERY_RARE   =   10 --   1%
LQS.SUPER_RARE  =    5 -- 0.5%
LQS.ULTRA_RARE  =    1 -- 0.1%

-----------------------------------
-- Prevents Treasure Caskets spawning for custom quest mobs
-----------------------------------
m:addOverride("xi.caskets.spawnCasket", function(player, mob, x, y, z, r)
    if mob:getLocalVar("NO_CASKET") == 1 then
        return
    else
        super(player, mob, x, y, z, r)
    end
end)

return m
