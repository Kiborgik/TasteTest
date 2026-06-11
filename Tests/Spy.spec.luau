--[[
    Spy.spec — TasteTest meta-test for TasteTest.spy().
    Runs under the "TasteTestMeta" scenario.
]]

return function()
    local TasteTest = require("../Start")
    local describe, it, expect = TasteTest.describe, TasteTest.it, TasteTest.expect

    describe("TasteTest.spy()", function()
        it("returns two values: callable table + plain function", function()
            local spy, spyFn = TasteTest.spy()
            expect(type(spy)).toBe("table")
            expect(type(spyFn)).toBe("function")
        end)

        it("records calls via the callable-table form (with .n arity)", function()
            local spy = TasteTest.spy()
            spy("a", 1)
            spy("b", 2)
            expect(#spy.calls).toBe(2)
            expect(spy.calls[1].n).toBe(2)
            expect(spy.calls[1][1]).toBe("a")
            expect(spy.calls[1][2]).toBe(1)
            expect(spy.calls[2][1]).toBe("b")
            expect(spy.calls[2][2]).toBe(2)
        end)

        it("records calls via the plain-function form", function()
            local spy, spyFn = TasteTest.spy()
            spyFn("x")
            spyFn("y")
            expect(#spy.calls).toBe(2)
            expect(spy.calls[1][1]).toBe("x")
            expect(spy.calls[2][1]).toBe("y")
        end)

        it("shares recorder state between table and function forms", function()
            local spy, spyFn = TasteTest.spy()
            spy(1)
            spyFn(2)
            spy(3)
            expect(#spy.calls).toBe(3)
            expect(spy.calls[1][1]).toBe(1)
            expect(spy.calls[2][1]).toBe(2)
            expect(spy.calls[3][1]).toBe(3)
        end)

        it("returns nil from calls when no impl provided", function()
            local spy = TasteTest.spy()
            expect(spy("anything")).toBe(nil)
        end)

        it("forwards to impl and returns its value", function()
            local _, doublerFn = TasteTest.spy(function(x) return x * 2 end)
            expect(doublerFn(5)).toBe(10)
            expect(doublerFn(7)).toBe(14)
        end)

        it("records calls even when impl is provided", function()
            local doubler, doublerFn = TasteTest.spy(function(x) return x * 2 end)
            doublerFn(5)
            doubler(7)
            expect(#doubler.calls).toBe(2)
            expect(doubler.calls[1][1]).toBe(5)
            expect(doubler.calls[2][1]).toBe(7)
        end)

        it("impl can close over state for per-call return values", function()
            local i = 0
            local _, seqFn = TasteTest.spy(function()
                i = i + 1
                return ({ "a", "b", "c" })[i]
            end)
            expect(seqFn()).toBe("a")
            expect(seqFn()).toBe("b")
            expect(seqFn()).toBe("c")
        end)

        it("calls table is empty initially", function()
            local spy = TasteTest.spy()
            expect(#spy.calls).toBe(0)
        end)

        it("records calls with zero arguments (.n == 0)", function()
            local spy = TasteTest.spy()
            spy()
            expect(#spy.calls).toBe(1)
            expect(spy.calls[1].n).toBe(0)
        end)

        it("preserves trailing-nil arguments (.n captures real arity)", function()
            local spy = TasteTest.spy()
            spy("a", nil, "c")           -- 3 args, middle is nil
            spy("a", "b", nil)           -- 3 args, trailing is nil
            spy(nil, nil, nil)           -- 3 args, all nil
            expect(spy.calls[1].n).toBe(3)
            expect(spy.calls[1][1]).toBe("a")
            expect(spy.calls[1][2]).toBe(nil)
            expect(spy.calls[1][3]).toBe("c")
            expect(spy.calls[2].n).toBe(3)
            expect(spy.calls[2][3]).toBe(nil)
            expect(spy.calls[3].n).toBe(3)
        end)
    end)
end
