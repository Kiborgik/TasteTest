# Spies and strict-table fixtures

## Spies

`TasteTest.spy(impl?)` returns TWO values bound to the same call record:

```lua
local spy, spyFn = TasteTest.spy()
```

- `spy` is a callable table carrying `.calls`. Pass THIS to the spy matchers.
- `spyFn` is a plain function. Pass THIS into code that validates its inputs with `type(x) == "function"`; callable tables fail that check.

Calls through either form append to the same `.calls` list.

### The call record

Each entry in `.calls` is a `table.pack` result: `spy("a", 1)` records `{ n = 2, [1] = "a", [2] = 1 }`. Consequences:

- `#spy.calls` is the call count; `spy.calls[i].n` is the argument count of call `i` (explicit trailing nils included).
- `expect(spy.calls[1]).toEqual({ "a", 1 })` FAILS because of the `n` field. Either index positionally (`spy.calls[1][1]`) or use `toHaveBeenCalledWith("a", 1)`, which packs its own arguments and therefore compares correctly, including explicit nils by position.

### Return values

```lua
local doubler, doublerFn = TasteTest.spy(function(x) return x * 2 end)
doublerFn(5) -- 10, and the call is recorded
```

Without `impl`, calls return nil. For per-call return sequences there is deliberately no `mockReturnValueOnce` chain; close over an index instead:

```lua
local i = 0
local responses = { "first", "second" }
local stub, stubFn = TasteTest.spy(function()
    i += 1
    return responses[i]
end)
```

## Strict-table fixtures

`TasteTest.strictTable(name, canonicalKeys, factory)` builds fixture factories that fail loudly at the point of mistake instead of producing confusing downstream failures:

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
```

Two protections:

1. Construction rejects unknown override keys: `makePlayerData({ coinz = 1 })` errors immediately, naming the factory and the bad key. This catches test typos.
2. Reads of non-canonical keys error: `d.unknwon` errors instead of silently returning nil. This catches drift when the real data shape changes and the fixture didn't.

Escape hatches: raw assignment (`d.x = 1`) and `pairs(d)` iteration bypass the read check, so production code that enumerates the table still works. The strict read check applies to string keys only; numeric or other non-string indexing returns nil without erroring, so array-shaped data inside a fixture is not drift-protected.

Use a strict factory whenever more than one spec constructs the same shaped data. One factory per data shape, defined in a shared fixtures module, is easier to keep current than hand-built tables scattered across specs.
