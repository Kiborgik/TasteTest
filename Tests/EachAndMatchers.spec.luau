--[[
    EachAndMatchers.spec — TasteTest meta-test for it.each / describe.each / toMatchObject.
    Runs under the "TasteTestMeta" scenario.
]]

return function()
    local TasteTest = require("../Start")
    local describe, it, expect = TasteTest.describe, TasteTest.it, TasteTest.expect

    describe("toMatchObject", function()
        it("matches a strict subset of keys", function()
            expect({ a = 1, b = 2, c = 3 }).toMatchObject({ a = 1, c = 3 })
        end)

        it("matches when expected is empty", function()
            expect({ a = 1, b = 2 }).toMatchObject({})
        end)

        it("fails when a key value differs", function()
            expect(function()
                expect({ a = 1 }).toMatchObject({ a = 2 })
            end).toThrow()
        end)

        it("fails when a required key is missing from actual", function()
            expect(function()
                expect({ a = 1 }).toMatchObject({ a = 1, b = 2 })
            end).toThrow()
        end)

        it("recurses into nested tables (partial-equality semantics)", function()
            expect({ user = { id = 5, name = "Pat", email = "p@x" }, ts = 100 })
                .toMatchObject({ user = { id = 5 } })
        end)

        it("fails with path in error message when nested mismatch", function()
            expect(function()
                expect({ user = { id = 5 } }).toMatchObject({ user = { id = 6 } })
            end).toThrow("user.id")
        end)

        it("fails when actual is not a table", function()
            expect(function()
                expect(42).toMatchObject({ a = 1 })
            end).toThrow()
        end)

        it("never.toMatchObject — negation pass", function()
            expect({ a = 1 }).never.toMatchObject({ a = 2 })
        end)

        it("never.toMatchObject — negation fail when it would match", function()
            expect(function()
                expect({ a = 1, b = 2 }).never.toMatchObject({ a = 1 })
            end).toThrow()
        end)
    end)

    -- ===== it.each — array rows =====
    -- Sibling-witness pattern: register tests via it.each, then verify them in a sibling describe.
    local arrayRowsSeen = {}
    describe("it.each array rows — registers one test per row", function()
        it.each({
            { 1, 1, 2 },
            { 2, 3, 5 },
            { 10, 20, 30 },
        })("$1 + $2 = $3", function(a, b, sum)
            table.insert(arrayRowsSeen, { a = a, b = b, sum = sum, computed = a + b })
            expect(a + b).toBe(sum)
        end)
    end)
    describe("it.each array rows — verification sibling", function()
        it("registered and ran all three rows in order", function()
            expect(#arrayRowsSeen).toBe(3)
            expect(arrayRowsSeen[1]).toEqual({ a = 1, b = 1, sum = 2, computed = 2 })
            expect(arrayRowsSeen[2]).toEqual({ a = 2, b = 3, sum = 5, computed = 5 })
            expect(arrayRowsSeen[3]).toEqual({ a = 10, b = 20, sum = 30, computed = 30 })
        end)
    end)

    -- ===== it.each — dict rows =====
    local dictRowsSeen = {}
    describe("it.each dict rows", function()
        it.each({
            { name = "alpha", input = "x", out = "X" },
            { name = "beta",  input = "y", out = "Y" },
        })("case: $name (input=$input)", function(row)
            table.insert(dictRowsSeen, row.name)
            expect(row.out).toBe(string.upper(row.input))
        end)
    end)
    describe("it.each dict rows — verification sibling", function()
        it("ran both rows with full row table", function()
            expect(#dictRowsSeen).toBe(2)
            expect(dictRowsSeen[1]).toBe("alpha")
            expect(dictRowsSeen[2]).toBe("beta")
        end)
    end)

    -- ===== it.each — empty rows (sibling-witness pattern) =====
    local emptyEachCallCount = 0
    describe("it.each empty rows — registers nothing", function()
        it.each({})("never runs", function()
            emptyEachCallCount = emptyEachCallCount + 1
        end)
    end)
    describe("it.each empty rows — verification sibling", function()
        it("no rows ran and registration did not error", function()
            expect(emptyEachCallCount).toBe(0)
        end)
    end)

    -- ===== it.each — mixed-shape rows rejection (H2 fix verification) =====
    describe("it.each rejects mixed-key rows at registration", function()
        it("row with both numerical and string keys errors", function()
            expect(function()
                TasteTest.it.each({ { "x", name = "y" } })("test", function() end)
            end).toThrow("both numerical and string keys")
        end)
        it("rows of different shapes (array + dict) errors", function()
            expect(function()
                TasteTest.it.each({ { 1, 2 }, { a = 1, b = 2 } })("test", function() end)
            end).toThrow("must all be arrays or all be dicts")
        end)
        it("non-table row errors", function()
            expect(function()
                TasteTest.it.each({ 42 })("test", function() end)
            end).toThrow("expected table")
        end)
    end)

    -- ===== it.each — missing template variables substitute "" and warn =====
    -- We can't easily observe warnings from inside the same runAll, so this is
    -- a registration-time smoke check that the substitution doesn't error and
    -- that running tests works regardless of misses.
    local missingVarRan = false
    describe("it.each missing template variables — graceful behavior", function()
        it.each({ { name = "x" } })("template has $missing and $name", function(row)
            missingVarRan = true
            expect(row.name).toBe("x")
        end)
    end)
    describe("it.each missing template variables — verification sibling", function()
        it("test ran despite missing $missing token", function()
            expect(missingVarRan).toBe(true)
        end)
    end)

    -- ===== it.each — array rows with nil holes keep their arity =====
    -- Regression: table.unpack(row) alone stops at #row, which is undefined
    -- for { "a", nil, "c" }; the runner now unpacks to the highest numeric key.
    -- (Trailing nils in row literals are still unknowable — Lua drops them at
    -- construction — so only interior holes are guaranteed.)
    describe("it.each nil-hole rows", function()
        it.each({
            { "a", nil, "c" },
        })("interior nil reaches the test as nil", function(a, b, c)
            expect(a).toBe("a")
            expect(b).toBe(nil)
            expect(c).toBe("c")
        end)
    end)

    describe("it.each accepts per-row timeout opts", function()
        it.each({ { 1 } })("row $1 runs with a raised timeout", function(v)
            expect(v).toBe(1)
        end, { timeout = 10 })
    end)

    -- ===== it.each.skip — propagates to all rows =====
    local skipRowsSeen = 0
    describe("it.each.skip propagates skip to all rows", function()
        it.each({ { 1 }, { 2 }, { 3 } }).skip("skipped $1", function(_)
            skipRowsSeen = skipRowsSeen + 1
        end)
    end)
    describe("it.each.skip — verification", function()
        it("no skipped rows ran", function()
            expect(skipRowsSeen).toBe(0)
        end)
    end)

    -- ===== describe.each — runs one describe per row =====
    local describeEachSeen = {}
    describe.each({
        { case = "small", n = 1 },
        { case = "big",   n = 100 },
    })("describe.each: size $case", function(row)
        it("captures the row n=$n", function()
            table.insert(describeEachSeen, row.case)
            expect(row.n > 0).toBeTruthy()
        end)
    end)
    describe("describe.each — verification", function()
        it("created two describes, each ran its own it", function()
            expect(#describeEachSeen).toBe(2)
            expect(describeEachSeen[1]).toBe("small")
            expect(describeEachSeen[2]).toBe("big")
        end)
    end)
end
