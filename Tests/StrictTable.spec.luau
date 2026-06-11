--[[
    StrictTable.spec — TasteTest meta-test for TasteTest.strictTable().
    Runs under the "TasteTestMeta" scenario.
]]

return function()
    local TasteTest = require("../Start")
    local describe, it, expect = TasteTest.describe, TasteTest.it, TasteTest.expect

    local KEYS = { coins = true, inventory = true, pickaxeLevel = true }
    local function makeFactory()
        return TasteTest.strictTable("TestFactory", KEYS, function(overrides)
            return {
                coins = overrides.coins or 100,
                inventory = overrides.inventory or {},
                pickaxeLevel = overrides.pickaxeLevel or 1,
            }
        end)
    end

    describe("TasteTest.strictTable factory", function()
        it("returns canonical defaults when called with no args", function()
            local make = makeFactory()
            local d = make()
            expect(d.coins).toBe(100)
            expect(d.pickaxeLevel).toBe(1)
        end)

        it("returns canonical defaults when called with nil", function()
            local make = makeFactory()
            local d = make(nil)
            expect(d.coins).toBe(100)
        end)

        it("applies overrides for known keys", function()
            local make = makeFactory()
            local d = make({ coins = 500 })
            expect(d.coins).toBe(500)
            expect(d.pickaxeLevel).toBe(1)
        end)

        it("errors at construction on unknown override key", function()
            local make = makeFactory()
            expect(function()
                make({ coiins = 500 })
            end).toThrow("coiins")
        end)

        it("error message includes the factory name", function()
            local make = makeFactory()
            expect(function()
                make({ wrong = 1 })
            end).toThrow("TestFactory")
        end)

        it("error message lists allowed keys", function()
            local make = makeFactory()
            expect(function()
                make({ wrong = 1 })
            end).toThrow("Allowed")
        end)

        it("errors when overrides arg is not a table", function()
            local make = makeFactory()
            expect(function()
                make(42)
            end).toThrow("overrides must be a table")
        end)
    end)

    describe("strict-mode __index", function()
        it("returns nil for canonical key with nil default", function()
            local M = TasteTest.strictTable("M", { x = true, y = true }, function(o)
                return { x = o.x }
            end)
            local d = M()
            expect(d.y).toBe(nil)
        end)

        it("errors on non-canonical key access", function()
            local make = makeFactory()
            local d = make()
            expect(function()
                local _ = d.totallyUnknown
            end).toThrow("totallyUnknown")
        end)

        it("error message identifies factory + suggests fix", function()
            local make = makeFactory()
            local d = make()
            expect(function()
                local _ = d.someBadKey
            end).toThrow("TestFactory")
        end)

        it("pairs() iterates raw keys without erroring", function()
            local make = makeFactory()
            local d = make()
            local found = {}
            for k, _ in pairs(d) do
                found[k] = true
            end
            expect(found.coins).toBe(true)
            expect(found.inventory).toBe(true)
            expect(found.pickaxeLevel).toBe(true)
        end)

        it("raw assignment bypasses the metatable (escape hatch)", function()
            local make = makeFactory()
            local d = make()
            d.testMarker = "ok"
            expect(d.testMarker).toBe("ok")
        end)
    end)
end
