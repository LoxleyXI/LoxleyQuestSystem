-----------------------------------
-- Static check: globals a file reads that nothing defines
-----------------------------------
-- A misspelt local or a name from another file (`Verona1` for `Verona`) is a
-- global read that is nil at runtime. It only errors on the line that runs,
-- which may be a reminder nobody sees in a test or a combat callback the walker
-- never fires. This reads the file's bytecode without running it, so every
-- line is checked.
--
-- A name counts as defined when it exists once the harness has loaded
-- everything (LSB's enums and globals, the server's preloads, LQS, the quest),
-- when the file sets it itself, when LSB's C++ registers it (luautils.cpp,
-- common/lua.cpp and the binding lists), when LSB's scripts/globals set it at the top level, or
-- when a server extension names it in W.knownGlobals.
-----------------------------------
local util = require("jit.util")
local band, rshift = bit.band, bit.rshift

local G = {}

-- The opcodes, from probes (no jit.vmdef needed): `return y` starts with a
-- global read; `x = 1` sets one
local function opcodeOf(chunk, nth)
    local fn = assert(loadstring(chunk))
    return band(util.funcbc(fn, nth), 0xff)
end

local GGET = opcodeOf("return y", 1)
local GSET = opcodeOf("x = 1", 2)

-- Every global read and write in fn and the functions inside it:
-- reads[name] = first line, writes[name] = true
local function scan(fn, reads, writes)
    for pc = 1, 1e7 do
        local ins = util.funcbc(fn, pc)

        if not ins then
            break
        end

        local op = band(ins, 0xff)

        if op == GGET or op == GSET then
            local name = util.funck(fn, -rshift(ins, 16) - 1)

            if type(name) == "string" then
                if op == GGET then
                    if reads[name] == nil then
                        reads[name] = util.funcinfo(fn, pc).currentline or 0
                    end
                else
                    writes[name] = true
                end
            end
        end
    end

    for n = -1, -1e7, -1 do
        local k = util.funck(fn, n)

        if k == nil then
            break
        end

        if type(k) == "proto" then
            scan(k, reads, writes)
        end
    end
end

-- Globals LSB's C++ registers: set_function("Name") and lua["Name"] = ...
local function cppGlobals(files, known)
    for _, path in ipairs(files) do
        local f = io.open(path)

        if f then
            local src = f:read("*a")
            f:close()

            for name in src:gmatch('set_function%(%s*"([%w_]+)"') do
                known[name] = true
            end

            for name in src:gmatch('lua%[%s*"([%w_]+)"%s*%]%s*=') do
                known[name] = true
            end
        end
    end
end

-- Globals LSB's own Lua defines at the top level of scripts/globals (the Interaction
-- Framework's Quest, Mission, Battlefield...), which the harness doesn't load
local function lsbGlobals(lsb, known)
    local p = io.popen('find "' .. lsb .. '/scripts/globals" -name "*.lua" 2>/dev/null')

    if not p then
        return
    end

    for path in p:lines() do
        local f = io.open(path)

        if f then
            for line in f:lines() do
                local name = line:match("^([%a_][%w_]*)%s*=[^=]")

                if name then
                    known[name] = true
                end
            end

            f:close()
        end
    end

    p:close()
end

-- Globals read by the file at path that nothing defines: a list of { name, line }
function G.undefined(path, extra)
    local fn, err = loadfile(path)

    if not fn then
        return {}, err
    end

    local reads, writes = {}, {}
    scan(fn, reads, writes)

    local known = {}

    for name in pairs(extra or {}) do
        known[name] = true
    end

    local lsb   = os.getenv("LSB_DIR")
    local files = {}

    if lsb then
        table.insert(files, lsb .. "/src/map/lua/luautils.cpp")
        table.insert(files, lsb .. "/src/common/lua.cpp")   -- fmt, print, tostring
        lsbGlobals(lsb, known)
    end

    for p in (os.getenv("LQS_BINDINGS") or ""):gmatch("[^:]+") do
        table.insert(files, p)
    end

    cppGlobals(files, known)

    local missing = {}

    for name, line in pairs(reads) do
        if rawget(_G, name) == nil and not writes[name] and not known[name] then
            table.insert(missing, { name = name, line = line })
        end
    end

    table.sort(missing, function(a, b)
        return a.line < b.line or (a.line == b.line and a.name < b.name)
    end)

    return missing
end

return G
