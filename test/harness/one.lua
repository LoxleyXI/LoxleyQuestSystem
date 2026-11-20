-----------------------------------
-- LQS test harness: test one quest file in a fresh server
-----------------------------------
-- luajit test/harness/one.lua <quest.lua> [--verbose] [--record <dir>]
--
-- Environment:
--   LSB_DIR       LandSandBoat checkout (enums, npc_util.lua, bindings)
--   LQS_LIB       folder holding LQS.lua and LQS/ (default: lib/ beside test/)
--   MODULES_DIR   folder that "modules/..." requires resolve against (optional)
--   LQS_BINDINGS  extra C++ module files with CBaseEntity bindings, ':' separated
--
-- Prints one line per quest: PASS, WARN or FAIL, then notes indented.
-----------------------------------
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
package.path = here .. "../?.lua;" .. package.path

local args = { ... }
local questFile, verbose, recordDir

local i = 1
while i <= #args do
    if args[i] == "--verbose" or args[i] == "-v" then
        verbose = true
    elseif args[i] == "--record" then
        i = i + 1
        recordDir = args[i]
    else
        questFile = args[i]
    end
    i = i + 1
end

if not questFile then
    io.stderr:write("usage: one.lua <quest.lua> [--verbose] [--record <dir>]\n")
    os.exit(2)
end

local S = require("harness.server")
local W = require("harness.walker")

local lib = os.getenv("LQS_LIB") or (here .. "../../lib")

-- LQS's own C++ bindings, plus any the server adds
local bindings = { lib .. "/../cpp/lqs_util.cpp" }
for path in (os.getenv("LQS_BINDINGS") or ""):gmatch("[^:]+") do
    table.insert(bindings, path)
end

S.boot({ modulesDir = os.getenv("MODULES_DIR"), bindings = bindings })

local out = io.stdout

local function finish(status, label, notes)
    out:write(string.format("%s %s\n", status, label))

    for _, n in ipairs(notes or {}) do
        out:write("    " .. n:gsub("\n", "\n    ") .. "\n")
    end
end

-- LQS itself, in the order LSB loads the lib folder
local function loadLib()
    local files = S.moduleOrder(lib)

    if #files == 0 then
        error("no Lua files in " .. lib)
    end

    for _, file in ipairs(files) do
        if file:match("/LQS[/%.]") then
            dofile(file)
        else
            -- Other libraries sharing the folder: their failures aren't the quest's
            local okLoad, loadErr = xpcall(function() dofile(file) end, debug.traceback)

            if not okLoad then
                io.stderr:write("lib " .. file:match("[^/]+$") .. ": " .. tostring(loadErr):match("^[^\n]*") .. "\n")
            end
        end
    end
end

-- Server files that load before LQS (LQS_PRELOAD: files or folders, ':' separated).
-- Failures here are noted, not fatal: they're the server's, not the quest's.
local preloadNotes = {}

for path in (os.getenv("LQS_PRELOAD") or ""):gmatch("[^:]+") do
    for _, file in ipairs(S.moduleOrder(path)) do
        local okLoad, loadErr = xpcall(function() dofile(file) end, debug.traceback)

        if not okLoad then
            table.insert(preloadNotes, "preload " .. file:match("[^/]+$") .. ": " .. tostring(loadErr):match("^[^\n]*"))
        end
    end
end

local ok, err = xpcall(loadLib, debug.traceback)

if not ok then
    finish("FAIL", questFile, { "LQS failed to load: " .. tostring(err) })
    os.exit(1)
end

W.instrument()

-- LQS_VALIDATE=warn: load quests with faults anyway (to survey them)
if os.getenv("LQS_VALIDATE") then
    LQS.settings.VALIDATE = os.getenv("LQS_VALIDATE")
end

-- LQS_PERTURB=n: allocate junk first, to show whether a quest's results depend on memory layout
for _ = 1, tonumber(os.getenv("LQS_PERTURB") or 0) do
    local junk = { {}, function() end }
end

S.strictItems()

local errorsBefore = #S.errors
ok, err = xpcall(function() dofile(questFile) end, debug.traceback)

if not ok then
    finish("FAIL", questFile, { "quest file failed to load: " .. tostring(err) })
    os.exit(1)
end

S.initZones()

-- What LQS said while the quest loaded (validation faults, warnings)
local loadNotes = {}

