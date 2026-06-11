# Matchers

Every matcher is called dot-style on the result of `expect(actual)`. A failed matcher raises an error whose message includes what was expected and what was received; the runner records it under the test's `describe > it` path.

## Equality

| Matcher | Semantics |
|---|---|
| `toBe(expected)` | Strict `==`. Tables compare by identity, not contents. |
| `toEqual(expected)` | Deep equality, recursive on tables, comparing raw keys and values only: metatables are NOT compared, so a strictTable fixture and a plain table with the same fields compare equal. Failure messages name the path of the first difference: `at a.b.c: expected 2, got 1`, `at b: missing, expected 2`, `at z: unexpected key, got 9`, or `at top level: ...` for scalar mismatches. |
| `toMatchObject(subset)` | Partial deep equality. Extra fields in `actual` are fine; every field in `subset` must match. Same path-style failure messages. |
| `toBeCloseTo(expected, numDigits?)` | Float comparison. `numDigits` defaults to 10. Use for any arithmetic result. |

## Truthiness and comparison

| Matcher | Semantics |
|---|---|
| `toBeTruthy()` / `toBeFalsy()` | Lua truthiness: only `false` and `nil` are falsy. `0` and `""` are truthy. |
| `toBeGreaterThan(n)` / `toBeGreaterThanOrEqual(n)` | Numeric. Errors usefully when actual is not a number. |
| `toBeLessThan(n)` / `toBeLessThanOrEqual(n)` | Numeric. |

## Containers and errors

| Matcher | Semantics |
|---|---|
| `toContain(item)` | Array membership via deep equality over `ipairs`. Tables only; it does NOT do string substring matching. |
| `toThrow(pattern?)` | `actual` must be a function. Calls it via pcall and passes when it errors. With `pattern`, the error message must match the Lua string pattern, so escape magic characters: `toThrow("a%.b")`. To assert on a failure message, this is the tool (not `toContain`). |

## Spy matchers

See `spies-and-fixtures.md` for the spy API itself.

| Matcher | Semantics |
|---|---|
| `toHaveBeenCalled()` | At least one recorded call. |
| `toHaveBeenCalledTimes(n)` | Exactly `n` recorded calls. |
| `toHaveBeenCalledWith(...)` | Some single recorded call whose full argument list deep-equals the given arguments. Nil-aware by position: a call `spy("a", nil, "c")` matches only `toHaveBeenCalledWith("a", nil, "c")`. |

All three require the spy TABLE (the first return of `TasteTest.spy()`), not the plain function form.

## Negation

`expect(x).never.<matcher>(...)` inverts any matcher, including custom ones: `expect(spy).never.toHaveBeenCalled()`.

## Custom matchers

```lua
TasteTest.addMatcher("toBeEven", function(actual)
    if type(actual) ~= "number" then return false, "expected a number" end
    if actual % 2 ~= 0 then return false, string.format("expected %d to be even", actual) end
    return true, "is even"
end)
```

Signature: `(actual, ...args) -> (ok: boolean, message: string)`. The message is shown on failure, and with a `NOT:` prefix when the matcher passes under `never`. Register matchers at spec-registration time (top of the returned function), not inside a test.

## Parameterized tests

```lua
-- Array rows: positional access, $1 $2 $3 in the name template
it.each({
    { 1, 1, 2 },
    { 2, 3, 5 },
})("$1 + $2 = $3", function(a, b, sum)
    expect(a + b).toBe(sum)
end)

-- Dict rows: $key access, the whole row is passed as one argument
it.each({
    { case = "happy", input = "x" },
    { case = "edge",  input = "" },
})("scenario: $case", function(row)
    expect(transform(row.input)).toBeTruthy()
end)
```

`describe.each(rows)(nameFmt, fn)` works the same for groups. `.skip` and `.only` propagate to all rows: `it.each(rows).skip(...)`. A `$token` with no value in some row substitutes an empty string and adds a registration warning to `verdict.warnings`; treat that warning as a bug in the template or the rows.

## Skip, only, timeouts

- `it.skip` / `describe.skip` mark tests skipped (counted in `verdict.skipped`).
- `it.only` / `describe.only` run ONLY the marked tests; everything else is reported skipped. Never commit `.only`.
- `it(name, fn, { timeout = seconds })` raises the per-test timeout for a yielding test (default 5s, suite-wide default via `runAll(root, { timeout = s })`). The opts argument is also accepted by `it.skip`, `it.only`, and as the third argument after an `it.each(rows)(nameFmt, fn, opts)` template, where it applies to every generated row.
