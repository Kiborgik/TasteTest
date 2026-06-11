--[[
  GUIDE — agent-readable usage guide that ships inside the place.

  Studio's built-in Assistant (and any other in-Studio AI) can only see
  instances, not repository files, so this module carries the working
  knowledge from SKILL.md to wherever the framework is installed. Tell the
  assistant: "Read ReplicatedStorage.TasteTest.GUIDE and follow it."

  Keep this file in sync with SKILL.md when the recipe changes (see
  CONTRIBUTING.md). Full reference docs: https://github.com/Kiborgik/TasteTest
]]

return [=[
TasteTest usage guide for AI assistants working inside Roblox Studio.

WRITING A SPEC

A spec is a ModuleScript whose Name ends in ".spec", placed next to the
module it tests. It returns one function that registers tests:

    return function()
        local TasteTest = require(game.ReplicatedStorage.TasteTest.Start)
        local describe, it, expect = TasteTest.describe, TasteTest.it, TasteTest.expect
        local MyThing = require(script.Parent.MyThing)

        describe("MyThing.doStuff", function()
            it("returns 1 for empty input", function()
                expect(MyThing.doStuff({})).toBe(1)
            end)
            it("rejects nil", function()
                expect(function() MyThing.doStuff(nil) end).toThrow()
            end)
        end)
    end

Rules:
- The name must end in ".spec" and the module must return a function,
  otherwise the runner never picks it up.
- Hooks (beforeEach, afterEach, beforeAll, afterAll) only inside describe.
- Make tests deterministic: pass time and randomness into the code under
  test as parameters (a now argument, a randomFn argument) instead of
  calling os.time or math.random inside it.
- Test the public API of the module, not its internals.

RUNNING

From the command bar (or any Script):

    local TasteTest = require(game.ReplicatedStorage.TasteTest.Start)
    local v = TasteTest.runAll(game.ReplicatedStorage.MyModules)
    print(v.ok, v.passed, v.failed, v.skipped)
    for _, f in v.failures do print(f.path, f.error) end

runAll discovers every descendant ModuleScript named *.spec under the root
you pass. The verdict table: ok, passed, failed, skipped, totalTests,
durationSec, failures ({path, file, error}), beforeAllErrors,
afterAllErrors, warnings (registration problems), capturedWarnings,
expectedWarnings, unexpectedWarnings, warningsClean (the warning gate).

A run is clean only when ok is true AND warnings is empty AND
unexpectedWarnings is empty. Pass strictWarnings = true in the second
argument of runAll to make unexpected warnings fail the run, with
expectedWarnings = { "substring", ... } as the allowlist.

MATCHERS

    expect(x).toBe(y)                  strict ==
    expect(x).toEqual(y)               deep equality, metatables ignored;
                                       failures name the differing path
    expect(x).toMatchObject(subset)    partial deep equality
    expect(x).toBeCloseTo(y, digits)   floats, digits defaults to 10
    expect(x).toBeTruthy() / .toBeFalsy()
    expect(x).toBeGreaterThan(n) / GreaterThanOrEqual / LessThan / LessThanOrEqual
    expect(list).toContain(item)       arrays only, never strings
    expect(fn).toThrow(pattern)        pattern is a Lua pattern, escape dots
    expect(spy).toHaveBeenCalled() / Times(n) / With(...)
    expect(x).never.<matcher>(...)     negates any matcher

it.each({...})("name $1", fn) registers one test per row; it.skip and
it.only work as in Jest. TasteTest.addMatcher(name, fn) adds custom
matchers. TasteTest.spy() returns a callable table plus a plain function
bound to the same record. TasteTest.strictTable builds fixture factories
that error on unknown keys.

MISTAKES THAT COST THE MOST TIME

- Dot calls, never colon calls: expect(x).toBe(y), not expect(x):toBe(y).
- spy() returns TWO values; code checking type(x) == "function" needs the
  second one, the spy matchers need the first.
- spy.calls entries are table.pack results with an n field, so
  expect(spy.calls[1]).toEqual({"a", 1}) fails; index positionally or use
  toHaveBeenCalledWith.
- toContain does not search strings; assert on error text with
  toThrow("pattern").
- A test that yields (WaitForChild, task.wait, remotes) is subject to a 5s
  timeout; raise it per test: it(name, fn, { timeout = 30 }).
- Never call runAll from inside a test; it is not reentrant.
]=]
