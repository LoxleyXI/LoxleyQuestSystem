-----------------------------------
-- LQS test harness: a fake LandSandBoat map server
-----------------------------------
-- Just enough of LSB for LQS and its quests to run without a server or database:
-- players, NPCs, mobs, zones, timers, menus and trades. Every call is logged.
--
-- Fidelity rules:
--   * LSB's real enums (scripts/enum) and npc_util.lua are loaded, not imitated
--   * entity methods that exist in LSB (or in a listed C++ module) but aren't
--     modelled here are logged no-ops; methods that don't exist anywhere are nil,
--     as sol2 makes them, so calling one fails the way it would on a server
-----------------------------------
local S = {}

local LSB_DIR = os.getenv("LSB_DIR")

if not LSB_DIR or LSB_DIR == "" then
    io.stderr:write("LSB_DIR is not set: point it at a LandSandBoat checkout\n")
    os.exit(2)
end

-----------------------------------
-- Clock and timers
-----------------------------------
local clock = { now = 0, queue = {}, seq = 0 }
S.clock = clock

function clock.schedule(ms, fn, label)
    clock.seq = clock.seq + 1
    table.insert(clock.queue, { at = clock.now + (tonumber(ms) or 0), seq = clock.seq, fn = fn, label = label })
end

-- Run timers in time order until none are due before `untilMs`. The default horizon
-- is ten minutes of game time: long enough for any event, and it stops repeating
-- timers (heartbeats, wave spawners) from running forever.
clock.HORIZON = 600000

function clock.run(untilMs)
    local guard = 0
    untilMs = untilMs or (clock.now + clock.HORIZON)

    while #clock.queue > 0 do
        table.sort(clock.queue, function(a, b)
            if a.at == b.at then
                return a.seq < b.seq
            end

            return a.at < b.at
        end)

        local nextTimer = clock.queue[1]

        if untilMs and nextTimer.at > untilMs then
            break
        end

        table.remove(clock.queue, 1)
        clock.now = math.max(clock.now, nextTimer.at)
        S.protect("timer " .. (nextTimer.label or ""), nextTimer.fn)

        guard = guard + 1
        if guard > 100000 then
            S.fail("timer loop: more than 100,000 timers fired")
            break
        end
    end

    -- Only jump the clock forward when nothing is left to wait for, or when asked to
    if #clock.queue > 0 then
        clock.now = math.max(clock.now, untilMs)
    end
end

function clock.advance(ms)
    clock.run(clock.now + ms)
end

-----------------------------------
-- Log and errors
-----------------------------------
S.log    = {}
S.errors = {}

function S.record(kind, data)
    data      = data or {}
    data.kind = kind
    data.t    = clock.now
    table.insert(S.log, data)
end

function S.fail(msg)
    table.insert(S.errors, msg)
    S.record("error", { text = msg })
end

-- Call fn, catching Lua errors with a traceback (the server would log and carry on)
function S.protect(label, fn, ...)
    local args = { ... }
    local n    = select("#", ...)
    local ok, result = xpcall(function()
        return fn(unpack(args, 1, n))
    end, debug.traceback)

    if not ok then
        S.fail(string.format("%s: %s", label, tostring(result)))
        return nil
    end

    return result
end

-----------------------------------
-- LSB bindings (names only), for the strict entity lookup
-----------------------------------
local bindings = {}
S.bindings     = bindings

local function readBindings(path, pattern)
    local f = io.open(path, "r")

    if not f then
        return false
    end

    for line in f:lines() do
        for name in line:gmatch(pattern) do
            bindings[name] = true
        end
    end

    f:close()
    return true
end

function S.loadBindings(extraCpp)
    -- lua_baseentity.cpp, renamed lua_base_entity.cpp in late 2026
    if
        not readBindings(LSB_DIR .. "/src/map/lua/lua_base_entity.cpp", 'SOL_REGISTER%("([%w_]+)"') and
        not readBindings(LSB_DIR .. "/src/map/lua/lua_baseentity.cpp", 'SOL_REGISTER%("([%w_]+)"')
    then
        error("LSB_DIR has no src/map/lua/lua_base_entity.cpp: " .. LSB_DIR)
    end

    for _, path in ipairs(extraCpp or {}) do
        readBindings(path, 'lua%["CBaseEntity"%]%["([%w_]+)"%]')
    end
end

-----------------------------------
-- Entities
-----------------------------------
local world = { zones = {}, zonesByName = {}, entities = {}, nextId = 17000000, players = {} }
S.world     = world

local Entity = {}

local function newId()
    world.nextId = world.nextId + 1
    return world.nextId
end

