-----------------------------------
-- LQS unit tests: the cases
-----------------------------------
-- Each test is { name, fn(S, T) }. fn raises an error to fail.
-- Nothing here touches LQS until a test runs, so the list loads without a server.
-----------------------------------
local T = { list = {}, byName = {} }

local function test(name, fn, opts)
    local t = { name = name, fn = fn, allowErrors = opts and opts.allowErrors }
    table.insert(T.list, t)
    T.byName[name] = t
end

-----------------------------------
-- Helpers
-----------------------------------
local S -- set when a test runs

function T.eq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
    end
end

function T.ok(value, what)
    if not value then
        error((what or "expected true") , 2)
    end
end

local zoneName = "Upper_Jeuno"

-- Register a quest and build its entities. Returns the quest table.
function T.quest(tbl)
    tbl.info = tbl.info or {}
    tbl.info.name = tbl.info.name or "Unit Quest"
    tbl.info.var  = tbl.info.var or "[LQS]UNIT"
    local m = Module:new("unit_" .. tbl.info.name)
    LQS.add(m, tbl)
    S.initZones()
    return tbl
end

function T.npc(name, extra)
    local e = { name = name, type = xi.objType.NPC, pos = { 0, 0, 0, 0 }, default = { "..." } }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end

function T.mob(name, extra)
    local e = { name = name, type = xi.objType.MOB, pos = { 0, 0, 0, 0 }, base = { 245, 1 }, level = 10 }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end

function T.player(opts)
    opts = opts or {}
    opts.zone = opts.zone or zoneName
    return S.newPlayer(opts)
end

function T.entity(name)
    return S.getZone(zoneName):queryEntitiesByName("DE_" .. name)[1]
end

function T.trigger(player, name)
    local e = T.entity(name)
    S.protect("onTrigger " .. name, e.def.onTrigger, player, e)
end

function T.trade(player, name, items)
    local e = T.entity(name)
    local slots = {}

    for _, it in ipairs(items) do
        player:addItem(it[1], it[2])
        table.insert(slots, { id = it[1], qty = it[2] })
    end

    local trade = { slots = slots, confirmed = {} }
    function trade:getSlotCount() return #self.slots end
    function trade:getItemId(i) return self.slots[i + 1] and self.slots[i + 1].id or 0 end
    function trade:getSlotQty(i) return self.slots[i + 1] and self.slots[i + 1].qty or 0 end
    function trade:getItemCount() local n = 0 for _, s in ipairs(self.slots) do n = n + s.qty end return n end
    function trade:getItemQty(id) local n = 0 for _, s in ipairs(self.slots) do if s.id == id then n = n + s.qty end end return n end
    function trade:confirmItem(id, qty) self.confirmed[id] = (self.confirmed[id] or 0) + (qty or 1) end

    player.currentTrade = trade
    S.protect("onTrade " .. name, e.def.onTrade, player, e, trade)
    return trade
end

function T.choose(player, index)
    local menu = player.openMenu
    T.ok(menu, "no menu open")
    player.openMenu = nil
    S.protect("menu option", menu.options[index][2], player)
end

function T.run()
    S.clock.run()
end

function T.count(kind, field, value)
    local n = 0
    for _, e in ipairs(S.log) do
        if e.kind == kind and (field == nil or e[field] == value) then
            n = n + 1
        end
    end
    return n
end

local function wrap(fn)
    return function(server, t)
        S = server
        fn(t)
    end
end

-----------------------------------
-- Checks
-----------------------------------
test("checks: level, vareq, item, gil", wrap(function()
    local p = T.player({ level = 10, gil = 50 })
    T.eq(LQS.checks({ level = 10 })(p), true, "level 10 >= 10")
    T.eq(LQS.checks({ level = 11 })(p), false, "level 10 >= 11")
    T.eq(LQS.checks({ vareq = { "[X]", 0 } })(p), true, "unset var is 0")
    p:setCharVar("[X]", 3)
    T.eq(LQS.checks({ vareq = { "[X]", 3 } })(p), true, "var 3")
    T.eq(LQS.checks({ item = 640 })(p), false, "no copper ore")
    p:addItem(640, 1)
    T.eq(LQS.checks({ item = 640, gil = 50 })(p), true, "copper ore and 50 gil")
    T.eq(LQS.checks({ gil = 51 })(p), false, "51 gil")
end))

