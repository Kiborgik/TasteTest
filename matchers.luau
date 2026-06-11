--[[
  Matchers — pattern follows Roblox/jest-roblox/src/expect (registry of matcher
  functions; .never namespace for negation). Built-in matchers:
    Equality:   toBe, toEqual
    Truthiness: toBeTruthy, toBeFalsy
    Numeric:    toBeCloseTo, toBeGreaterThan, toBeGreaterThanOrEqual,
                toBeLessThan, toBeLessThanOrEqual
    Collection: toContain
    Errors:     toThrow
  Extensible via Matchers.addMatcher.
]]

local Matchers = {}

-- ============================================
-- Helpers
-- ============================================
local function deepEqual(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function formatValue(v)
    if type(v) == "table" then
        local parts = {}
        local seen = 0
        for k, x in pairs(v) do
            seen = seen + 1
            if seen > 6 then table.insert(parts, "..."); break end
            table.insert(parts, tostring(k) .. "=" .. tostring(x))
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

local function childPath(path, k)
    return path == "" and tostring(k) or (path .. "." .. tostring(k))
end

-- Walks both tables and returns a human description of the first difference
-- found, or nil if none. Caller is expected to have already failed deepEqual;
-- key order from pairs() makes "first" arbitrary but stable enough for messages.
local function firstDifference(actual, expected, path)
    if actual == expected then return nil end
    if type(actual) ~= "table" or type(expected) ~= "table" then
        local where = path == "" and "at top level" or ("at " .. path)
        return string.format("%s: expected %s, got %s", where, formatValue(expected), formatValue(actual))
    end
    for k, expectedV in pairs(expected) do
        local subPath = childPath(path, k)
        if actual[k] == nil then
            return string.format("at %s: missing, expected %s", subPath, formatValue(expectedV))
        end
        local diff = firstDifference(actual[k], expectedV, subPath)
        if diff then return diff end
    end
    for k in pairs(actual) do
        if expected[k] == nil then
            local subPath = childPath(path, k)
            return string.format("at %s: unexpected key, got %s", subPath, formatValue(actual[k]))
        end
    end
    return nil
end

-- ============================================
-- Matcher registry — each matcher returns (ok: bool, msg: string)
-- ============================================
local registry = {}

function registry.toBe(actual, expected)
    return actual == expected,
        string.format("expected %s == %s", formatValue(actual), formatValue(expected))
end

function registry.toEqual(actual, expected)
    if deepEqual(actual, expected) then
        return true, string.format("expected deep-equal: actual=%s expected=%s",
            formatValue(actual), formatValue(expected))
    end
    local diff = firstDifference(actual, expected, "") or "values differ"
    return false, string.format("expected deep-equal: %s (actual=%s expected=%s)",
        diff, formatValue(actual), formatValue(expected))
end


local function matchObject(actual, expected, path)
    local pathLabel = path == "" and "<root>" or path
    if type(actual) ~= "table" then
        return false, string.format("at %s: expected table, got %s", pathLabel, type(actual))
    end
    if type(expected) ~= "table" then
        return false, string.format("at %s: matcher expected table, got %s", pathLabel, type(expected))
    end
    for k, v in pairs(expected) do
        local subPath = childPath(path, k)
        local actualV = actual[k]
        if type(v) == "table" then
            -- Recurse — the recursive call's own type check handles non-table actualV
            -- with the correct subPath in the error message.
            local ok, msg = matchObject(actualV, v, subPath)
            if not ok then return false, msg end
        elseif actualV == nil and v ~= nil then
            return false, string.format("at %s: missing, expected %s", subPath, formatValue(v))
        elseif actualV ~= v then
            return false, string.format("at %s: expected %s, got %s", subPath, formatValue(v), formatValue(actualV))
        end
    end
    return true, "matches"
end

function registry.toMatchObject(actual, expected)
    return matchObject(actual, expected, "")
end

function registry.toBeTruthy(actual)
    return (actual and true or false),
        string.format("expected truthy, got %s", formatValue(actual))
end

function registry.toBeFalsy(actual)
    return (not actual),
        string.format("expected falsy, got %s", formatValue(actual))
end

-- Float-precision-friendly equality. Defaults to 10 decimal digits of precision
-- (tolerance = 0.5e-10), tight enough to catch real bugs but loose enough to
-- allow IEEE 754 cumulative error (e.g., 0 + 0.1*3 = 0.30000000000000004).
-- Matches Jest's `toBeCloseTo(expected, numDigits)` API shape, but the default
-- numDigits is intentionally 10 (Jest uses 2): tight enough to catch real bugs
-- while still absorbing IEEE 754 cumulative error.
function registry.toBeCloseTo(actual, expected, numDigits)
    if type(actual) ~= "number" or type(expected) ~= "number" then
        return false, string.format("toBeCloseTo requires numbers; got actual=%s expected=%s",
            type(actual), type(expected))
    end
    numDigits = numDigits or 10
    local tolerance = 0.5 * (10 ^ -numDigits)
    local diff = math.abs(actual - expected)
    return diff < tolerance,
        string.format("expected %s to be close to %s (within %s, actual diff = %s)",
            tostring(actual), tostring(expected), tostring(tolerance), tostring(diff))
end

-- Numeric comparison matchers (Jest-compatible). Better failure messages than
-- the `expect(x < n).toBe(true)` workaround — "expected 0.42 to be less than
-- 0.3" tells you the actual value, "expected true, got false" doesn't.
local function ensureNumber(name, v)
    if type(v) ~= "number" then
        return false, string.format("%s requires a number, got %s (%s)",
            name, type(v), formatValue(v))
    end
    return true
end

function registry.toBeGreaterThan(actual, expected)
    local ok, msg = ensureNumber("toBeGreaterThan", actual)
    if not ok then return false, msg end
    return actual > expected,
        string.format("expected %s to be greater than %s", tostring(actual), tostring(expected))
end

function registry.toBeGreaterThanOrEqual(actual, expected)
    local ok, msg = ensureNumber("toBeGreaterThanOrEqual", actual)
    if not ok then return false, msg end
    return actual >= expected,
        string.format("expected %s to be >= %s", tostring(actual), tostring(expected))
end

function registry.toBeLessThan(actual, expected)
    local ok, msg = ensureNumber("toBeLessThan", actual)
    if not ok then return false, msg end
    return actual < expected,
        string.format("expected %s to be less than %s", tostring(actual), tostring(expected))
end

function registry.toBeLessThanOrEqual(actual, expected)
    local ok, msg = ensureNumber("toBeLessThanOrEqual", actual)
    if not ok then return false, msg end
    return actual <= expected,
        string.format("expected %s to be <= %s", tostring(actual), tostring(expected))
end

-- Array-style containment (uses sequential ipairs; works for the project's
-- common list-of-tables shape). For string-in-string use string.find directly.
function registry.toContain(actual, item)
    if type(actual) ~= "table" then
        return false, string.format("toContain requires a table, got %s", type(actual))
    end
    for _, v in ipairs(actual) do
        if deepEqual(v, item) then
            return true, string.format("(contains %s)", formatValue(item))
        end
    end
    return false, string.format("expected list to contain %s; got %s",
        formatValue(item), formatValue(actual))
end

function registry.toThrow(actual, pattern)
    if type(actual) ~= "function" then
        return false, "toThrow requires a function: expect(function() ... end).toThrow()"
    end
    local ok, err = pcall(actual)
    if ok then return false, "expected to throw, but did not" end
    if pattern then
        local findOk, found = pcall(string.find, tostring(err), pattern)
        if not findOk then
            -- A malformed Lua pattern would otherwise replace the test's real
            -- failure with a cryptic pattern-parse error from inside find.
            return false, string.format("toThrow received an invalid Lua pattern %q: %s", pattern, tostring(found))
        end
        if not found then
            return false, string.format("expected error to match %q, got %q", pattern, tostring(err))
        end
    end
    return true, "(threw as expected)"
end


-- The spy matcher family operates on the callable table returned by
-- TasteTest.spy() (anything with a .calls array works). Note the plain
-- function form returned as the second value is NOT a valid actual here;
-- pass the spy table.
local function requireSpy(matcherName, actual)
    if type(actual) == "table" and type(actual.calls) == "table" then
        return actual.calls
    end
    return nil, matcherName .. " expected a spy (a table with a .calls array), got " .. type(actual)
end

function registry.toHaveBeenCalled(actual)
    local calls, spyErr = requireSpy("toHaveBeenCalled", actual)
    if not calls then return false, spyErr end
    return #calls > 0, string.format("expected spy to have been called, call count is %d", #calls)
end

function registry.toHaveBeenCalledTimes(actual, n)
    local calls, spyErr = requireSpy("toHaveBeenCalledTimes", actual)
    if not calls then return false, spyErr end
    if type(n) ~= "number" then
        return false, "toHaveBeenCalledTimes requires a number, got " .. type(n)
    end
    return #calls == n, string.format("expected spy to have been called %d times, call count is %d", n, #calls)
end

function registry.toHaveBeenCalledWith(actual, ...)
    local calls, spyErr = requireSpy("toHaveBeenCalledWith", actual)
    if not calls then return false, spyErr end
    -- table.pack on both sides makes explicit nil arguments positional:
    -- spy("a", nil, "c") only matches toHaveBeenCalledWith("a", nil, "c").
    local expectedArgs = table.pack(...)
    for _, call in ipairs(calls) do
        if deepEqual(call, expectedArgs) then
            return true, "(spy was called with the expected arguments)"
        end
    end
    local argParts = {}
    for i = 1, expectedArgs.n do
        argParts[i] = formatValue(expectedArgs[i])
    end
    return false, string.format("expected spy to have been called with (%s), %d recorded calls had no match",
        table.concat(argParts, ", "), #calls)
end

-- ============================================
-- Chain construction
-- ============================================
local function makeChain(actual, isNegated)
    local chain = {}
    for name, matcherFn in pairs(registry) do
        chain[name] = function(...)
            local ok, msg = matcherFn(actual, ...)
            if isNegated then
                ok = not ok
                msg = "NOT: " .. msg
            end
            if not ok then error(msg, 3) end
        end
    end
    return chain
end

-- ============================================
-- Public API
-- ============================================
function Matchers.expect(actual)
    local m = makeChain(actual, false)
    m.never = makeChain(actual, true)
    return m
end

-- Extensibility: register a custom matcher at runtime.
--   fn signature: function(actual, ...) -> (ok: bool, msg: string)
function Matchers.addMatcher(name, fn)
    if type(name) ~= "string" or type(fn) ~= "function" then
        error("addMatcher(name: string, fn: function)", 2)
    end
    registry[name] = fn
end

return Matchers
