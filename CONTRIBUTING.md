# Contributing to TasteTest

## What kind of changes fit

TasteTest is meant to stay a single folder that works when copied into `ReplicatedStorage`, with the same core running in Roblox Studio and under Lune. Before starting work, check your idea against these constraints:

- The framework has to keep working with nothing else installed. Changes that depend on Rojo, Wally, a build step, or a companion plugin will not be merged.
- Core code runs in both runtimes. Roblox-only APIs are acceptable behind a runtime guard (`installWarningCapture` in `runner.luau` shows the pattern), as long as the behavior in the other runtime is documented.
- The public API (`Start.luau` exports, `runAll` opts, verdict fields, matcher behavior) stays backward compatible. Additive changes are fine; behavioral changes need a strong reason and a CHANGELOG entry describing exactly what changed.

Snapshot testing, module mocking, fake timers, and parallel execution are out of scope. The README explains the reasoning, and Jest Lua already covers those needs.

## Development setup

1. Clone the repository.
2. Install [Lune](https://github.com/lune-org/lune); it is a single binary.
3. Run `lune run Tests/RunInLune.luau` from the repo root. A passing run exits 0 and reports no unexpected warnings.

To test inside Roblox Studio as well, copy the folder into `ReplicatedStorage` of any place and run:

```lua
local TasteTest = require(game.ReplicatedStorage.TasteTest.Start)
print(game:GetService("HttpService"):JSONEncode(TasteTest.runAll(game.ReplicatedStorage.TasteTest.Tests)))
```

CI runs the Lune suite on every push and pull request. If a change affects Studio-only behavior (Instance discovery, LogService capture), verify it manually in Studio and describe what you did in the pull request.

## Tests

Behavior changes need specs in `Tests/`; a new spec file also gets an entry in the list inside `Tests/RunInLune.luau`. For bug fixes, include a regression test and confirm it fails on the old code before fixing.

`runAll` is not reentrant, so runner behavior is tested through the exported seams (`Runner._runTestFn`, `_runTestWithHooks`, `_classifyWarnings`). `Tests/Timeouts.spec.luau` and `Tests/WarningGate.spec.luau` show how, including how to fake a scheduler so timeout paths run without real waiting.

The suite runs with the strict warning gate enabled. If a change legitimately emits a warning, add it to the allowlist in `Tests/RunInLune.luau` together with a reason rather than loosening the gate.

Tests must be deterministic: nothing timing-dependent, no raw `math.random`, no reliance on `pairs` ordering. Pass time and random functions in as parameters.

## Code and docs style

Plain Luau, four-space indent, LF line endings (enforced through `.gitattributes`). Write comments only where they capture a constraint the code itself cannot show. Keep user-facing error messages in ASCII, and include the name of the matcher or function that produced them.

When public behavior changes, update `README.md`, the matching file under `references/`, `SKILL.md` if the recipe changed, and the Unreleased section of `CHANGELOG.md`. Code examples in the docs should stay copy-paste runnable.

## Pull requests and releases

Keep a pull request to one logical change, and split refactors from fixes. In the description, state what changed, why, and how it was verified (Lune output, Studio notes, or both). Commit messages are short imperative sentences without attribution trailers.

Versions follow semver. Maintainers handle tagging; contributors add a CHANGELOG entry under Unreleased. Pushing a `v*` tag triggers the release workflow, which runs the suite, builds `TasteTest.rbxm` via `Tools/BuildRbxm.luau`, and attaches it to a GitHub release.