test("checks: an unknown key fails the check instead of crashing", wrap(function()
    local p = T.player()
    local ok, result = pcall(function() return LQS.checks({ lvl = 10 })(p) end)
    T.ok(ok, "LQS.checks crashed on an unknown key: " .. tostring(result))
    T.eq(result, false, "unknown check result")
end), { allowErrors = true })

test("checks: mixed-case keys work (hasTeleport)", wrap(function()
    local p = T.player()
    local ok, result = pcall(function() return LQS.checks({ hasTeleport = 3 })(p) end)
    T.ok(ok, "crashed: " .. tostring(result))
    T.eq(result, false, "no teleport yet")
    p.teleports[p.nation .. ":" .. 8] = true
    T.eq(LQS.checks({ hasTeleport = 3 })(p), true, "teleport unlocked")
end), { allowErrors = true })

-----------------------------------
-- pickItem and eventDelay
-----------------------------------
test("pickItem: follows the weights", wrap(function()
    local pool = { { 750, "a" }, { 250, "b" } }
    local counts = { a = 0, b = 0 }

    for _ = 1, 4000 do
        local r = LQS.pickItem(pool)
        counts[r[2]] = counts[r[2]] + 1
    end

    T.ok(counts.a > 2800 and counts.a < 3200, "a picked " .. counts.a .. " of 4000 (want about 3000)")
end))

test("eventDelay: strings 1500, tables 0, delay and duration as given", wrap(function()
    T.eq(LQS.eventDelay({ "a", "b" }), 3000, "two lines")
    T.eq(LQS.eventDelay({ { emote = 1 }, "a" }), 1500, "emote then a line")
    T.eq(LQS.eventDelay({ { delay = 700 }, "a" }), 2200, "delay then a line")
    T.eq(LQS.eventDelay({ { animation = 48, duration = 3000 } }), 3000, "duration")
end))

test("eventDelay: an empty event doesn't crash", wrap(function()
    local ok, err = pcall(LQS.eventDelay, {})
    T.ok(ok, "crashed: " .. tostring(err))
end), { allowErrors = true })

-----------------------------------
-- Dialog
-----------------------------------
test("dialog: reward given once when the player spams the NPC", wrap(function()
    T.quest({
        entities = { [zoneName] = { T.npc("Giver") } },
        steps = { { Giver = LQS.dialog({ reward = 4198, event = { "Here.", "Take it." } }) } },
    })

    local p = T.player()
    T.trigger(p, "Giver")
    T.trigger(p, "Giver")
    T.run()
    T.trigger(p, "Giver")
    T.run()

    T.eq(p:getItemCount(4198), 1, "rewards")
    T.eq(p:getCharVar("[LQS]UNIT"), 1, "quest var")
end))

test("dialog: full bags keep the step, and the reward comes once there's room", wrap(function()
    T.quest({
        entities = { [zoneName] = { T.npc("Giver") } },
        steps = { { Giver = LQS.dialog({ reward = 4198, event = { "Here." } }) } },
    })

    local p = T.player({ freeSlots = 0 })
    T.trigger(p, "Giver")
    T.run()
    T.eq(p:getCharVar("[LQS]UNIT"), 0, "var after a failed reward")

    p.freeSlots = 5
    T.trigger(p, "Giver")
    T.run()
    T.eq(p:getItemCount(4198), 1, "reward after making room")
    T.eq(p:getCharVar("[LQS]UNIT"), 1, "var after the reward")
end))

test("dialog: augmented reward fails cleanly when the item can't be obtained", wrap(function()
    T.quest({
        entities = { [zoneName] = { T.npc("Giver") } },
        steps = { { Giver = LQS.dialog({ reward = { item = 13227, augment = { 1, 9 } }, event = { "Here." } }) } },
    })

    local p = T.player()
    p.canObtainItem = function() return false end
    p.addItem = function() return false end
    T.trigger(p, "Giver")
    T.run()
    T.eq(p:getCharVar("[LQS]UNIT"), 0, "var when the augmented item wasn't given")
end))

