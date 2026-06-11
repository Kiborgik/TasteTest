# Changelog

## 0.2.1 (2026-06-11)

- `GUIDE.luau`: the agent guide now also ships inside the place as a ModuleScript, so Studio's built-in Assistant (which sees instances, not repository files) can be told "Read ReplicatedStorage.TasteTest.GUIDE and follow it" and write correct specs. Condensed from SKILL.md; the two are kept in sync per CONTRIBUTING.
- The model build normalizes line endings, so a build from a Windows working tree is byte-identical to a CI build, and `Tools/VerifyRelease.luau` compares a downloaded release artifact against a local build module by module.

## 0.2.0 (2026-06-10)

- Release packaging: `Tools/BuildRbxm.luau` builds `TasteTest.rbxm` (framework plus test suite) with byte-for-byte round-trip verification, and a tag-triggered workflow runs the suite, builds the model, and attaches it to a GitHub release. README gained the CI badge, a Studio-only install path via the release artifact, and a section showing real failure output.
- CONTRIBUTING.md: scope rules (zero setup and both-runtimes constraints, out-of-scope feature list), development setup via Lune, test-first requirements, seam-based testing guidance, and PR conventions. README positioning now states the two design ideas directly: zero setup and AI-first.

- Review fixes ahead of first release: `it.each` array rows with interior nil holes (`{ "a", nil, "c" }`) now reach the test with arity preserved instead of depending on undefined `#row` behavior; `it.each` templates accept a per-row opts argument (`it.each(rows)(fmt, fn, { timeout = s })`); a malformed Lua pattern passed to `toThrow` reports itself instead of masking the test's real failure; the reentrancy guard can no longer wedge permanently if runAll setup errors; matcher messages are plain ASCII; docs now state that `toEqual` ignores metatables, `durationSec` is CPU time, and LogService warning capture is best-effort for last-frame warnings.

- Built-in warning gate: runtime warnings are captured during the run, classified against `opts.expectedWarnings` (plain substring allowlist with optional reasons), and reported as `capturedWarnings` / `expectedWarnings` / `unexpectedWarnings` / `warningsClean` on the verdict. `opts.strictWarnings = true` fails the run on any unexpected warning. Capture is automatic inside Roblox (LogService, engine warnings included); under Lune the entry script installs an entry-level warn override and passes the buffer via `opts.capturedWarnings` (pattern in `Tests/RunInLune.luau`, including a sanity assert that fails CI if capture silently breaks).

- `afterEach` now always runs, even when the test body or a `beforeEach` failed or timed out (Jest semantics). Each hook is protected individually so one failing cleanup does not skip its siblings; cleanup errors fail the test without masking the body's own error.

- Documentation suite for humans and agents: SKILL.md (Agent Skills format guide validated by a cold agent run), references/ (matchers, spies and fixtures, debugging), AGENTS.md pointer, and a README rework with a comparison table against Jest Lua, TestEZ, and busted, including a section on when Jest Lua is the better choice. README fixes along the way: spy call records are table.pack results with an `n` field, and `toContain` is array-only.

- Tests are now yield-safe: each test body runs inside a watchdog coroutine, so a test that never finishes fails with "timed out after Ns" instead of hanging the suite. Per-test override via `it(name, fn, { timeout = seconds })`, suite default via `runAll(root, { timeout = seconds })` (5s). Outside Roblox pass `runAll(root, { wait = ... })` (for Lune, `require("@lune/task").wait`); inside Roblox the global `task.wait` is picked up automatically.
- New spy matchers: `toHaveBeenCalled()`, `toHaveBeenCalledTimes(n)`, `toHaveBeenCalledWith(...)`. Argument matching is deep equality and nil-aware by position (`spy("a", nil, "c")` only matches `toHaveBeenCalledWith("a", nil, "c")`).
- `toEqual` failure messages now name the path of the first difference ("at a.b.c: expected 2, got 1", "at b: missing, expected 2", "at z: unexpected key, got 9") instead of only dumping both tables. `toMatchObject` paths lose their leading dot for the same format.

- `runAll` now also accepts a plain array of `{ name = string, fn = function }` spec entries, so the core runs outside Roblox (Lune, CI). Instance roots work exactly as before.
- Internal requires use string paths (`require("./matchers")`), which resolve identically in Roblox and Lune.
- `tick()` replaced with `os.clock()`; outside Instance discovery the framework uses no Roblox-only APIs.
- `Tests/RunInLune.luau` runs the self-test suite under the Lune runtime. A GitHub Actions workflow runs it on every push.

## 0.1.0 (2026-06-10)

- Initial public history: describe/it with skip, only, and each; hooks; expect with 12 matchers plus never negation and custom matchers; spies; strict-table fixture factories; reentrancy-guarded runner.
