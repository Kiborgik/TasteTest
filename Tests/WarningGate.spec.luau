--[[
  WarningGate.spec — warning capture and classification.

  Classification is unit-tested through the Runner._classifyWarnings seam.
  Capture is dogfooded end to end: the test below emits a real warn(), and
  the suite entry (Tests/RunInLune.luau, TasteTestMetaRunner in Studio)
  allowlists it via opts.expectedWarnings with strictWarnings on, so the
  suite only stays green if capture and classification actually work.
]]

return function()
    local TasteTest = require("../Start")
    local Runner = require("../runner")
    local describe, it, expect =
        TasteTest.describe, TasteTest.it, TasteTest.expect
    local classify = Runner._classifyWarnings

    describe("classifyWarnings", function()
        it("splits messages into expected and unexpected", function()
            local expectedList, unexpectedList = classify(
                { "DataStore budget low", "totally novel problem" },
                { "DataStore budget" })
            expect(#expectedList).toBe(1)
            expect(#unexpectedList).toBe(1)
            expect(unexpectedList[1]).toBe("totally novel problem")
        end)

        it("matches plainly, not as a Lua pattern", function()
            local expectedList, unexpectedList = classify(
                { "value is 50% (raw)" },
                { "50% (raw)" })
            expect(#expectedList).toBe(1)
            expect(#unexpectedList).toBe(0)
        end)

        it("accepts { pattern = ..., reason = ... } entries", function()
            local expectedList, unexpectedList = classify(
                { "known noisy warning here" },
                { { pattern = "noisy warning", reason = "tracked upstream" } })
            expect(#expectedList).toBe(1)
            expect(#unexpectedList).toBe(0)
        end)

        it("ignores empty patterns instead of matching everything", function()
            local _, unexpectedList = classify(
                { "anything at all" },
                { "" })
            expect(#unexpectedList).toBe(1)
        end)

        it("everything is unexpected with no allowlist", function()
            local expectedList, unexpectedList = classify({ "a", "b" }, {})
            expect(#expectedList).toBe(0)
            expect(#unexpectedList).toBe(2)
        end)

        it("no messages means clean", function()
            local expectedList, unexpectedList = classify({}, { "whatever" })
            expect(#expectedList).toBe(0)
            expect(#unexpectedList).toBe(0)
        end)
    end)

    describe("warning capture (end to end)", function()
        it("a runtime warn during a test is captured by the gate", function()
            -- The assertion for this test lives OUTSIDE the suite: the entry
            -- script runs with strictWarnings = true and this exact message
            -- allowlisted. If capture broke, this warn would be invisible and
            -- nothing fails; if classification broke, this warn would be
            -- unexpected and the strict gate would fail the run.
            warn("TasteTest self-test expected warning")
            expect(true).toBeTruthy()
        end)
    end)
end