-----------------------------------
-- Trade
-----------------------------------
test("trade: the right items advance and are taken; wrong ones are declined", wrap(function()
    T.quest({
        entities = { [zoneName] = { T.npc("Taker") } },
        steps = { { Taker = { onTrade = LQS.trade({
            required = { { 640, 3 } },
            reward   = 4198,
            accepted = { "Thanks." },
            declined = { "No." },
        }) } } },
    })

    local p = T.player()
    T.trade(p, "Taker", { { 641, 3 } })
    T.run()
    T.eq(p:getCharVar("[LQS]UNIT"), 0, "var after the wrong items")

    T.trade(p, "Taker", { { 640, 3 } })
    T.run()
    T.eq(p:getCharVar("[LQS]UNIT"), 1, "var after the right items")
    T.eq(p:getItemCount(640), 0, "copper ore taken")
    T.eq(p:getItemCount(4198), 1, "reward")
end))

test("trade: a failed reward releases the lock so the player can trade again", wrap(function()
    T.quest({
        entities = { [zoneName] = { T.npc("Taker") } },
        steps = { { Taker = { onTrade = LQS.trade({
            required = 640,
            reward   = { item = 4198 },
            accepted = { "Thanks." },
            declined = { "No." },
        }) } } },
    })

    local p = T.player({ freeSlots = 1 })
    T.trade(p, "Taker", { { 640, 1 } }) -- fills the last slot with the ore itself
    T.run()
    T.eq(p:getCharVar("[LQS]UNIT"), 0, "var after a failed reward")

    p.freeSlots = 5
    T.trade(p, "Taker", { { 640, 1 } })
    T.run()
    T.eq(p:getCharVar("[LQS]UNIT"), 1, "var after trading again with room")
end), { allowErrors = true })

test("trade: spawning two mobs gives the reward and the step once", wrap(function()
    T.quest({
        entities = { [zoneName] = { T.npc("Altar"), T.mob("Imp"), T.mob("Fiend") } },
        steps = { { Altar = { onTrade = LQS.trade({
            required = 640,
            reward   = 4198,
            spawn    = { "Imp", "Fiend" },
            accepted = { "Something stirs." },
            declined = { "No." },
        }) } } },
    })

    local p = T.player()
    T.trade(p, "Altar", { { 640, 1 } })
    T.run()

    T.eq(p:getCharVar("[LQS]UNIT"), 1, "quest var")
    T.eq(p:getItemCount(4198), 1, "rewards")
    T.ok(T.entity("Imp"):isSpawned() and T.entity("Fiend"):isSpawned(), "both mobs spawned")
end), { allowErrors = true })

-----------------------------------
-- Menu
-----------------------------------
test("menu: an option's item reward is that item", wrap(function()
    T.quest({
        entities = { [zoneName] = { T.npc("Chooser") } },
        steps = { { Chooser = LQS.menu({
            title   = "Take one?",
            options = {
                { "No thanks." },
                { "Yes please.", { "Here you go." }, 4198 },
            },
        }) } },
    })

    local p = T.player()
    T.trigger(p, "Chooser")
    T.run()
    T.choose(p, 2)
    T.run()

    T.eq(p:getItemCount(4198), 1, "item from the option")
    T.eq(p:getCharVar("[LQS]UNIT"), 1, "quest var")
end), { allowErrors = true })

-----------------------------------
-- Defeat
-----------------------------------
local function defeatQuest(defeat, handlerCheck)
    return T.quest({
        entities = { [zoneName] = { T.npc("Spot"), T.mob("Beast") } },
        steps = {
            {
                Spot  = LQS.menu({ title = "Poke it?", spawn = { "Beast" }, options = { { "No." }, { "Yes.", true } } }),
                Beast = handlerCheck and { onMobDeath = defeat, check = handlerCheck } or defeat,
            },
        },
    })
end

local function fight(p)
    T.trigger(p, "Spot")
    T.run()
    T.choose(p, 2)
    T.run()
    T.ok(T.entity("Beast"):isSpawned(), "Beast spawned")
    S.killMob(T.entity("Beast"), p)
    T.run()
end

test("defeat: killing the mob advances the step", wrap(function()
    defeatQuest(LQS.defeat({ mobs = { "Beast" } }))
    local p = T.player()
    fight(p)
    T.eq(p:getCharVar("[LQS]UNIT"), 1, "quest var")
end))

test("defeat: a step check on the mob handler doesn't crash", wrap(function()
    defeatQuest(LQS.defeat({ mobs = { "Beast" } }), LQS.checks({ level = 1 }))
    local p = T.player()
    fight(p)
    T.eq(p:getCharVar("[LQS]UNIT"), 1, "quest var")
end), { allowErrors = true })

