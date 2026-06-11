--[[
    Hooks.spec — TasteTest meta-test for beforeAll / afterAll.
    Runs under the "TasteTestMeta" scenario.
]]

return function()
    local TasteTest = require("../Start")
    local describe, it, expect = TasteTest.describe, TasteTest.it, TasteTest.expect
    local beforeAll, afterAll = TasteTest.beforeAll, TasteTest.afterAll
    local beforeEach = TasteTest.beforeEach

    -- Test 1: beforeAll fires once per describe scope
    describe("beforeAll fires once before first test", function()
        local count = 0
        beforeAll(function() count = count + 1 end)

        it("first test sees count == 1", function()
            expect(count).toBe(1)
        end)
        it("second test still sees count == 1 (not re-fired)", function()
            expect(count).toBe(1)
        end)
        it("third test still sees count == 1", function()
            expect(count).toBe(1)
        end)
    end)

    -- Test 2: multiple beforeAll siblings all run, in registration order
    describe("multiple beforeAll siblings", function()
        local order = {}
        beforeAll(function() table.insert(order, "first") end)
        beforeAll(function() table.insert(order, "second") end)
        beforeAll(function() table.insert(order, "third") end)

        it("all three fired in order", function()
            expect(order[1]).toBe("first")
            expect(order[2]).toBe("second")
            expect(order[3]).toBe("third")
        end)
    end)

    -- Test 3: nested describes — outer beforeAll fires once for whole subtree
    describe("nested describes — outer beforeAll fires once for whole subtree", function()
        local outerCount = 0
        local innerCount1, innerCount2 = 0, 0  -- independent counters per inner describe
        beforeAll(function() outerCount = outerCount + 1 end)

        describe("inner", function()
            beforeAll(function() innerCount1 = innerCount1 + 1 end)
            it("inner test 1: outer fired once, own inner once", function()
                expect(outerCount).toBe(1)
                expect(innerCount1).toBe(1)
            end)
            it("inner test 2: still 1, own inner still 1", function()
                expect(outerCount).toBe(1)
                expect(innerCount1).toBe(1)
            end)
        end)

        describe("another inner", function()
            beforeAll(function() innerCount2 = innerCount2 + 1 end)
            it("inner test 3: outer still 1, own inner fired once", function()
                expect(outerCount).toBe(1)
                expect(innerCount2).toBe(1)
            end)
        end)
    end)

    -- Test 4: beforeEach inheritance to inner describe is preserved (sanity check)
    describe("beforeEach STILL runs for inner-describe tests (inheritance preserved)", function()
        local beforeEachCount = 0
        beforeEach(function() beforeEachCount = beforeEachCount + 1 end)

        describe("inner", function()
            it("test 1: outer beforeEach fired", function()
                expect(beforeEachCount).toBe(1)
            end)
            it("test 2: outer beforeEach fired again", function()
                expect(beforeEachCount).toBe(2)
            end)
        end)
    end)

    -- Test 5: afterAll runs after all tests in scope.
    -- We can't assert afterAll's effect inside the scope where it runs, so we
    -- record into a module-level table and verify in a SIBLING describe that
    -- registers AFTER this one.
    local afterAllOrder = {}
    describe("scope under test — records its lifecycle", function()
        beforeAll(function() table.insert(afterAllOrder, "beforeAll") end)
        afterAll(function() table.insert(afterAllOrder, "afterAll") end)
        it("test A", function() table.insert(afterAllOrder, "testA") end)
        it("test B", function() table.insert(afterAllOrder, "testB") end)
    end)
    describe("sibling — verifies lifecycle of prior scope", function()
        it("recorded order is beforeAll, testA, testB, afterAll", function()
            expect(#afterAllOrder).toBe(4)
            expect(afterAllOrder[1]).toBe("beforeAll")
            expect(afterAllOrder[2]).toBe("testA")
            expect(afterAllOrder[3]).toBe("testB")
            expect(afterAllOrder[4]).toBe("afterAll")
        end)
    end)

    -- Test 6: afterAll runs in reverse-nesting order — assertions are
    -- order-independent on the contract (afterAll AFTER tests in scope;
    -- inner.afterAll BEFORE outer.afterAll). We don't assert direct-vs-children
    -- test ordering because that's an implementation detail of visitNode.
    local nestedAfter = {}
    describe("outer — records nested afterAll order", function()
        afterAll(function() table.insert(nestedAfter, "outer.afterAll") end)
        describe("inner", function()
            afterAll(function() table.insert(nestedAfter, "inner.afterAll") end)
            it("inner test", function() table.insert(nestedAfter, "inner.test") end)
        end)
        it("outer test", function() table.insert(nestedAfter, "outer.test") end)
    end)
    describe("verifies nested afterAll contract (order-independent on test interleaving)", function()
        local function findIdx(t, v)
            for i, x in ipairs(t) do if x == v then return i end end
            return nil
        end

        it("all four events recorded", function()
            expect(#nestedAfter).toBe(4)
            expect(findIdx(nestedAfter, "outer.test")).never.toBe(nil)
            expect(findIdx(nestedAfter, "inner.test")).never.toBe(nil)
            expect(findIdx(nestedAfter, "inner.afterAll")).never.toBe(nil)
            expect(findIdx(nestedAfter, "outer.afterAll")).never.toBe(nil)
        end)
        it("inner.afterAll runs BEFORE outer.afterAll (the contract)", function()
            local i, o = findIdx(nestedAfter, "inner.afterAll"), findIdx(nestedAfter, "outer.afterAll")
            expect(i < o).toBe(true)
        end)
        it("afterAll runs AFTER its scope's tests (the contract)", function()
            local innerTestIdx = findIdx(nestedAfter, "inner.test")
            local innerAfterIdx = findIdx(nestedAfter, "inner.afterAll")
            expect(innerTestIdx < innerAfterIdx).toBe(true)
            local outerTestIdx = findIdx(nestedAfter, "outer.test")
            local outerAfterIdx = findIdx(nestedAfter, "outer.afterAll")
            expect(outerTestIdx < outerAfterIdx).toBe(true)
        end)
    end)

    -- Test 7: top-level hooks (outside any describe) are rejected loudly.
    describe("top-level hook rejection", function()
        it("beforeAll outside describe throws", function()
            expect(function() TasteTest.beforeAll(function() end) end).toThrow("describe")
        end)
        it("afterAll outside describe throws", function()
            expect(function() TasteTest.afterAll(function() end) end).toThrow("describe")
        end)
        it("beforeEach outside describe throws", function()
            expect(function() TasteTest.beforeEach(function() end) end).toThrow("describe")
        end)
        it("afterEach outside describe throws", function()
            expect(function() TasteTest.afterEach(function() end) end).toThrow("describe")
        end)
    end)

    -- Test 8: multiple beforeAll failures in same scope ARE all collected,
    -- visible via verdict.beforeAllErrors. We can't easily exercise the
    -- cascade-to-nested directly from inside the meta-suite (would corrupt
    -- the outer run's verdict), so this is a pure structural/registration
    -- test of the API surface.
    describe("multiple beforeAll siblings registered (failure-collection API surface)", function()
        local fired = {}
        beforeAll(function() table.insert(fired, "first") end)
        beforeAll(function() table.insert(fired, "second") end)
        beforeAll(function() table.insert(fired, "third") end)

        it("all three siblings ran in registration order", function()
            expect(fired[1]).toBe("first")
            expect(fired[2]).toBe("second")
            expect(fired[3]).toBe("third")
        end)
    end)
end
