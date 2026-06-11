# Agent guide

This repository is TasteTest, a zero-dependency Jest-style test framework for Roblox Luau.

If your tooling supports Agent Skills, the full agent-facing guide is [SKILL.md](SKILL.md): the spec-writing recipe, how to run suites in Roblox and in Lune, how to read verdicts, and the mistakes that cost the most time. The `references/` folder behind it documents every matcher, the spy and fixture APIs, and runner semantics for debugging.

If not, read [SKILL.md](SKILL.md) anyway; it is plain markdown and self-contained. Human-oriented documentation starts at [README.md](README.md).

Repository conventions: the framework's own tests live in `Tests/` and run with `lune run Tests/RunInLune.luau` (CI does this on every push) or via the same suite inside Roblox Studio. Keep `CHANGELOG.md` updated with user-visible changes. Commit messages are plain with no attribution trailers. Before changing code, read [CONTRIBUTING.md](CONTRIBUTING.md); it defines what is in scope and what every change needs to ship with.