-- Strict lookup: modelled method, else a logged no-op if LSB has it, else nil
local function entityIndex(self, key)
    local method = Entity[key]

    if method ~= nil then
        return method
    end

    if bindings[key] then
        return function(selfArg, ...)
            S.record("call", { entity = rawget(selfArg, "name"), method = key, args = { ... } })
            return nil
        end
    end

    return nil
end

local entityMeta = { __index = entityIndex, __tostring = function(e) return "Entity(" .. tostring(rawget(e, "name")) .. ")" end }

local function newEntity(fields)
    local e = fields or {}
    e.id        = e.id or newId()
    e.localVars = e.localVars or {}
    e.status    = e.status or 0
    e.animation = e.animation or 0
    e.pos       = e.pos or { x = 0, y = 0, z = 0, rot = 0 }
    e.effects   = e.effects or {}
    e.listeners = e.listeners or {}
    setmetatable(e, entityMeta)
    world.entities[e.id] = e
    return e
end

S.newEntity = newEntity

-- Identity
function Entity:getID()         return self.id end
function Entity:getTargID()     return self.id % 4096 end
function Entity:getName()       return self.name end
function Entity:getPacketName() return self.packetName or self.name end
function Entity:getObjType()    return self.objtype end
function Entity:isPC()          return self.objtype == xi.objType.PC end
function Entity:isNPC()         return self.objtype == xi.objType.NPC end
function Entity:isMob()         return self.objtype == xi.objType.MOB end
function Entity:getZone()       return self.zone end
function Entity:getZoneID()     return self.zone and self.zone.id or 0 end
function Entity:getZoneName()   return self.zone and self.zone.name or "" end

-- Local vars
function Entity:getLocalVar(name)        return self.localVars[name] or 0 end
function Entity:setLocalVar(name, value) self.localVars[name] = value end

-- Timers
function Entity:timer(ms, fn)
    local selfRef = self
    clock.schedule(ms, function()
        fn(selfRef)
    end, rawget(self, "name"))
end

-- Position
function Entity:getPos() return { x = self.pos.x, y = self.pos.y, z = self.pos.z, rot = self.pos.rot } end
function Entity:getXPos() return self.pos.x end
function Entity:getYPos() return self.pos.y end
function Entity:getZPos() return self.pos.z end
function Entity:getRotPos() return self.pos.rot end

function Entity:checkDistance(other, y, z)
    local ox, oy, oz

    if type(other) == "table" and other.pos and getmetatable(other) == getmetatable(self) then
        ox, oy, oz = other.pos.x, other.pos.y, other.pos.z
    elseif type(other) == "table" then
        ox, oy, oz = other.x or other[1], other.y or other[2], other.z or other[3]
    else
        ox, oy, oz = other, y, z
    end

    local dx, dy, dz = self.pos.x - ox, self.pos.y - oy, self.pos.z - oz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Entity:setPos(x, y, z, rot, zoneId)
    if type(x) == "table" then
        x, y, z, rot, zoneId = x.x or x[1], x.y or x[2], x.z or x[3], x.rot or x[4], x.zone or x[5]
    end

    self.pos = { x = x or 0, y = y or 0, z = z or 0, rot = rot or 0 }

    if zoneId ~= nil and zoneId ~= self:getZoneID() then
        S.record("zone", { entity = self.name, zone = zoneId })
        S.moveTo(self, zoneId)
    end
end

-- Status and animation
function Entity:getStatus()           return self.status end
function Entity:setStatus(status)     self.status = status end
function Entity:getAnimation()        return self.animation end
function Entity:setAnimation(anim)    self.animation = anim end

-- Status effects
function Entity:addStatusEffect(effect, power, tick, duration, ...)
    if type(effect) == "table" then
        effect = effect.effect
    end

    self.effects[effect] = { power = power or 0, duration = duration }
    S.record("effect", { entity = self.name, effect = effect, power = power })
    return true
end

function Entity:addStatusEffectEx(effect, icon, power, ...)
    return self:addStatusEffect(effect, power)
end

function Entity:hasStatusEffect(effect) return self.effects[effect] ~= nil end

function Entity:delStatusEffect(effect)
    local had = self.effects[effect] ~= nil
    self.effects[effect] = nil
    return had
end

function Entity:getStatusEffect(effect)
    local e = self.effects[effect]

    if not e then
        return nil
    end

    return {
        getPower    = function() return e.power end,
        getDuration = function() return e.duration end,
    }
end

-- Listeners
function Entity:addListener(event, name, fn)
    self.listeners[name] = { event = event, fn = fn }
end

function Entity:removeListener(name)
    self.listeners[name] = nil
end

function Entity:fireListeners(event, ...)
    for _, l in pairs(self.listeners) do
        if l.event == event then
            S.protect("listener " .. event, l.fn, self, ...)
        end
    end
end

