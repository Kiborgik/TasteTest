# Debugging failures and runner semantics

## The verdict, field by field

`runAll(specRoot, opts?)` returns:

| Field | Meaning |
|---|---|
| `ok` | True when `failed == 0`. Says nothing about warnings or afterAll errors; check those too. |
| `passed`, `failed`, `skipped`, `totalTests` | Counts. `totalTests = passed + failed + skipped`. |
| `durationSec` | Suite duration via os.clock, which measures CPU time. Accurate for synchronous suites; a yield-heavy suite (tests spending wall time in task.wait) under-reports, because yielded time costs no CPU. |
| `failures` | Array of `{ path, file, error }`. `path` is the composed `describe > it` chain. `file` is the spec's full name (Instance path in Roblox, the given `name` for table-form specs). |
| `beforeAllErrors` | Array of `{ path, error }` for every beforeAll that threw, including siblings after the first failure. |
| `afterAllErrors` | Same shape for afterAll. afterAll errors do NOT fail tests; surface them anyway. |
| `warnings` | Registration-time warnings (for example a bad `it.each` name template). A green run with warnings deserves a look. |
| `capturedWarnings` | Every runtime warning captured during the run (see the warning gate below). |
| `expectedWarnings` | Captured warnings that matched the `opts.expectedWarnings` allowlist. |
| `unexpectedWarnings` | Captured warnings that matched nothing; the list to inspect first. |
| `warningsClean` | True when `unexpectedWarnings` is empty. |

`opts`: `{ wait = fn, timeout = seconds, expectedWarnings = list, strictWarnings = bool, capturedWarnings = buffer }`. `wait` is the scheduler used for yielding tests (defaults to the global `task.wait` inside Roblox; pass `require("@lune/task").wait` under Lune). `timeout` is the suite default per-test timeout, 5s when omitted.

## The warning gate

A passing count with stray warnings is not a clean run; the gate makes that machine-checkable. During `runAll` the framework captures warning output, classifies each message against `opts.expectedWarnings` (plain substring matching, entries are strings or `{ pattern, reason }` tables, empty patterns are ignored), and reports the result in the verdict fields above. With `opts.strictWarnings = true`, any unexpected warning flips `ok` to false and appends a `(warning gate)` entry to `failures` (test counts are not inflated; the entry is the visibility).

Capture sources differ by runtime, and the difference matters:

- **Inside Roblox**, capture is automatic via `LogService.MessageOut`, which also catches engine warnings (bad asset ids, deprecations) the allowlist can then triage. Two caveats: MessageOut is game-wide, so unrelated scripts warning during the run land in the gate too (usually what you want in a test session), and delivery is asynchronous, so a warning emitted in the very last frame of the run can occasionally escape capture. Treat the gate as reliable in practice rather than guaranteed complete.
- **Outside Roblox (Lune)**, the framework cannot self-install a capture: a `warn` override assigned inside a required module is invisible to other files (module global writes are isolated; reads inherit). The ENTRY script must install the override itself before requiring specs and pass the buffer in via `opts.capturedWarnings`. `Tests/RunInLune.luau` is the reference implementation, including the sanity assert that fails the run if capture silently breaks.

Registration-time warnings (`verdict.warnings`) are a separate channel: messages the FRAMEWORK emits about spec-authoring problems (for example a bad `it.each` template), never gate-classified. Note the distinction is by emitter, not by phase: a `warn()` call in a spec module's top-level code runs while capture is active and IS gate-classified like any other runtime warning.

## Hook ordering and failure semantics

For nested describes, per test:

```
outer.beforeAll (once, on entering scope)
inner.beforeAll (once)
outer.beforeEach > inner.beforeEach > test body > inner.afterEach > outer.afterEach
inner.afterAll (once, after last test in scope)
outer.afterAll (once)
```

Semantics worth knowing before debugging:

- **If a beforeAll throws**, every test in its scope is marked FAILED (not skipped) with `beforeAll failed: <error>`. Sibling beforeAll hooks still run (their errors land in `beforeAllErrors`), and all afterAll hooks still run.
- **afterEach always runs**, even when the test body or a beforeEach failed or timed out (Jest semantics). Each afterEach is protected individually, so one failing cleanup does not skip its siblings. An afterEach failure fails the test; when the body also failed, the body's error comes first in the message and the cleanup errors are appended as `afterEach failed: ...`.
- **Hooks must be declared inside a describe.** Top-level hook calls error at registration time, because the registration tree is shared across all spec files in the run.

## Yielding tests and timeouts

Each test body (with its beforeEach/afterEach chain) runs inside a watchdog coroutine:

- A test that completes synchronously is unaffected.
- A test that yields (task.wait, WaitForChild, remote round-trip) is polled by the scheduler until it finishes or the timeout elapses. Timeout failures read `timed out after Ns`.
- Errors thrown AFTER a yield are still captured and attributed to the right test; they do not leak to the global error handler.
- If no scheduler is available (running outside Roblox without `opts.wait`), a yielding test fails immediately with a message saying so. That message means: pass `{ wait = require("@lune/task").wait }` to `runAll`.

The timeout exists to convert a hung suite into a diagnosable failure. When a test legitimately needs longer than 5s, raise it locally (`it(name, fn, { timeout = 30 })`) rather than raising the suite default.

## Discovery problems

Symptoms and causes when a spec "does not run":

- Name does not end in `.spec` — the walker matches on the name suffix.
- Spec module returned a table instead of a function — recorded as a failed placeholder test `(spec did not return function)`.
- Spec module errored at require time — placeholder `(spec require failed)` with the error.
- Registration code threw (for example a top-level hook) — placeholder `(spec registration failed)`.
- Table-form entry malformed — placeholder `(invalid spec entry #i)`; entries must be `{ name = string, fn = function }`.

All placeholders count as failures, so a broken spec can never silently vanish from the totals.

## Reentrancy

`runAll` asserts against reentrant calls; the registration tree is module state. Never call `runAll` from inside a test. To test runner behavior itself, use the exposed seams on `require(<TasteTest>/runner)`: `_runTestFn` (watchdog execution, see `Tests/Timeouts.spec.luau`), `_runTestWithHooks` (afterEach semantics, same file), and `_classifyWarnings` (warning classification, see `Tests/WarningGate.spec.luau`).
