--[[
  TasteTest — a zero-dependency Jest-style test framework for Luau.

  Public entry point: require this module ("Start", not "init", because
  Studio Script Sync doesn't elevate init.luau the way Rojo does).

  Specs are ModuleScripts named *.spec that return a function; the function
  registers tests via describe/it/expect. runAll(specRoot) discovers every
  spec under specRoot (an Instance, or a { name, fn } array outside Roblox),
  runs them, and returns a structured verdict. See README.md.
]]

local matchers = require("./matchers")
local runner = require("./runner")
local spy = require("./spy")
local strictTable = require("./strictTable")

local TasteTest = {}

TasteTest.spy = spy
TasteTest.strictTable = strictTable

-- Registration API (used inside .spec ModuleScripts)
TasteTest.describe = runner.describe       -- callable + .skip + .only
TasteTest.it = runner.it                   -- callable + .skip + .only
TasteTest.beforeEach = runner.beforeEach   -- per-describe setup hook (per test)
TasteTest.afterEach = runner.afterEach     -- per-describe teardown hook (per test)
TasteTest.beforeAll = runner.beforeAll     -- per-describe one-time setup
TasteTest.afterAll = runner.afterAll       -- per-describe one-time teardown

-- Assertion API
TasteTest.expect = matchers.expect
TasteTest.addMatcher = matchers.addMatcher

-- Execution API (used by ServerScriptService.Tests.TasteTestRunner)
function TasteTest.runAll(specRoot, opts)
    return runner.runAll(specRoot, opts or {})
end

return TasteTest