-- Model
function Entity:setModelId(id)   self.look = id end
function Entity:setLookString(s) self.look = s end
function Entity:getModelId()     return type(self.look) == "number" and self.look or 0 end

-- Client-side spawn per player (lqs_util.cpp), tracked so tests can see what a player sees
function Entity:ceSpawn(player)
    self.seenBy = self.seenBy or {}
    self.seenBy[player.id] = true
    S.record("ceSpawn", { entity = self.name })
end

function Entity:ceDespawn(player)
    self.seenBy = self.seenBy or {}
    self.seenBy[player.id] = false
    S.record("ceDespawn", { entity = self.name })
end

-----------------------------------
-- Players
-----------------------------------
local INVENTORY_SIZE = 80

function S.newPlayer(opts)
    opts = opts or {}

    local p = newEntity({
        name        = opts.name or "Tester",
        objtype     = xi.objType.PC,
        charVars    = {},
        varExpiry   = {},
        inventory   = {},
        keyItems    = {},
        currencies  = {},
        titles      = {},
        quests      = {},
        teleports   = {},
        ranks       = {},
        skills      = {},
        containers  = {},
        gil         = opts.gil or 0,
        level       = opts.level or 75,
        job         = opts.job or xi.job.WAR,
        subJob      = opts.subJob or xi.job.NIN,
        gmLevel     = opts.gm or 0,
        nation      = opts.nation or 0,
        cp          = 0,
        exp         = 0,
        freeSlots   = opts.freeSlots or INVENTORY_SIZE,
        hp          = 1000,
        mp          = 500,
        tp          = 0,
    })

    table.insert(world.players, p)

    if opts.zone then
        S.moveTo(p, opts.zone)
    end

    return p
end

function Entity:getCharVar(name)
    local expiry = self.varExpiry[name]

    if expiry and expiry > 0 and S.systemTime() >= expiry then
        self.charVars[name]  = nil
        self.varExpiry[name] = nil
    end

    return self.charVars[name] or 0
end

function Entity:setCharVar(name, value, expiry)
    -- LSB takes numbers only; anything else throws on a real server
    if (expiry ~= nil and type(expiry) ~= "number") or (value ~= nil and type(value) ~= "number") then
        error(string.format("setCharVar('%s', %s, %s): value and expiry must be numbers", tostring(name), type(value), type(expiry)), 2)
    end

    value = value or 0
    S.record("var", { var = name, value = value, old = self.charVars[name] or 0 })

    if value == 0 then
        self.charVars[name]  = nil
        self.varExpiry[name] = nil
    else
        self.charVars[name]  = value
        self.varExpiry[name] = expiry
    end
end

function Entity:incrementCharVar(name, amount)
    self:setCharVar(name, self:getCharVar(name) + (amount or 1), self.varExpiry[name])
end

-- Text the player sees
local function say(self, channel, text)
    S.record("text", { channel = channel, text = tostring(text) })
end

function Entity:fmt(text, ...)          say(self, "fmt", S.fmt(text, ...)) end
function Entity:sys(text, ...)          say(self, "sys", S.fmt(text, ...)) end
function Entity:printToPlayer(text, ch) say(self, "print", text) end
function Entity:messageSpecial(id, ...) say(self, "special", string.format("special %s %s", tostring(id), table.concat({ ... }, ","))) end
function Entity:messageBasic(id, ...)   say(self, "basic", tostring(id)) end
function Entity:messageSystem(id, ...)  say(self, "system", tostring(id)) end
function Entity:messageText(...)        say(self, "text", "messageText") end
function Entity:showText(npc, id)       say(self, "showText", tostring(id)) end

-- Character
function Entity:getMainJob()          return self.job end
function Entity:getSubJob()           return self.subJob end
function Entity:getMainLvl()          return self.level end
function Entity:getSubLvl()           return math.floor((self.level or 1) / 2) end
function Entity:getJobLevel(job)      return job == self.job and self.level or 0 end
function Entity:getGMLevel()          return self.gmLevel or 0 end
function Entity:getNation()           return self.nation or 0 end
function Entity:getRank(nation)       return self.ranks[nation or self.nation] or 1 end
function Entity:getCP()               return self.cp end
function Entity:getCharSkillLevel(s)  return self.skills[s] or 0 end
function Entity:addExp(amount)        self.exp = self.exp + amount; S.record("exp", { amount = amount }) end
function Entity:addTitle(title)       self.titles[title] = true; S.record("title", { title = title }) end
function Entity:hasTitle(title)       return self.titles[title] == true end

