--[[
  SpyMatchers.spec — the toHaveBeenCalled matcher family and the path-diff
  output of toEqual / toMatchObject failure messages.
]]

return function()
    local TasteTest = require("../Start")
    local describe, it, expect =
        TasteTest.describe, TasteTest.it, TasteTest.expect

    describe("toHaveBeenCalled", function()
        it("passes after at least one call", function()
            local spy = TasteTest.spy()
            spy()
            expect(spy).toHaveBeenCalled()
        end)

        it("fails on a fresh spy", function()
            local spy = TasteTest.spy()
            expect(function()
                expect(spy).toHaveBeenCalled()
            end).toThrow()
        end)

        it("supports never on a fresh spy", function()
            local spy = TasteTest.spy()
            expect(spy).never.toHaveBeenCalled()
        end)

        it("counts calls made through the plain function form", function()
            local spy, spyFn = TasteTest.spy()
            spyFn()
            expect(spy).toHaveBeenCalled()
        end)

        it("rejects values that are not spies", function()
            expect(function()
                expect(5).toHaveBeenCalled()
            end).toThrow("expected a spy")
        end)
    end)

    describe("toHaveBeenCalledTimes", function()
        it("matches the exact call count", function()
            local spy = TasteTest.spy()
            spy()
            spy()
            spy()
            expect(spy).toHaveBeenCalledTimes(3)
            expect(spy).never.toHaveBeenCalledTimes(2)
        end)

        it("accepts zero for a fresh spy", function()
            local spy = TasteTest.spy()
            expect(spy).toHaveBeenCalledTimes(0)
        end)
    end)

    describe("toHaveBeenCalledWith", function()
        it("matches any single call by deep equality on args", function()
            local spy = TasteTest.spy()
            spy("a", { x = 1 })
            spy("b")
            expect(spy).toHaveBeenCalledWith("a", { x = 1 })
            expect(spy).toHaveBeenCalledWith("b")
        end)

        it("fails when no call matches", function()
            local spy = TasteTest.spy()
            spy("a", 1)
            expect(function()
                expect(spy).toHaveBeenCalledWith("a", 2)
            end).toThrow()
        end)

        it("distinguishes explicit nil arguments by position", function()
            local spy = TasteTest.spy()
            spy("a", nil, "c")
            expect(spy).toHaveBeenCalledWith("a", nil, "c")
            expect(spy).never.toHaveBeenCalledWith("a")
        end)
    end)

    describe("toEqual failure diffs", function()
        it("reports the path of the first nested difference", function()
            expect(function()
                expect({ a = { b = { c = 1 } } }).toEqual({ a = { b = { c = 2 } } })
            end).toThrow("at a%.b%.c")
        end)

        it("reports a missing key with its path", function()
            expect(function()
                expect({ a = 1 }).toEqual({ a = 1, b = 2 })
            end).toThrow("at b: missing")
        end)

        it("reports an unexpected extra key with its path", function()
            expect(function()
                expect({ a = 1, z = 9 }).toEqual({ a = 1 })
            end).toThrow("at z: unexpected")
        end)

        it("reports a top level type mismatch plainly", function()
            expect(function()
                expect(1).toEqual("1")
            end).toThrow("top level")
        end)
    end)

    describe("toMatchObject failure diffs", function()
        it("reports the failing path", function()
            expect(function()
                expect({ a = { b = 1 } }).toMatchObject({ a = { b = 2 } })
            end).toThrow("at a%.b")
        end)

        it("still ignores extra fields in actual", function()
            expect({ a = 1, extra = true }).toMatchObject({ a = 1 })
        end)
    end)
end