test("defeat: points with a multiplier don't crash", wrap(function()
    defeatQuest(LQS.defeat({
        mobs       = { "Beast" },
        points     = 10,
        pointsVar  = "[UNIT]POINTS",
        message    = "{} gains {} points.",
        multiplier = { var = "MULT", range = { 1, 100 } },
    }))
    local p = T.player()
    fight(p)
    T.ok(p:getCharVar("[UNIT]POINTS") > 0, "points given")
end), { allowErrors = true })


test("defeat: an entity tally counts once per member in a party", wrap(function()
    T.quest({
        entities = { [zoneName] = { T.npc("Spot"), T.mob("Beast", { tally = "[UNIT]TALLY" }) } },
        steps = {
            {
                Spot  = LQS.menu({ title = "Poke it?", spawn = { "Beast" }, options = { { "No." }, { "Yes.", true } } }),
                Beast = LQS.defeat({ mobs = { "Beast" } }),
            },
        },
    })

    local a = T.player({ name = "A" })
    local b = T.player({ name = "B" })
    a.party, b.party = { a, b }, { a, b }

    T.trigger(a, "Spot")
    T.run()
    T.choose(a, 2)
    T.run()
    S.killMob(T.entity("Beast"), a)
    T.run()

    T.eq(a:getCharVar("[UNIT]TALLY"), 1, "A's tally")
    T.eq(b:getCharVar("[UNIT]TALLY"), 1, "B's tally")
    T.eq(b:getCharVar("[LQS]UNIT"), 1, "B's quest var")
end))