function Entity:getHP()      return self.hp end
function Entity:getMaxHP()   return self.maxHP or 1000 end
function Entity:getMP()      return self.mp end
function Entity:getMaxMP()   return self.maxMP or 500 end
function Entity:getTP()      return self.tp end
function Entity:getHPP()     return math.floor(100 * self.hp / self:getMaxHP()) end
function Entity:setHP(hp)    self.hp = hp end
function Entity:setMP(mp)    self.mp = mp end
function Entity:setTP(tp)    self.tp = tp end
function Entity:addHP(hp)    self.hp = math.min(self:getMaxHP(), self.hp + hp) end
function Entity:addMP(mp)    self.mp = math.min(self:getMaxMP(), self.mp + mp) end
function Entity:isAlive()    return (self.hp or 0) > 0 and not self.dead end
function Entity:isDead()     return not self:isAlive() end

function Entity:getFameLevel(area)   return 9 end
function Entity:getLevelCap()        return self.levelCap or 75 end
function Entity:setLevelCap(cap)     self.levelCap = cap end
function Entity:getAllianceSize()    return #(self.party or { self }) end
function Entity:getDeaths()          return self.deaths or {} end

function Entity:getPet()      return nil end
function Entity:getParty()    return { self } end
function Entity:getAlliance() return self.party or { self } end
function Entity:getPartySize() return #(self.party or { self }) end

function Entity:hasCompletedQuest(log, quest) return self.quests[log .. ":" .. quest] == true end
function Entity:hasTeleport(nation, bit)      return self.teleports[nation .. ":" .. bit] == true end

-- Money and currencies
function Entity:getGil()        return self.gil end
function Entity:addGil(amount)  self.gil = self.gil + amount; S.record("gil", { amount = amount }) end
function Entity:delGil(amount)  if self.gil < amount then return false end self.gil = self.gil - amount; S.record("gil", { amount = -amount }) return true end
function Entity:setGil(amount)  self.gil = amount end
function Entity:getCurrency(c)  return self.currencies[c] or 0 end
function Entity:addCurrency(c, amount) self.currencies[c] = self:getCurrency(c) + amount; S.record("currency", { currency = c, amount = amount }) end
function Entity:delCurrency(c, amount) self.currencies[c] = self:getCurrency(c) - amount; S.record("currency", { currency = c, amount = -amount }) end
function Entity:setCurrency(c, amount) self.currencies[c] = amount end

-- Items
function Entity:getFreeSlotsCount() return self.freeSlots end

function Entity:hasItem(itemId)
    return (self.inventory[itemId] or 0) > 0
end

function Entity:getItemCount(itemId)
    return self.inventory[itemId] or 0
end