for _, entry in ipairs(S.log) do
    if entry.kind == "print" and entry.text:match("^%[LQS%]") and not entry.text:match("Added entity") then
        table.insert(loadNotes, entry.text)
    end
end

-- Files without quests (LQS.npc, teleporters): talk to every NPC and try every menu option
if #W.quests == 0 then
    local npcs = {}

    for _, zone in pairs(S.world.zones) do
        for _, e in ipairs(zone.entities) do
            if e.objtype ~= xi.objType.MOB and e.def.onTrigger then
                table.insert(npcs, e)
            end
        end
    end

    if #npcs == 0 then
        finish("FAIL", questFile, { "registers nothing: no LQS.add and no NPCs (does it return a handler instead of a module?)" })
        os.exit(1)
    end

    local errStart = #S.errors

    for _, npc in ipairs(npcs) do
        local tries = 1
        local option = 1

        while option <= tries and option <= 20 do
            local player = S.newPlayer({ level = 99, gil = 1000000, zone = npc.zone.name })
            player.ranks[0] = 10

            S.protect("onTrigger " .. npc.name, npc.def.onTrigger, player, npc)
            S.clock.run()

            if player.openMenu then
                tries = #player.openMenu.options
                local opt = player.openMenu.options[option]
                player.openMenu = nil

                if opt and type(opt[2]) == "function" then
                    S.protect("menu option '" .. tostring(opt[1]) .. "'", opt[2], player)
                    S.clock.run()
                end

                -- Sub-menus: take their first option
                local depth = 0
                while player.openMenu and depth < 3 do
                    local sub = player.openMenu.options[1]
                    player.openMenu = nil

                    if sub and type(sub[2]) == "function" then
                        S.protect("sub-menu option '" .. tostring(sub[1]) .. "'", sub[2], player)
                        S.clock.run()
                    end

                    depth = depth + 1
                end
            end

            option = option + 1
        end
    end

    local notes = {}
    local shown = {}

    for j = errStart + 1, #S.errors do
        local first = S.errors[j]:match("^[^\n]*")
        if not shown[first] then
            shown[first] = true
            table.insert(notes, "error: " .. first)
        end
    end

    table.insert(notes, string.format("npcs: %d talked to, every menu option tried", #npcs))
    finish(#S.errors > errStart and "FAIL" or "PASS", questFile, notes)
    os.exit(#S.errors > errStart and 1 or 0)
end

-----------------------------------
-- Static checks
-----------------------------------
local function lint(quest)
    local problems = {}
    local names    = {}

    if not quest.info or not quest.info.var then
        table.insert(problems, "info.var is missing")
    end

    for zoneName, list in pairs(quest.entities or {}) do
        for _, e in ipairs(list) do
            names[e.name] = true

            local shown = e.packetName or e.name

            if type(shown) == "string" and #shown > 15 then
                table.insert(problems, string.format("name '%s' is %d characters (the client shows 15)", shown, #shown))
            end

            if e.pos == nil then
                table.insert(problems, string.format("entity '%s' has no pos", e.name))
            end

            if e.type == xi.objType.MOB and e.base == nil and e.groupId == nil then
                table.insert(problems, string.format("mob '%s' has no base or groupId", e.name))
            end
        end
    end

    for index, step in ipairs(quest.steps or {}) do
        for key in pairs(step) do
            if key ~= "check" and not names[key] then
                table.insert(problems, string.format("step %d names '%s', which is not an entity", index, key))
            end
        end
    end

    return problems
end

-----------------------------------
-- Walk each quest in the file
-----------------------------------
local exitCode = 0

for _, quest in ipairs(W.quests) do
    local label = string.format("%s :: %s", questFile, quest.info and quest.info.name or "?")
    local notes = {}
    local failed = false

    for _, problem in ipairs(lint(quest)) do
        table.insert(notes, "lint: " .. problem)
    end

    -- Load-time faults from LQS's own validation: errors fail the quest
    for _, text in ipairs(loadNotes) do
        if text:find(quest.info.name or "", 1, true) then
            table.insert(notes, text)

            if not text:match(": warning: ") then
                failed = true
            end
        end
    end

    -- Optional quest script: LQS_SCRIPTS/<var>.lua returns { setup = fn(player, step, S), trades = { [entity] = items } }
    W.script = nil
    local scriptsDir = os.getenv("LQS_SCRIPTS") or (here .. "../scripts")
    local scriptName = (quest.info.var or ""):gsub("[^%w]+", "_"):gsub("^_", ""):gsub("_$", "")
    local scriptFile = io.open(scriptsDir .. "/" .. scriptName .. ".lua", "r")

    if scriptFile then
        scriptFile:close()
        W.script = dofile(scriptsDir .. "/" .. scriptName .. ".lua")
        table.insert(notes, "script: " .. scriptName .. ".lua")
    end

    local logStart  = #S.log
    local errStart  = #S.errors
    local player    = S.newPlayer({ level = 1 })

    if W.script and W.script.autoKill then
        S.autoKill   = W.script.autoKill
        S.autoKillBy = player
    end
    local result    = W.walk(quest, player)

    -- The walker's notes explain a stuck quest; on a finished one they're noise
    if not result.complete then
        for _, n in ipairs(result.notes) do
            table.insert(notes, n)
        end
    end

    if not result.complete then
        failed = true
        table.insert(notes, string.format("stuck at step %d of %d (var %s = %d)", result.stuckAt or -1, result.steps, result.var, result.reached))
    end

    -- Rewards: items the quest gave (not the walker), and repeats within the walk
    local given, seen, repeats = {}, {}, {}

    for j = logStart + 1, #S.log do
        local entry = S.log[j]

        if entry.kind == "item" and not entry.walker then
            table.insert(given, entry.item)

            -- Loot pools may legitimately drop the same item twice
            if seen[entry.item] and not entry.treasure then
                repeats[entry.item] = true
            end

            seen[entry.item] = true
        end
    end

    for itemId in pairs(repeats) do
        table.insert(notes, string.format("item %d given more than once (check the reward lock)", itemId))
    end

    local unchanged, extra = W.revisit(quest, player)

    if not unchanged then
        failed = true
        table.insert(notes, "talking to NPCs after finishing changed the quest var")
    end

    if extra > 0 then
        failed = true
        table.insert(notes, string.format("talking to NPCs after finishing gave %d more item(s)", extra))
    end

    -- Hints for !quest
    local entry = quest.info and LQS.registry[string.lower(quest.info.name or "")]

    if entry and not quest.info.hidden and #entry.hint ~= #(quest.steps or {}) then
        table.insert(notes, string.format("!quest has %d hints for %d steps", #entry.hint, #quest.steps))
    end

    local shown = {}

    for j = errStart + 1, #S.errors do
        failed = true

        -- First line and the first LQS or quest frame is enough; the same error once
        local msg   = S.errors[j]
        local first = msg:match("^[^\n]*")
        local frame = msg:match("\n%s*([^\n]*lib/LQS[^\n]*)") or ""
        local key   = first

        if not shown[key] then
            shown[key] = true
            table.insert(notes, "error: " .. first .. (frame ~= "" and ("\n  at " .. frame) or ""))
        end
    end

    if #given > 0 then
        table.insert(notes, "rewards: " .. table.concat(given, ", "))
    end

    local quietNotes = (#given > 0 and 1 or 0) + (W.script and 1 or 0)
    local status = failed and "FAIL" or ((#notes > quietNotes) and "WARN" or "PASS")

    if failed then
        exitCode = 1
    end

    finish(status, label, notes)

    -- Transcript: var changes and items, for comparing old and new versions of a quest
    if verbose or recordDir then
        local lines = {}

        for j = logStart + 1, #S.log do
            local e = S.log[j]

            if e.kind == "var" or (e.kind == "item" and not e.walker) or e.kind == "keyitem" or e.kind == "gil" or e.kind == "currency" or e.kind == "exp" or e.kind == "error" then
                table.insert(lines, string.format("%s %s %s %s", e.kind, tostring(e.var or e.item or e.ki or e.currency or ""), tostring(e.value or e.qty or e.amount or ""), e.text or ""))
            elseif (verbose or recordDir) and (e.kind == "text" or e.kind == "trigger" or e.kind == "choose" or e.kind == "trade" or e.kind == "death" or e.kind == "spawn" or e.kind == "print") then
                table.insert(lines, string.format("  [%s] %s", e.kind, tostring(e.text or e.entity or e.option or "")))
            end
        end

        if verbose then
            out:write(table.concat(lines, "\n") .. "\n")
        end

        if recordDir then
            local name = (quest.info.var or quest.info.name):gsub("[^%w]+", "_")
            local f = io.open(recordDir .. "/" .. name .. ".txt", "w")
            f:write(table.concat(lines, "\n") .. "\n")
            f:close()
        end
    end
end

os.exit(exitCode)
