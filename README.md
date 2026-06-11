# TasteTest

[![CI](https://github.com/Kiborgik/TasteTest/actions/workflows/ci.yml/badge.svg)](https://github.com/Kiborgik/TasteTest/actions/workflows/ci.yml)

A zero-setup, AI-first, Jest-style unit testing framework for Roblox Luau. The framework is a single folder of plain Luau with no dependencies, and the same core runs inside Roblox Studio and under [Lune](https://github.com/lune-org/lune) on CI. Alongside the human docs, the repo ships an agent skill so that a coding agent can write and run specs correctly from the start.

```lua
local TasteTest = require(game.ReplicatedStorage.TasteTest.Start)
local describe, it, expect = TasteTest.describe, TasteTest.it, TasteTest.expect

describe("math", function()
    it("adds", function()
        expect(1 + 1).toBe(2)
    end)
end)
```

## Why TasteTest

Setup is the main difference. Copy the folder into `ReplicatedStorage`, write a ModuleScript named `Something.spec`, and call `runAll`; there is no project file or package manager involved. The AI-first part is [SKILL.md](SKILL.md), an agent-facing guide in the Agent Skills format, so a coding agent can write specs, run suites, and debug failures without reverse-engineering the API from source.

How it compares with the alternatives:

| | TasteTest | Jest Lua (jest-roblox) | TestEZ | busted / LuaUnit |
|---|---|---|---|---|
| Install | copy one folder | Wally/Rojo package tree | Wally/Rojo or model | LuaRocks |
| Dependencies | none | many (Jest 27 port) | none | LuaRocks ecosystem |
| Runs in plain Studio, no toolchain | yes | no | possible but awkward | no (no Roblox API) |
| CI without Roblox Studio | yes (Lune) | no (needs run-in-roblox) | no | yes (plain Lua) |
| Jest API surface | the practical subset | nearly all of Jest 27 | older expect style | xUnit style |
| Yield-safe tests with timeouts | yes | yes | partial | n/a |
| Built-in warning gate (fail on unexpected warn) | yes | no | no | no |
| Bundled AI agent skill | yes | no | no | no |
| Battle-tested at scale | drives a 1400+ test suite in one shipped game | all of Roblox's internal apps | legacy, maintenance mode | huge, outside Roblox |

**Use Jest Lua instead** if you need snapshot testing, module mocking (`jest.mock`), or fake timers, or if your team wants to standardize on Roblox's internal tooling. TasteTest leaves those features out so that it can stay a drop-in folder.

A practical consequence of the drop-in model: you vendor the framework. The copy in your place is yours, an abandoned upstream cannot break your tests, and at five short modules it is small enough to patch yourself if you ever need to.

## Installation

Two ways, depending on how you work:

- **Studio only:** download `TasteTest.rbxm` from the [latest release](https://github.com/Kiborgik/TasteTest/releases/latest) and drag it into `ReplicatedStorage`. It contains the framework and its own test suite.
- **Filesystem (Script Sync, Rojo):** copy the `TasteTest` folder into the directory that maps to `ReplicatedStorage`.

Nothing else needs to be installed or configured.

```lua
local TasteTest = require(game.ReplicatedStorage.TasteTest.Start)
```

Note on naming: the entry module is called `Start` instead of the conventional `init` because Studio Script Sync does not honor the Rojo `init.luau` folder-collapse convention. A sibling module keeps the folder layout working in both worlds.

## Writing specs

A spec is a ModuleScript whose name ends in `.spec`. It returns a single function that registers tests:

```lua
-- MyThing.spec (ModuleScript)
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

Specs do not need to be registered anywhere. Inside Roblox the runner walks a root Instance and picks up every descendant ModuleScript named `*.spec`.

## Running

Inside Roblox (command bar, a runner Script, or `StudioTestService`):

```lua
local TasteTest = require(game.ReplicatedStorage.TasteTest.Start)
local verdict = TasteTest.runAll(game.ReplicatedStorage.MyModules)
print(verdict.ok, verdict.passed, verdict.failed)
```

Outside Roblox (Lune, CI), pass the specs as an explicit list plus a scheduler:

```lua
local task = require("@lune/task")
local TasteTest = require("./TasteTest/Start")

local verdict = TasteTest.runAll({
    { name = "MyThing.spec", fn = require("./MyThing.spec") },
}, { wait = task.wait })
```

This repository tests itself that way on every push (see `.github/workflows/ci.yml` and `Tests/RunInLune.luau`).

### The verdict

| Field | Meaning |
|---|---|
| `ok` | `true` when no test failed |
| `passed`, `failed`, `skipped`, `totalTests` | counts |
| `durationSec` | suite duration (CPU time via os.clock; yield-heavy suites under-report) |
| `failures` | list of `{ path, file, error }` with composed `describe > it` paths |
| `beforeAllErrors`, `afterAllErrors` | hook errors (afterAll errors do not fail tests) |
| `warnings` | registration-time warnings, for example a bad `it.each` name template |
| `capturedWarnings`, `expectedWarnings`, `unexpectedWarnings`, `warningsClean` | the warning gate (below) |

`runAll` options: `{ wait = fn, timeout = seconds, expectedWarnings = list, strictWarnings = bool, capturedWarnings = buffer }`. `wait` is the scheduler used for yielding tests (defaults to the global `task.wait` inside Roblox). `timeout` is the default per-test timeout, 5 seconds when omitted. `runAll` is guarded against reentrancy.

### What failures look like

Each entry in `verdict.failures` carries the composed describe-to-test path and a message written to be acted on. Deep-equality failures name the first differing path inside the compared tables, a hung test reports its timeout instead of freezing the suite, and the warning gate reports what it caught:

```
Mining.calculateDrop > applies the luck bonus
  expected deep-equal: at drops.bonus: expected 2, got 1 (actual={base=1, bonus=1} expected={base=1, bonus=2})

SellSystem > pays out after the remote round-trip
  timed out after 5.0s

(warning gate)
  1 unexpected warning(s):
  Infinite yield possible on 'ReplicatedStorage:WaitForChild("Remotes")'
```

### The warning gate

Warnings often point at real problems that a passing test count hides, so TasteTest treats warning output as part of the verdict. Every warning captured during the run is classified against an allowlist of expected patterns (plain substring matching, with an optional reason for documentation), and with `strictWarnings = true` any unexpected warning fails the run with a `(warning gate)` entry in `failures`.

```lua
local verdict = TasteTest.runAll(root, {
    strictWarnings = true,
    expectedWarnings = {
        { pattern = "DataStore budget", reason = "throttling is expected in Studio" },
    },
})
```

Inside Roblox, capture is automatic (LogService, so engine warnings like bad asset ids are caught too). Under Lune the entry script installs a small entry-level `warn` override and passes the buffer via `capturedWarnings`; `Tests/RunInLune.luau` shows the pattern.

## API

### Registration

| API | Behavior |
|---|---|
| `describe(name, fn)` | Group block. Names compose into `outer > inner > test` paths in failure output. |
| `describe.skip(name, fn)` | Skip every test inside the block. |
| `describe.only(name, fn)` | Run only this block (and other `.only` blocks). Everything else is reported as skipped. |
| `describe.each(rows)(nameFmt, fn)` | One `describe` per row. |
| `it(name, fn, opts?)` | Register a test. `opts = { timeout = seconds }` raises the per-test timeout for yielding tests. |
| `it.skip(name, fn)` | Skip this test. |
| `it.only(name, fn)` | Run only this test (and other `.only` tests). |
| `it.each(rows)(nameFmt, fn)` | One test per row. |
| `beforeAll(fn)` / `afterAll(fn)` | Run once per enclosing `describe`. `afterAll` always runs, even when `beforeAll` failed. |
| `beforeEach(fn)` / `afterEach(fn)` | Run around every test in the enclosing `describe` and its descendants. |

Hook ordering for nested describes:

```
outer.beforeAll > inner.beforeAll > outer.beforeEach > inner.beforeEach
> test body > inner.afterEach > outer.afterEach > inner.afterAll > outer.afterAll
```

If a `beforeAll` throws, the tests in its scope are marked failed (not skipped) with the message `beforeAll failed: <error>`. `afterEach` always runs, even when the test failed or timed out, and an `afterEach` failure fails the test without masking the test's own error.

### Yield-safe tests and timeouts

Each test body runs inside a watchdog coroutine. A test that yields (`task.wait`, `WaitForChild`, a remote round-trip) is waited on by the scheduler up to its timeout, and a test that never finishes fails with `timed out after Ns` instead of hanging the suite. Errors thrown after a yield are still captured and attributed to the right test.

```lua
it("waits for the round-trip", function()
    local result = thing.requestAndWait()
    expect(result.ok).toBeTruthy()
end, { timeout = 30 })
```

### Matchers

```lua
expect(actual).toBe(expected)                   -- strict equality (==)
expect(actual).toEqual(expected)                -- deep equality by keys/values (metatables ignored), diff in the failure message
expect(actual).toMatchObject(subset)            -- partial equality, extra fields in actual are fine
expect(actual).toBeCloseTo(expected, numDigits) -- float comparison, numDigits defaults to 10
expect(actual).toBeTruthy()
expect(actual).toBeFalsy()
expect(actual).toBeGreaterThan(n)
expect(actual).toBeGreaterThanOrEqual(n)
expect(actual).toBeLessThan(n)
expect(actual).toBeLessThanOrEqual(n)
expect(list).toContain(item)                    -- array membership via deep equality (tables only)
expect(fn).toThrow(optionalLuaPattern)
expect(spy).toHaveBeenCalled()
expect(spy).toHaveBeenCalledTimes(n)
expect(spy).toHaveBeenCalledWith(...)           -- deep equality on args, nil-aware by position
expect(actual).never.toBe(forbidden)            -- .never negates any matcher
```

`toEqual` and `toMatchObject` failures name the path of the first difference, for example `at a.b.c: expected 2, got 1` or `at b: missing, expected 2`.

### Custom matchers

```lua
TasteTest.addMatcher("toBeEven", function(actual)
    if type(actual) ~= "number" then return false, "expected a number" end
    if actual % 2 ~= 0 then return false, string.format("expected %d to be even", actual) end
    return true, "is even"
end)

expect(4).toBeEven()
```

Matcher signature: `(actual, ...args) -> (ok: boolean, message: string)`. Registered matchers automatically work with `.never`.

### Parameterized tests

```lua
-- Array rows, positional access via $1, $2, ...
it.each({
    { 1, 1, 2 },
    { 2, 3, 5 },
})("$1 + $2 = $3", function(a, b, sum)
    expect(a + b).toBe(sum)
end)

-- Dict rows, named access via $key
it.each({
    { case = "happy", input = "x" },
    { case = "edge",  input = "" },
})("scenario: $case", function(row)
    expect(transform(row.input)).toBeTruthy()
end)
```

`.skip` and `.only` propagate to all rows: `it.each(rows).skip(...)`.

### Spies

`TasteTest.spy(impl?)` returns two values: a callable table with a `.calls` record, and a plain function bound to the same record. Use the plain function where consuming code does `type(x) == "function"` checks; use the table with the spy matchers.

```lua
local spy, spyFn = TasteTest.spy()
spy("a", 1)
spyFn("b", 2)
expect(spy).toHaveBeenCalledTimes(2)
expect(spy).toHaveBeenCalledWith("a", 1)
```

Each entry in `.calls` is a `table.pack` result (`{ n = 2, "a", 1 }`), so explicit nil arguments are positional and countable: `spy.calls[1].n` is the argument count. `toHaveBeenCalledWith` accounts for this; manual asserts should index positionally (`spy.calls[1][1]`).

For per-call return sequences, pass an `impl` closure that closes over an index. There is intentionally no `mockReturnValueOnce` chain API.

### Strict-table fixtures

`TasteTest.strictTable(name, canonicalKeys, factory)` produces a fixture factory whose tables error on reads of non-canonical keys and reject unknown override keys at construction. This catches fixture drift at the point of mistake instead of as a confusing downstream failure.

```lua
local makePlayerData = TasteTest.strictTable("playerData", {
    coins = true, inventory = true, level = true,
}, function(overrides)
    return {
        coins = overrides.coins or 100,
        inventory = overrides.inventory or {},
        level = overrides.level or 1,
    }
end)

local d = makePlayerData({ coins = 500 })
print(d.coins)                -- 500
print(d.unknown)              -- error, names the factory and the bad key
makePlayerData({ coinz = 1 }) -- error at construction, unknown override key
```

Escape hatches: raw assignment and `pairs()` iteration bypass the strict read check.

## For AI agents

Which entry point an agent needs depends on where it lives:

**Studio's built-in Assistant** (or any AI working inside the place) cannot read repository files, so the install includes the guide as a ModuleScript: `ReplicatedStorage.TasteTest.GUIDE`. Start a session with a prompt like:

> Read ReplicatedStorage.TasteTest.GUIDE and follow it. Then write TasteTest specs for ReplicatedStorage.MyModules.Inventory and run them.

The Assistant reads the spec recipe, the matcher list, and the known mistakes from the module, writes the `.spec` files next to your code, and runs the suite from the command bar.

**Filesystem agents** (Claude Code, Cursor, and similar) get [SKILL.md](SKILL.md), an agent-facing guide in the Agent Skills format: the spec recipe, run recipes for both runtimes, verdict interpretation, and the most common mistakes. Claude Code users can copy or symlink the folder under `.claude/skills/tastetest/`. The `references/` folder holds the detailed API docs it links to ([matchers](references/matchers.md), [spies and fixtures](references/spies-and-fixtures.md), [debugging](references/debugging.md)); they double as the human reference documentation.

## Testing the framework itself

The `Tests/` folder contains TasteTest's own spec suite. Inside Roblox, point `runAll` at the folder Instance; outside, `lune run Tests/RunInLune.luau` does it (this is what CI runs).

## Layout

```
TasteTest/
  Start.luau        public API entry, require this
  runner.luau       spec discovery, execution, hooks, watchdog timeouts
  matchers.luau     expect(), matcher registry, failure diffs
  spy.luau          call recorder
  strictTable.luau  strict fixture factory
  GUIDE.luau        in-place agent guide for Studio assistants
  SKILL.md          agent-facing guide (Agent Skills format)
  references/       detailed API and debugging docs
  Tests/            the framework's own specs (+ RunInLune.luau entry)
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the scope rules, development setup, and test requirements for changes.

## License

MIT, see [LICENSE](LICENSE).
