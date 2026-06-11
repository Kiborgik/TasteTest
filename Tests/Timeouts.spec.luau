--[[
  Timeouts.spec — yield-safe test execution and per-test timeouts.

  The watchdog unit (Runner._runTestFn) is tested with a fake wait function
  and tests that register their own coroutine handle, so the timeout and
  resume paths run deterministically with no real waiting in any runtime.
  One real-scheduler test runs only where a global task library exists
  (Roblox); under Lune it is skipped.
]]

return function()
    local TasteTest = require("../Start")
    local Runner = require("../runner")
    local describe, it, expect =
        TasteTest.describe, TasteTest.it, TasteTest.expect
    local runTestFn = Runner._runTestFn

    describe("runTestFn yield safety", function()
        it("passes a synchronous test", function()
            local ok, err = runTestFn(function() end, 1, nil)
            expect(ok).toBe(true)
            expect(err).toBe(nil)
        end)

        it("captures a synchronous error", function()
            local ok, err = runTestFn(function()
                error("sync boom")
            end, 1, nil)
            expect(ok).toBe(false)
            expect(tostring(err):find("sync boom") ~= nil).toBe(true)
        end)

        it("resumes a yielding test to completion", function()
            local resume = nil
            local ran = false
            local ok, err = runTestFn(function()
                local thread = coroutine.running()
                resume = function() coroutine.resume(thread) end
                coroutine.yield()
                ran = true
            end, 5, function(step)
                if resume then
                    local r = resume
                    resume = nil
                    r()
                end
                return step
            end)
            expect(ok).toBe(true)
            expect(err).toBe(nil)
            expect(ran).toBe(true)
        end)

        it("captures an error thrown after a yield", function()
            local resume = nil
            local ok, err = runTestFn(function()
                local thread = coroutine.running()
                resume = function() coroutine.resume(thread) end
                coroutine.yield()
                error("boom after yield")
            end, 5, function(step)
                if resume then
                    local r = resume
                    resume = nil
                    r()
                end
                return step
            end)
            expect(ok).toBe(false)
            expect(tostring(err):find("boom after yield") ~= nil).toBe(true)
        end)

        it("times out a test that never finishes", function()
            local ok, err = runTestFn(function()
                coroutine.yield()
            end, 0.2, function(step)
                return step
            end)
            expect(ok).toBe(false)
            expect(tostring(err):find("timed out after") ~= nil).toBe(true)
        end)

        it("fails a yielding test when no scheduler is available", function()
            local ok, err = runTestFn(function()
                coroutine.yield()
            end, 1, nil)
            expect(ok).toBe(false)
            expect(tostring(err):find("no scheduler") ~= nil).toBe(true)
        end)
    end)

    describe("afterEach always runs (via the _runTestWithHooks seam)", function()
        local runTestWithHooks = Runner._runTestWithHooks

        it("runs afterEach after a failing test body and keeps the body error", function()
            local cleaned = false
            local ok, err = runTestWithHooks(
                {},
                function() error("body boom") end,
                { function() cleaned = true end },
                1, nil)
            expect(ok).toBe(false)
            expect(cleaned).toBe(true)
            expect(tostring(err):find("body boom") ~= nil).toBe(true)
        end)

        it("fails a passing test when afterEach throws", function()
            local ok, err = runTestWithHooks(
                {},
                function() end,
                { function() error("cleanup boom") end },
                1, nil)
            expect(ok).toBe(false)
            expect(tostring(err):find("afterEach failed") ~= nil).toBe(true)
            expect(tostring(err):find("cleanup boom") ~= nil).toBe(true)
        end)

        it("reports body error first when both body and afterEach fail", function()
            local ok, err = runTestWithHooks(
                {},
                function() error("body boom") end,
                { function() error("cleanup boom") end },
                1, nil)
            expect(ok).toBe(false)
            local msg = tostring(err)
            local bodyPos = msg:find("body boom")
            local cleanupPos = msg:find("cleanup boom")
            expect(bodyPos ~= nil).toBe(true)
            expect(cleanupPos ~= nil).toBe(true)
            expect(bodyPos < cleanupPos).toBe(true)
        end)

        it("one failing afterEach does not skip its siblings", function()
            local secondRan = false
            local ok = runTestWithHooks(
                {},
                function() end,
                {
                    function() error("first cleanup boom") end,
                    function() secondRan = true end,
                },
                1, nil)
            expect(ok).toBe(false)
            expect(secondRan).toBe(true)
        end)

        it("passes cleanly when body and hooks all succeed", function()
            local order = {}
            local ok, err = runTestWithHooks(
                { function() table.insert(order, "before") end },
                function() table.insert(order, "body") end,
                { function() table.insert(order, "after") end },
                1, nil)
            expect(ok).toBe(true)
            expect(err).toBe(nil)
            expect(order[1]).toBe("before")
            expect(order[2]).toBe("body")
            expect(order[3]).toBe("after")
        end)

        it("a failing beforeEach still triggers afterEach", function()
            local cleaned = false
            local ok, err = runTestWithHooks(
                { function() error("before boom") end },
                function() end,
                { function() cleaned = true end },
                1, nil)
            expect(ok).toBe(false)
            expect(cleaned).toBe(true)
            expect(tostring(err):find("before boom") ~= nil).toBe(true)
        end)
    end)

    describe("timeout plumbing through it()", function()
        local hasTask = type(task) == "table" and type(task.wait) == "function"
        local maybeIt = hasTask and it or it.skip

        maybeIt("a test that really yields on the scheduler passes", function()
            task.wait(0.05)
            expect(true).toBeTruthy()
        end, { timeout = 5 })
    end)
end