test("dialog: a failed check on an NPC with default shows the default", wrap(function()
    T.quest({
        entities = { [zoneName] = { T.npc("Gate", { default = { "Closed." } }) } },
        steps = { { Gate = LQS.dialog({ check = { level = 99 }, event = { "Open." } }) } },
    })

    local p = T.player({ level = 1 })
    T.trigger(p, "Gate")
    T.run()
    T.eq(#S.errors, 0, "server errors")
end), { allowErrors = true })


-----------------------------------
-- Validation
-----------------------------------
local function refused(tbl)
    tbl.info = tbl.info or { name = "Bad Quest", var = "[LQS]BAD" }
    local result = LQS.add(Module:new("unit_bad"), tbl)
    return result == false
end

test("validate: an unknown builder option refuses the quest", wrap(function()
    T.ok(refused({
        entities = { [zoneName] = { T.npc("Giver") } },
        steps = { { Giver = LQS.dialog({ evnt = { "Typo." } }) } },
    }), "a typo'd option should refuse the quest")
end), { allowErrors = true })

test("validate: 2.x keys say what replaced them", wrap(function()
    T.ok(refused({
        entities = { [zoneName] = { T.npc("Giver") } },
        steps = { { Giver = LQS.dialog({ quest = "Old", event = { "Hi." } }) } },
    }), "quest = should refuse")

    local said = false
    for _, e in ipairs(S.log) do
        if e.kind == "print" and e.text:find("moved to accept or complete", 1, true) then
            said = true
        end
    end
    T.ok(said, "the message names the replacement")
end), { allowErrors = true })

test("validate: an unknown check key refuses the quest", wrap(function()
    T.ok(refused({
        entities = { [zoneName] = { T.npc("Giver") } },
        steps = { { check = { lvl = 5 }, Giver = LQS.dialog({ event = { "Hi." } }) } },
    }), "unknown check")
end), { allowErrors = true })

test("validate: a step naming a missing entity refuses the quest", wrap(function()
    T.ok(refused({
        entities = { [zoneName] = { T.npc("Giver") } },
        steps = { { Givr = LQS.dialog({ event = { "Hi." } }) } },
    }), "missing entity")
end), { allowErrors = true })

test("validate: a trade builder under onTrigger refuses the quest", wrap(function()
    T.ok(refused({
        entities = { [zoneName] = { T.npc("Giver") } },
        steps = { { Giver = { onTrigger = LQS.trade({ required = 640 }) } } },
    }), "wrong event")
end), { allowErrors = true })

test("validate: a defined check key is accepted and works", wrap(function()
    LQS.checks.define("vip", function(player, value) return (player:getCharVar("[UNIT]VIP") == 1) == value end)

    T.quest({
        entities = { [zoneName] = { T.npc("Giver") } },
        steps = { { check = { vip = true }, Giver = LQS.dialog({ event = { "Welcome." } }) } },
    })

    local p = T.player()
    T.trigger(p, "Giver")
    T.run()
    T.eq(p:getCharVar("[LQS]UNIT"), 0, "not a vip")

    p:setCharVar("[UNIT]VIP", 1)
    T.trigger(p, "Giver")
    T.run()
    T.eq(p:getCharVar("[LQS]UNIT"), 1, "vip")
end))

test("validate: a second quest can't reuse a var", wrap(function()
    T.quest({ info = { name = "First", var = "[LQS]SHARED" }, entities = { [zoneName] = { T.npc("A") } }, steps = { { A = LQS.dialog({ event = { "Hi." } }) } } })
    T.ok(refused({ info = { name = "Second", var = "[LQS]SHARED" }, entities = { [zoneName] = { T.npc("B") } }, steps = { { B = LQS.dialog({ event = { "Hi." } }) } } }), "duplicate var")
end), { allowErrors = true })


test("event: 2.x row names still work in direct LQS.event calls", wrap(function()
    local p = T.player()
    p:setCharVar("[UNIT]COUNT", 7)
    LQS.event(p, nil, { { fmt = "Count {}", var = "[UNIT]COUNT" }, { emotion = "waves." } })
    T.run()

    local said, narrated = false, false
    for _, e in ipairs(S.log) do
        if e.kind == "text" and e.text == "Count 7" then said = true end
        if e.kind == "text" and e.text == "waves." then narrated = true end
    end
    T.ok(said, "fmt row said its line")
    T.ok(narrated, "emotion row narrated")
end))


test("keys: two entities with one name in different zones get their own steps", wrap(function()
    T.quest({
        entities =
        {
            [zoneName]       = { T.npc("Reisle", { key = "REISLE_1" }) },
            ["Bastok_Mines"] = { T.npc("Reisle", { key = "REISLE_2" }) },
        },
        steps =
        {
            { REISLE_1 = LQS.dialog({ event = { "Meet me in the Mines." } }) },
            { REISLE_2 = LQS.dialog({ event = { "You came!" } }) },
        },
    })

    local p = T.player()
    local mines = S.getZone("Bastok_Mines"):queryEntitiesByName("DE_Reisle")[1]

    S.moveTo(p, "Bastok_Mines")
    S.protect("mines", mines.def.onTrigger, p, mines)
    T.run()
    T.eq(p:getCharVar("[LQS]UNIT"), 0, "the Mines Reisle has nothing at step 1")

    S.moveTo(p, zoneName)
    T.trigger(p, "Reisle")
    T.run()
    T.eq(p:getCharVar("[LQS]UNIT"), 1, "the first Reisle starts it")

    S.moveTo(p, "Bastok_Mines")
    S.protect("mines", mines.def.onTrigger, p, mines)
    T.run()
    T.eq(p:getCharVar("[LQS]UNIT"), 2, "the Mines Reisle finishes it")
end))


test("dialog keys: event = \"START\" plays the entity's dialog.START", wrap(function()
    T.quest({
        entities = { [zoneName] = { T.npc("Giver", { dialog = { DEFAULT = { "Hm?" }, START = { "Begin here." } } }) } },
        steps = { { Giver = LQS.dialog({ event = "START" }) } },
    })

    local p = T.player()
    T.trigger(p, "Giver")
    T.run()

    local said = false
    for _, e in ipairs(S.log) do
        if e.kind == "text" and e.text:find("Begin here.", 1, true) then said = true end
    end
    T.ok(said, "the START lines played")
    T.eq(p:getCharVar("[LQS]UNIT"), 1, "quest var")
end))

test("menu: an option with step = false only talks", wrap(function()
    T.quest({
        entities = { [zoneName] = { T.npc("Asker") } },
        steps = { { Asker = LQS.menu({
            title   = "Help?",
            options = { { "Tell me more.", event = { "It's dangerous." }, step = false }, { "Yes.", event = { "Thanks!" } } },
        }) } },
    })

    local p = T.player()
    T.trigger(p, "Asker") T.run() T.choose(p, 1) T.run()
    T.eq(p:getCharVar("[LQS]UNIT"), 0, "talking option")
    T.trigger(p, "Asker") T.run() T.choose(p, 2) T.run()
    T.eq(p:getCharVar("[LQS]UNIT"), 1, "accepting option")
end))

test("dialog spawn and defeat by key, with resetStep to a number", wrap(function()
    T.quest({
        entities = { [zoneName] = { T.npc("Spot"), T.mob("Wild Ram", { key = "RAM_1" }) } },
        steps =
        {
            { Spot = LQS.dialog({ event = { "Something rustles." } }) },
            {
                Spot  = LQS.dialog({ event = { "Here it comes!" }, spawn = { "RAM_1" }, step = false }),
                RAM_1 = LQS.defeat({ mobs = { "RAM_1" }, resetStep = 1 }),
            },
        },
    })

    local p = T.player()
    T.trigger(p, "Spot") T.run()
    T.eq(p:getCharVar("[LQS]UNIT"), 1, "first talk")
    T.trigger(p, "Spot") T.run()
    T.ok(T.entity("Wild Ram"):isSpawned(), "ram spawned by key")
    S.killMob(T.entity("Wild Ram"), p) T.run()
    T.eq(p:getCharVar("[LQS]UNIT"), 1, "resetStep = 1 sets the var to 1")
end))

test("reward after(ctx) runs once the reward is given", wrap(function()
    T.quest({
        entities = { [zoneName] = { T.npc("Giver") } },
        steps = { { Giver = LQS.dialog({ event = { "Here." }, reward = { gil = 10, after = function(ctx) ctx.player:setCharVar("[UNIT]AFTER", 1) end } }) } },
    })

    local p = T.player()
    T.trigger(p, "Giver") T.run()
    T.eq(p:getCharVar("[UNIT]AFTER"), 1, "after ran")
end))


test("byJob: the event and the reward follow the main job", wrap(function()
    T.quest({
        entities = { [zoneName] = { T.npc("Smith") } },
        steps = { { Smith = LQS.dialog({
            event  = { byJob = { [xi.job.WAR] = { "An axe for you." }, default = { "A stick for you." } } },
            reward = { byJob = { [xi.job.WAR] = 16640, default = 17088 } },
        }) } },
    })

    local p = T.player({ job = xi.job.WAR })
    T.trigger(p, "Smith") T.run()
    T.eq(p:getItemCount(16640), 1, "warrior's reward")

    local said = false
    for _, e in ipairs(S.log) do
        if e.kind == "text" and e.text:find("An axe", 1, true) then said = true end
    end
    T.ok(said, "warrior's line")
end))


test("defeat helper: only party members not on the step get it", wrap(function()
    T.quest({
        entities = { [zoneName] = { T.npc("Spot"), T.mob("Beast") } },
        steps =
        {
            {
                Spot  = LQS.menu({ title = "Poke it?", spawn = { "Beast" }, options = { { "No." }, { "Yes.", true } } }),
                Beast = LQS.defeat({ mobs = { "Beast" }, helper = 4198 }),
            },
        },
    })

    local a = T.player({ name = "A" })
    local b = T.player({ name = "B" })
    b:setCharVar("[LQS]UNIT", 5) -- B is further on, and is helping
    a.party, b.party = { a, b }, { a, b }

    T.trigger(a, "Spot") T.run() T.choose(a, 2) T.run()
    S.killMob(T.entity("Beast"), a) T.run()

    T.eq(a:getItemCount(4198), 0, "A advanced, no helper reward")
    T.eq(b:getItemCount(4198), 1, "B helped")
    T.eq(a:getCharVar("[LQS]UNIT"), 1, "A's quest var")
end))


test("LQS.spawn: a handler of your own starts an encounter", wrap(function()
    T.quest({
        entities = { [zoneName] = { T.npc("Horn"), T.mob("Beast", { key = "BEAST" }) } },
        steps = { { Horn = function(ctx) LQS.spawn(ctx, { "BEAST" }, { delay = 1000 }) end, BEAST = LQS.defeat({ mobs = { "BEAST" } }) } },
    })

    local p = T.player()
    T.trigger(p, "Horn") T.run()
    T.ok(T.entity("Beast"):isSpawned(), "spawned")
    S.killMob(T.entity("Beast"), p) T.run()
    T.eq(p:getCharVar("[LQS]UNIT"), 1, "quest var")
end))


test("validate: two entities in one zone may not share a key", wrap(function()
    T.ok(refused({
        entities =
        {
            [zoneName] = { T.npc("Sharara", { key = "SHARARA" }), T.npc("Sharara", { key = "SHARARA" }) },
        },
        steps = { { SHARARA = LQS.dialog({ event = { "Hello." } }) } },
    }), "a shared key should refuse the quest")
end), { allowErrors = true })

return T
