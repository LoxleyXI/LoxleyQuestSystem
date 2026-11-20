-----------------------------------
-- LQS tests
-----------------------------------
-- luajit test/run.lua                 unit tests, then every quest in questpack/ and npcpack/
-- luajit test/run.lua <file|dir> ...  just those quest files (CI passes a PR's changed files)
-- luajit test/run.lua --unit          unit tests only
--
-- Options: --verbose (transcripts), --record <dir> (write transcripts for comparison),
--          --quiet (only WARN and FAIL)
--
-- Each quest file runs in its own luajit process, so quests can't leak into each other.
-- Environment: see test/harness/one.lua (LSB_DIR, LQS_LIB, MODULES_DIR, LQS_BINDINGS).
-----------------------------------
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
local root = here .. "../"

local targets, passArgs = {}, {}
local unitOnly, quiet = false, false

local args = { ... }
local i = 1
while i <= #args do
    local a = args[i]

    if a == "--unit" then
        unitOnly = true
    elseif a == "--quiet" or a == "-q" then
        quiet = true
    elseif a == "--verbose" or a == "-v" then
        table.insert(passArgs, a)
    elseif a == "--record" then
        table.insert(passArgs, a)
        i = i + 1
        table.insert(passArgs, args[i])
        os.execute("mkdir -p '" .. args[i] .. "'")
    else
        table.insert(targets, a)
    end

    i = i + 1
end

local function shell(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function luaFiles(path)
    local files = {}
    local p = io.popen("find " .. shell(path) .. " -name '*.lua' -type f 2>/dev/null | sort")

    for line in p:lines() do
        table.insert(files, line)
    end

    p:close()
    return files
end

local totals = { PASS = 0, WARN = 0, FAIL = 0, SKIP = 0 }

-- Run each test with address randomisation off where we can: LuaJIT orders pairs()
-- over table- and function-keyed tables by address, so a quest that iterates one
-- would otherwise vary between runs (and between before/after transcripts).
local launcher = "luajit "

do
    local p = io.popen("setarch $(uname -m) -R true 2>/dev/null && echo ok")
    local ok = p:read("*a")
    p:close()

    if ok:match("ok") then
        launcher = "setarch $(uname -m) -R luajit "
    end
end

-----------------------------------
-- Unit tests
-----------------------------------
local unitFailed = false

if #targets == 0 or unitOnly then
    local p = io.popen(launcher .. shell(here .. "unit/run.lua") .. " 2>&1")
    local output = p:read("*a")
    local ok = p:close()
    io.write(output)

    if output:match("FAIL") or not ok then
        unitFailed = true
    end

    if unitOnly then
        os.exit(unitFailed and 1 or 0)
    end
end

-----------------------------------
-- Quests
-----------------------------------
if #targets == 0 then
    targets = { root .. "questpack", root .. "npcpack", here .. "examples" }
end

local files = {}

for _, t in ipairs(targets) do
    for _, f in ipairs(luaFiles(t)) do
        table.insert(files, f)
    end
end

local vars = {}

for _, file in ipairs(files) do
    local cmd = launcher .. shell(here .. "harness/one.lua") .. " " .. shell(file)

    for _, a in ipairs(passArgs) do
        cmd = cmd .. " " .. shell(a)
    end

    local p = io.popen(cmd .. " 2>&1")
    local output = p:read("*a")
    p:close()

    local block, status = {}, nil

    for line in output:gmatch("[^\n]*\n?") do
        local s = line:match("^(%u%u%u%u) ")

        if s and totals[s] then
            totals[s] = totals[s] + 1
            status = s
        end

        if line ~= "" then
            if not quiet or (status == "WARN" or status == "FAIL") then
                io.write(line)
            end
        end
    end

    if not status then
        totals.FAIL = totals.FAIL + 1
        io.write("FAIL " .. file .. "\n    harness crashed:\n" .. output)
    end
end

io.write(string.format("\n%d quests: %d pass, %d warn, %d fail, %d skipped\n",
    totals.PASS + totals.WARN + totals.FAIL, totals.PASS, totals.WARN, totals.FAIL, totals.SKIP))

os.exit((totals.FAIL > 0 or unitFailed) and 1 or 0)
