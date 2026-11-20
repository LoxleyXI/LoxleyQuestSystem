-----------------------------------
-- LQS unit tests
-----------------------------------
-- luajit test/unit/run.lua [filter]
--
-- Each test builds a small quest inline in a fresh server process, so tests
-- can't affect each other. One line per test: PASS or FAIL.
-----------------------------------
local here = debug.getinfo(1, "S").source:sub(2):match("(.*/)") or "./"
local filter = ...

-- Child mode: run one named test in this process
if filter and filter:match("^@") then
    package.path = here .. "../?.lua;" .. package.path

    local S   = require("harness.server")
    local lib = os.getenv("LQS_LIB") or (here .. "../../lib")

    S.boot({ bindings = { lib .. "/../cpp/lqs_util.cpp" } })
    for _, file in ipairs(S.moduleOrder(lib)) do
        dofile(file)
    end

    S.strictItems()

    local T = dofile(here .. "tests.lua")
    local name = filter:sub(2)
    local test = T.byName[name]

    local ok, err = xpcall(function() test.fn(S, T) end, debug.traceback)

    if ok and #S.errors > 0 and not test.allowErrors then
        ok, err = false, "server error: " .. S.errors[1]:match("^[^\n]*")
    end

    if ok then
        io.write("PASS " .. name .. "\n")
    else
        io.write("FAIL " .. name .. "\n    " .. tostring(err):match("^[^\n]*") .. "\n")

        if S.errors[1] then
            io.write("    server: " .. S.errors[1]:match("^[^\n]*") .. "\n")
        end
    end

    os.exit(ok and 0 or 1)
end

-- Parent mode: list tests and run each in its own process
package.path = here .. "../?.lua;" .. package.path
local T = dofile(here .. "tests.lua")
local passed, failed = 0, 0

for _, test in ipairs(T.list) do
    if not filter or test.name:find(filter, 1, true) then
        local function q(str) return "'" .. str:gsub("'", "'\\''") .. "'" end
        local p = io.popen((os.getenv("LQS_LUAJIT") or "luajit") .. " " .. q(here .. "run.lua") .. " " .. q("@" .. test.name) .. " 2>&1")
        local output = p:read("*a")
        p:close()
        io.write(output)

        if output:match("^PASS") then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end
end

io.write(string.format("unit: %d pass, %d fail\n\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
