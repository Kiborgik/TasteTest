---
name: tastetest
description: Write and run unit tests for Roblox Luau code with the TasteTest framework (describe/it/expect, spies, strict-table fixtures, yield-safe timeouts, runs in Studio and in Lune CI). Use this whenever the user asks to add tests, write a spec, run a test suite, or debug a failing test in any project that contains a TasteTest folder (usually ReplicatedStorage.TasteTest), even if they just say "test this module" without naming a framework.
---

# Testing with TasteTest

TasteTest is a zero-dependency Jest-style test framework for Luau. It lives as a single folder (usually `ReplicatedStorage.TasteTest`) and works without Rojo, Wally, or any other toolchain. This file covers the recipe for writing and running specs; the `references/` folder has the full API when you need details beyond the recipe. A condensed copy of this guide also ships inside the place as the `GUIDE` ModuleScript, for assistants that can only see instances; keep the two in sync when editing either.

## Writing a spec

A spec is a ModuleScript named `<Thing>.spec` that returns one function. Place it next to the module it tests.

```lua
-- MyThing.spec (ModuleScript, sibling of MyThing)
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
```

Rules that matter:

- The module name must end in `.spec`, and the module must return a function. The runner discovers specs by walking descendants of the root you pass to `runAll`; a wrong name means the spec silently never runs.
- Register tests only inside the returned function, and hooks (`beforeEach` etc.) only inside a `describe`. Top-level hooks raise an error by design, because the registration tree is shared across spec files.
- Make tests deterministic. Inject time and randomness as parameters of the code under test (a `now` argument, a `randomFn` argument) instead of calling `os.time` or `math.random` inside it. This is the single biggest factor in whether the suite stays trustworthy.
- Test through the public API of the module. Prefer asserting on return values and observable state over internals.

## Running

Inside Roblox (Studio command bar, a runner script, or MCP `execute_luau`):

```lua
local TasteTest = require(game.ReplicatedStorage.TasteTest.Start)
local verdict = TasteTest.runAll(game.ReplicatedStorage.MyModules)
print(verdict.ok, verdict.passed, verdict.failed)
```

Outside Roblox (Lune, CI), pass specs explicitly plus a scheduler, and turn the verdict into an exit code:

```lua
local process = require("@lune/process")
local task = require("@lune/task")
local TasteTest = require("./TasteTest/Start")
local verdict = TasteTest.runAll({
    { name = "MyThing.spec", fn = require("./MyThing.spec") },
}, { wait = task.wait })
if not verdict.ok then process.exit(1) end
```

On disk, a spec is a file named `MyThing.spec.luau`, and under Lune the spec body uses path requires instead of Instance paths: `require("./TasteTest/Start")` and `require("./MyThing")` in place of the `game.ReplicatedStorage...` / `script.Parent` forms. A spec meant to run in BOTH runtimes needs one require style per runtime; inside Roblox, string requires like `require("./MyThing")` also work (resolved against `script.Parent`), so prefer relative string requires when a spec must be portable.

## Reading the verdict

`runAll` returns a table; `verdict.ok` is true when nothing failed. Counts are in `verdict.passed`, `verdict.failed`, `verdict.skipped`, `verdict.totalTests`. On failure, read `verdict.failures`: each entry has `path` (composed `describe > it` chain), `file`, and `error`. The error message for `toEqual` names the path of the first difference inside the compared tables ("at a.b.c: expected 2, got 1"). Also check `verdict.beforeAllErrors`, `verdict.afterAllErrors`, and `verdict.warnings` before declaring a run clean; a passing count with warnings is not a clean run.

The warning gate makes that last rule enforceable: pass `strictWarnings = true` plus an `expectedWarnings` allowlist (plain substring patterns) and any unexpected runtime warning fails the run with a `(warning gate)` entry. Inside Roblox capture is automatic; under Lune the entry script must install an entry-level warn override and pass the buffer as `opts.capturedWarnings` (copy the pattern from `Tests/RunInLune.luau`). Details in `references/debugging.md`.

## Mistakes that cost the most time

- **Spy call form.** `TasteTest.spy()` returns TWO values: a callable table (has `.calls`) and a plain function. Code that checks `type(x) == "function"` needs the second value. The spy matchers (`toHaveBeenCalledWith` and friends) need the first.
- **Recorded calls are table.pack results.** `spy.calls[1]` is `{ n = 2, "a", 1 }`, not `{ "a", 1 }`. Assert with `spy.calls[1][1]` indexing or use `toHaveBeenCalledWith`.
- **Dot calls, not colon calls.** Everything is a plain function: `expect(x).toBe(y)`, never `expect(x):toBe(y)`.
- **`toContain` works on arrays only**, not on strings. To assert about an error message, use `toThrow(pattern)` (a Lua string pattern, so escape dots: `"a%.b"`).
- **A test that yields** (WaitForChild, task.wait, awaiting a remote) is subject to the per-test timeout (default 5s). Raise it per test with `it(name, fn, { timeout = 30 })`. A test that times out reports "timed out after Ns"; it does not hang the suite.
- **`runAll` is not reentrant.** Never call `runAll` inside a running test.

## References

Read these when the task goes beyond the recipe above:

- `references/matchers.md` — every matcher with exact semantics, `never` negation, custom matchers via `addMatcher`, parameterized tests with `it.each` / `describe.each`.
- `references/spies-and-fixtures.md` — the spy API and its matchers, strict-table fixture factories that catch typos at construction time.
- `references/debugging.md` — hook ordering, beforeAll failure semantics, timeout internals, yield rules, and how to read every field of the verdict.