-- addItem(id, qty, aug...) or addItem({ id = , quantity = , silent = , augment... })
function Entity:addItem(itemId, qty, ...)
    local augments = { ... }

    if type(itemId) == "table" then
        qty    = itemId.quantity or 1
        itemId = itemId.id
    end

    qty = qty or 1

    if self.freeSlots < 1 then
        return false
    end

    self.inventory[itemId] = (self.inventory[itemId] or 0) + qty
    self.freeSlots         = self.freeSlots - 1
    S.record("item", { item = itemId, qty = qty, augments = #augments > 0 and augments or nil, walker = S.walkerGiving or nil, treasure = S.treasureGiving or nil })
    return true
end

function Entity:delItem(itemId, qty)
    qty = qty or 1

    if (self.inventory[itemId] or 0) < qty then
        return false
    end

    self.inventory[itemId] = self.inventory[itemId] - qty

    if self.inventory[itemId] == 0 then
        self.inventory[itemId] = nil
        self.freeSlots         = self.freeSlots + 1
    end

    S.record("itemRemoved", { item = itemId, qty = qty })
    return true
end

-- lqs_util.cpp: false when the item is rare and already held
function Entity:canObtainItem(itemId)
    return self.freeSlots > 0
end

function Entity:hasKeyItem(ki)   return self.keyItems[ki] == true end
function Entity:addKeyItem(ki)   self.keyItems[ki] = true; S.record("keyitem", { ki = ki }) end
function Entity:delKeyItem(ki)   self.keyItems[ki] = nil end

function Entity:getContainerSize(bag)          return self.containers[bag] or 30 end
function Entity:changeContainerSize(bag, n)    self.containers[bag] = self:getContainerSize(bag) + n; S.record("slots", { bag = bag, amount = n }) end

function Entity:addTreasure(itemId, source, rate)
    S.record("treasure", { item = itemId, rate = rate })
    S.treasureGiving = true
    self:addItem(itemId, 1)
    S.treasureGiving = false
end

-- Trades: the walker builds a trade, then the handler confirms and completes it
function Entity:tradeComplete()
    local trade = self.currentTrade

    if trade then
        for itemId, qty in pairs(trade.confirmed) do
            if itemId == 65535 then
                self:delGil(qty)
            else
                self:delItem(itemId, qty)
            end
        end

        trade.completed = true
    end

    S.record("tradeComplete")
end

function Entity:confirmTrade() self:tradeComplete() end

function Entity:tradeRelease()
    if self.currentTrade then
        self.currentTrade.released = true
    end

    S.record("tradeRelease")
end

-- Menus (LSB core customMenu): the walker picks an option later
function Entity:customMenu(menu)
    self.openMenu = menu
    S.record("menu", { title = menu.title })

    if menu.onStart then
        menu.onStart(self)
    end
end

-- Music, costumes, misc player state
function Entity:changeMusic(slot, track) S.record("music", { slot = slot, track = track }) end
function Entity:setCostume(id)           self.costume = id end
function Entity:getCostume()             return self.costume or 0 end

-----------------------------------
-- NPCs and mobs
-----------------------------------
function Entity:isSpawned() return self.spawned == true end

function Entity:spawn()
    self.localVars = {} -- CBaseEntity::Spawn clears local vars
    self.spawned = true
    self.dead    = false
    self.hp      = self:getMaxHP()
    S.record("spawn", { entity = self.name })

    if self.def and self.def.onMobSpawn then
        S.protect("onMobSpawn " .. self.name, self.def.onMobSpawn, self)
    end

    -- A quest script's autoKill: a party that kills each mob this many ms after it appears
    if S.autoKill and self.objtype == xi.objType.MOB and S.autoKillBy then
        local mob = self
        clock.schedule(S.autoKill, function()
            if mob:isSpawned() then
                S.killMob(mob, S.autoKillBy)
            end
        end, "autoKill")
    end
end

function Entity:despawn()
    self.spawned = false
    S.record("despawn", { entity = self.name })
end

function Entity:setSpawn(x, y, z, rot) self.spawnPos = { x = x, y = y, z = z, rot = rot } end
function Entity:setMobLevel(level)     self.level = level end
function Entity:setMaxHP(hp)           self.maxHP = hp end
function Entity:updateHealth()         end
function Entity:getMobMod(mod)         return (self.mobMods or {})[mod] or 0 end

function Entity:setMobMod(mod, value)
    self.mobMods      = self.mobMods or {}
    self.mobMods[mod] = value
end

function Entity:getMod(mod)            return (self.mods or {})[mod] or 0 end

function Entity:setMod(mod, value)
    self.mods      = self.mods or {}
    self.mods[mod] = value
end

function Entity:addMod(mod, value)
    self:setMod(mod, self:getMod(mod) + value)
end

function Entity:delMod(mod, value)
    self:setMod(mod, self:getMod(mod) - value)
end

function Entity:getEnmityList()
    return {}
end

-- The walker's kill: run the death handlers as LSB does
function S.killMob(mob, killer)
    if not mob.spawned then
        return false
    end

    mob.hp      = 0
    mob.dead    = true
    mob.spawned = false
    S.record("death", { entity = mob.name })

    mob:fireListeners("DEATH", killer)

    if mob.def and mob.def.onMobDeath then
        for _, member in ipairs(killer:getAlliance()) do
            S.protect("onMobDeath " .. mob.name, mob.def.onMobDeath, mob, member, { isKiller = member == killer, isWeaponSkillKill = false })
        end
    end

    return true
end

-----------------------------------
-- Zones
-----------------------------------
local Zone   = {}
Zone.__index = function(self, key)
    if Zone[key] then
        return Zone[key]
    end

    return function()
        S.record("zoneCall", { method = key })
        return nil
    end
end

function S.getZone(idOrName)
    local zone = world.zones[idOrName] or world.zonesByName[idOrName]

    if zone then
        return zone
    end

    local id, name

    if type(idOrName) == "number" then
        id = idOrName

        for k, v in pairs(xi.zone) do
            if v == id then
                name = k
            end
        end
    else
        name = idOrName
        -- "Beadeaux_[S]" -> BEADEAUX_S, "Promyvion-Holla" -> PROMYVION_HOLLA
        local key = string.upper(idOrName):gsub("[%-%s]", "_"):gsub("[%[%]'%.]", ""):gsub("_+", "_"):gsub("_$", "")
        id = xi.zone[key]
    end

    if id == nil then
        -- A zone the enum doesn't know (a custom zone): give it an id of its own
        S.record("print", { text = "unknown zone " .. tostring(idOrName) })
        world.customZoneId = (world.customZoneId or 9000) + 1
        id = world.customZoneId
    end

    -- Zone names as LSB gives them: "Pashhow_Marshlands"
    local pretty = name and name:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end) or ("Zone" .. id)

    if type(idOrName) == "string" then
        pretty = idOrName
    end

    zone = setmetatable({ id = id, name = pretty, entities = {} }, Zone)
    world.zones[id]           = zone
    world.zonesByName[pretty] = zone
    return zone
end

-- rawget: the zone's __index answers any unknown key with a stub function
local function zoneVars(zone)
    local vars = rawget(zone, "localVars")

    if not vars then
        vars = {}
        rawset(zone, "localVars", vars)
    end

    return vars
end

function Zone:getLocalVar(name)        return zoneVars(self)[name] or 0 end
function Zone:setLocalVar(name, value) zoneVars(self)[name] = value end
function Zone:resetLocalVars()         rawset(self, "localVars", {}) end

function Zone:getID()   return self.id end
function Zone:getName() return self.name end

function Zone:queryEntitiesByName(name)
    local result = {}

    for _, e in ipairs(self.entities) do
        if e.name == name then
            table.insert(result, e)
        end
    end

    return result
end

function Zone:insertDynamicEntity(def)
    local e = newEntity({
        name       = "DE_" .. def.name,
        packetName = def.packetName or def.name,
        objtype    = def.objtype or xi.objType.NPC,
        look       = def.look,
        pos        = { x = def.x or 0, y = def.y or 0, z = def.z or 0, rot = def.rotation or 0 },
        level      = def.minLevel,
        def        = def,
        zone       = self,
    })

    table.insert(self.entities, e)
    S.record("insert", { entity = e.name, zone = self.name })

    if e.objtype == xi.objType.MOB then
        e.spawned = false
        e.hp      = 0

        if def.onMobInitialize then
            S.protect("onMobInitialize " .. e.name, def.onMobInitialize, e)
        end
    else
        e.spawned = true
    end

    return e
end

function Zone:getPlayers()
    local result = {}

    for _, p in ipairs(world.players) do
        if p.zone == self then
            result[p.id] = p
        end
    end

    return result
end

function S.moveTo(entity, zoneIdOrName)
    local zone = S.getZone(zoneIdOrName)
    entity.zone = zone
end

-- From here on a misspelt xi.item.NAME is an error, not a silent nil
-- (switched on just before the quest file loads, after the server's own files)
function S.strictItems()
    if xi.item then
        setmetatable(xi.item, { __index = function(_, key)
            error("xi.item." .. tostring(key) .. " does not exist", 2)
        end })
    end
end

-----------------------------------
-- Module load order: LSB expands an init.txt folder into a std::set<path>, which
-- compares paths component by component. So "LQS/x.lua" sorts before "LQS.lua"
-- ("LQS" < "LQS.lua"), and a folder's files load before a file named like it.
-----------------------------------
function S.moduleOrder(dir)
    local files = {}
    local p = io.popen("find '" .. dir .. "' -name '*.lua' -type f 2>/dev/null")

    for line in p:lines() do
        table.insert(files, line)
    end

    p:close()

    local function parts(path)
        local list = {}
        for part in path:gmatch("[^/]+") do
            table.insert(list, part)
        end
        return list
    end

    table.sort(files, function(a, b)
        local pa, pb = parts(a), parts(b)

        for i = 1, math.max(#pa, #pb) do
            if pa[i] == nil then return true end
            if pb[i] == nil then return false end
            if pa[i] ~= pb[i] then return pa[i] < pb[i] end
        end

        return false
    end)

    return files
end

-----------------------------------
-- Module system (modules/module_utils.lua)
-----------------------------------
S.overrides = {}

local Module   = {}
Module.__index = Module

function Module:new(name)
    return setmetatable({ name = name, overrides = {} }, Module)
end

function Module:addOverride(path, fn)
    table.insert(self.overrides, { path = path, fn = fn })
    table.insert(S.overrides, { module = self.name, path = path, fn = fn })
end

function Module:setEnabled() end

-- Call every override registered for a path (LSB chains them; super is a no-op here)
function S.callOverrides(path, ...)
    local called = 0

    for _, o in ipairs(S.overrides) do
        if o.path == path then
            _G.super = function() end
            S.protect(path, o.fn, ...)
            called = called + 1
        end
    end

    return called
end

-- Zones that quests added entities to
function S.overrideZones()
    local seen, result = {}, {}

    for _, o in ipairs(S.overrides) do
        local zoneName = o.path:match("^xi%.zones%.(.+)%.Zone%.onInitialize$")

        if zoneName and not seen[zoneName] then
            seen[zoneName] = true
            table.insert(result, zoneName)
        end
    end

    return result
end

function S.initZones()
    for _, zoneName in ipairs(S.overrideZones()) do
        local zone = S.getZone(zoneName)
        S.callOverrides(string.format("xi.zones.%s.Zone.onInitialize", zoneName), zone)
    end
end

-----------------------------------
-- Globals LSB provides
-----------------------------------
-- {} formatting, as the C++ fmt binding does
function S.fmt(text, ...)
    local args = { ... }
    local n    = select("#", ...)
    local i    = 0

    text = tostring(text)

    if n == 0 then
        return text
    end

    return (text:gsub("{[^{}]*}", function()
        i = i + 1

        if i > n then
            return "{}"
        end

        return tostring(args[i])
    end))
end

S.startTime = 1763600000 -- a fixed Earth time, so cooldowns and expiries are reproducible

function S.systemTime()
    return S.startTime + math.floor(clock.now / 1000)
end

local function autoTable(prefix, base)
    return setmetatable(base or {}, {
        __index = function(t, k)
            local v = autoTable(prefix .. "." .. tostring(k))
            rawset(t, k, v)
            return v
        end,
        __call = function()
            return nil
        end,
    })
end

local function loadEnums()
    local dir = LSB_DIR .. "/scripts/enum/"
    local p   = io.popen('ls "' .. dir .. '"')

    for file in p:lines() do
        if file:match("%.lua$") then
            local chunk, err = loadfile(dir .. file)

            if not chunk then
                error(err)
            end

            local ok, loadErr = pcall(chunk)

            if not ok then
                io.stderr:write("enum " .. file .. ": " .. tostring(loadErr) .. "\n")
            end
        end
    end

    p:close()

    -- Newer LSB keeps many enums in data/enums/*.yaml and builds xi.* tables from them
    -- at startup (keys upper-cased). Read the simple "values: key: number" form.
    local yp = io.popen('ls "' .. LSB_DIR .. '/data/enums/" 2>/dev/null')

    for file in yp:lines() do
        if file:match("%.yaml$") then
            local f = io.open(LSB_DIR .. "/data/enums/" .. file, "r")
            local tablePath, inValues = nil, false
            local values = {}

            for line in f:lines() do
                local t = line:match("^%s+table:%s*([%w_%.]+)")

                if t then
                    tablePath = t
                elseif line:match("^values:") then
                    inValues = true
                elseif inValues then
                    local key, num = line:match("^%s+([%w_]+):%s*(-?[%dxXa-fA-F]+)")

                    if key and tonumber(num) then
                        values[string.upper(key)] = tonumber(num)
                    elseif line:match("^%S") then
                        inValues = false
                    end
                end
            end

            f:close()

            if tablePath then
                local node = _G

                for part in tablePath:gmatch("[^%.]+") do
                    node[part] = node[part] or {}
                    node = node[part]
                end

                for k, v in pairs(values) do
                    if node[k] == nil then
                        node[k] = v
                    end
                end
            end
        end
    end

    yp:close()

    -- Datasets with an enum (data/status_effects.yaml builds xi.effect):
    -- "  name:" then "    id: N"
    local dp = io.popen('ls "' .. LSB_DIR .. '/data/" 2>/dev/null')

    for file in dp:lines() do
        if file:match("%.yaml$") then
            local f = io.open(LSB_DIR .. "/data/" .. file, "r")
            local tablePath, current = nil, nil
            local values = {}

            for line in f:lines() do
                local t = line:match("^%s+table:%s*([%w_%.]+)")

                if t and not tablePath then
                    tablePath = t
                else
                    local key = line:match("^  ([%w_]+):%s*$")

                    if key then
                        current = key
                    else
                        local id = line:match("^    id:%s*(%d+)")

                        if id and current then
                            values[string.upper(current)] = tonumber(id)
                        end
                    end
                end
            end

            f:close()

            if tablePath and next(values) then
                local node = _G

                for part in tablePath:gmatch("[^%.]+") do
                    node[part] = node[part] or {}
                    node = node[part]
                end

                for k, v in pairs(values) do
                    if node[k] == nil then
                        node[k] = v
                    end
                end
            end
        end
    end

    dp:close()
end

function S.boot(opts)
    opts = opts or {}

    math.randomseed(opts.seed or 1)

    _G.xi =
    {
        settings = { main = { GIL_RATE = 1, BAYLD_RATE = 1, EXP_RATE = 1, SHOP_PRICE = 1 } },
    }

    loadEnums()

    -- Namespaces that quests and LQS touch but tests don't model
    xi.zones   = xi.zones or {}
    xi.mob     = autoTable("xi.mob", xi.mob)
    xi.caskets = autoTable("xi.caskets", xi.caskets)
    xi.items   = autoTable("xi.items", xi.items)
    xi.module  = autoTable("xi.module", xi.module)

    _G.Module   = Module
    _G.fmt      = S.fmt
    _G.printf   = function(f, ...) S.record("print", { text = string.format(f, ...) }) end
    _G.print    = function(...)
        local parts = {}

        for i = 1, select("#", ...) do
            parts[i] = tostring((select(i, ...)))
        end

        S.record("print", { text = table.concat(parts, " ") })
    end

    _G.g_mixins = autoTable("g_mixins")
    _G.utils    = _G.utils or {}
    utils.clamp = utils.clamp or function(v, lo, hi) return math.max(lo, math.min(hi, v)) end

    -- Text ids by zone: any lookup gives a stable number
    local textIds = setmetatable({}, { __index = function(t, k)
        local v = 1000 + (#k * 7)
        rawset(t, k, v)
        return v
    end })

    _G.zones = setmetatable({}, { __index = function(t, k)
        local v = { text = textIds, mob = autoTable("mob"), npc = autoTable("npc") }
        rawset(t, k, v)
        return v
    end })

    _G.GetSystemTime   = S.systemTime
    _G.os              = setmetatable({ time = function(t) if t then return os_time(t) end return S.systemTime() end }, { __index = os })
    _G.JstMidnight     = function() return S.systemTime() + 86400 - (S.systemTime() % 86400) end
    _G.NextJstWeek     = function() return S.systemTime() + 7 * 86400 end
    _G.NextConquestTally = function() return S.systemTime() + 7 * 86400 end
    _G.NextGameTime    = function() return S.systemTime() + 3600 end
    _G.VanadielTime    = function() return S.systemTime() end
    _G.GetZone         = function(id) return world.zones[id] end
    _G.GetPlayerByID   = function(id) local e = world.entities[id]; return e and e:isPC() and e or nil end
    _G.GetPlayerByName = function(name) for _, p in ipairs(world.players) do if p.name == name then return p end end end
    _G.GetMobByID      = function(id) return world.entities[id] end
    _G.GetNPCByID      = function(id) return world.entities[id] end
    _G.DisallowRespawn = function() end
    _G.SpawnMob        = function(id) local e = world.entities[id]; if e then e:spawn() end return e end
    _G.DespawnMob      = function(id) local e = world.entities[id]; if e then e:despawn() end end
    _G.GetItemByID     = function(id)
        return {
            getID        = function() return id end,
            getBasePrice = function() return 100 end,
            getFlag      = function() return 0 end,
            getName      = function() return "item" .. id end,
        }
    end

    _G.GetNationRank   = function(nation) return 1 end

    -- luautils::NearLocation / utils nearPosition
    _G.NearLocation    = function(pos, offset, theta)
        local total = ((pos.rot or 0) / 256) * 2 * math.pi + theta
        return {
            x   = pos.x + math.cos(2 * math.pi - total) * offset,
            y   = pos.y,
            z   = pos.z + math.sin(2 * math.pi - total) * offset,
            rot = pos.rot,
        }
    end

    -- Any other global function LSB registers: a logged no-op
    local f = io.open(LSB_DIR .. "/src/map/lua/luautils.cpp", "r")

    if f then
        for line in f:lines() do
            local name = line:match('lua%.set_function%("([%w_]+)"')

            if name and rawget(_G, name) == nil then
                _G[name] = function(...)
                    S.record("global", { name = name })
                    return nil
                end
            end
        end

        f:close()
    end

    -- require: LSB module paths resolve to stubs or real files
    local modulesDir = opts.modulesDir
    local stubs = { ["modules/module_utils"] = true }

    table.insert(package.loaders, 2, function(name)
        if stubs[name] then
            return function() return Module end
        end

        if name:match("^scripts/") then
            local path = LSB_DIR .. "/" .. name .. ".lua"
            local f    = io.open(path, "r")

            if f then
                f:close()

                -- Globals already provided, or too tangled to load: stub
                if name:match("npc_util$") or name:match("mixins/") or name:match("interaction") then
                    return function() return {} end
                end

                return function() return dofile(path) end
            end

            return function() return {} end
        end

        if modulesDir and name:match("^modules/") then
            local path = modulesDir .. "/" .. name:gsub("^modules/", "") .. ".lua"
            local f    = io.open(path, "r")

            if f then
                f:close()
                return function() return dofile(path) end
            end
        end

        return nil
    end)

    -- LSB's own helpers
    dofile(LSB_DIR .. "/scripts/globals/npc_util.lua")
    dofile(LSB_DIR .. "/scripts/globals/teleports.lua")

    -- utils (mask, contains, clamp...) and quest ids: real files, tolerated if they fail
    for _, file in ipairs({ "scripts/utils/common.lua", "scripts/utils/utils.lua", "scripts/globals/quests.lua", "scripts/globals/missions.lua", "scripts/globals/shop.lua" }) do
        local okLoad, loadErr = pcall(dofile, LSB_DIR .. "/" .. file)

        if not okLoad then
            io.stderr:write("harness: " .. file .. " did not load: " .. tostring(loadErr) .. "\n")
        end
    end

    S.loadBindings(opts.bindings)
end

_G.os_time = os.time

return S
