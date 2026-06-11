--[[
  RunInLune — runs the framework's own spec suite under the Lune runtime.

  Usage: lune run Tests/RunInLune.luau   (from the TasteTest repo root)

  This file is inert inside Roblox: it requires @lune/process, which only
  resolves under Lune, and nothing in the game ever requires this module.
  New spec files must be added to the list below; Lune has no Instance tree
  for the runner to discover specs from.
]]

local process = require("@lune/process")
local task = require("@lune/task")

-- Entry-level warn capture for the warning gate. This must live HERE, not
-- inside the framework: in Lune, global writes from a required module are
-- invisible to other files, so only the entry script can install a warn
-- override that spec code will actually hit.
local capturedWarnings = {}
local realWarn = warn
warn = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    table.insert(capturedWarnings, table.concat(parts, " "))
    realWarn(...)
end

local TasteTest = require("../Start")

local verdict = TasteTest.runAll({
    { name = "EachAndMatchers.spec", fn = require("./EachAndMatchers.spec") },
    { name = "Hooks.spec", fn = require("./Hooks.spec") },
    { name = "Spy.spec", fn = require("./Spy.spec") },
    { name = "SpyMatchers.spec", fn = require("./SpyMatchers.spec") },
    { name = "StrictTable.spec", fn = require("./StrictTable.spec") },
    { name = "Timeouts.spec", fn = require("./Timeouts.spec") },
    { name = "WarningGate.spec", fn = require("./WarningGate.spec") },
}, {
    wait = task.wait,
    capturedWarnings = capturedWarnings,
    strictWarnings = true,
    expectedWarnings = {
        { pattern = "TasteTest self-test expected warning", reason = "WarningGate.spec capture dogfood" },
    },
})

warn = realWarn

-- Two-sided dogfood: WarningGate.spec emits one allowlisted warn. If capture
-- silently broke, the gate would read "clean" and hide the breakage; this
-- assert turns that into a CI failure.
assert(#verdict.expectedWarnings >= 1,
    "warning capture broke: the self-test warn from WarningGate.spec was not captured")

print(("TasteTest: %d passed, %d failed, %d skipped (%.3fs)"):format(
    verdict.passed, verdict.failed, verdict.skipped, verdict.durationSec))

for _, failure in ipairs(verdict.failures) do
    print(("FAIL %s\n  %s"):format(failure.path, tostring(failure.error)))
end

if #verdict.warnings > 0 then
    for _, w in ipairs(verdict.warnings) do
        print("WARN (registration) " .. tostring(w))
    end
end

if verdict.unexpectedWarnings and #verdict.unexpectedWarnings > 0 then
    for _, w in ipairs(verdict.unexpectedWarnings) do
        print("WARN (unexpected) " .. tostring(w))
    end
end

if not verdict.ok then
    process.exit(1)
end
