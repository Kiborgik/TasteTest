--[[
	spy.luau — minimal call-recording spy.

	Returns TWO values: a callable table and a plain function. Both share
	the same recorder. Use the function form when consuming code does
	`type(x) == "function"` type checks — callable tables fail those.

	Each captured call uses `table.pack(...)` to preserve trailing nils and
	the exact arity — `spy.calls[i].n` is the call's argument count, and
	`spy.calls[i][1..n]` are the values (nil-safe). Plain `{...}` would lose
	trailing nils because `#t` is undefined for tables with holes.

	Usage:
		local spy, spyFn = TasteTest.spy()
		spy("a", 1)
		expect(spy.calls[1].n).toBe(2)
		expect(spy.calls[1][1]).toBe("a")
		-- Or, if no nil args, deep-compare against an array literal:
		expect(spy.calls[1]).toEqual({ "a", 1, n = 2 })

	With implementation:
		local doubler, doublerFn = TasteTest.spy(function(x) return x * 2 end)
		expect(doublerFn(5)).toBe(10)
		expect(doubler.calls[1].n).toBe(1)
]]

local function spy(impl)
	local calls = {}
	local function record(...)
		table.insert(calls, table.pack(...))
		if impl then
			return impl(...)
		end
		return nil
	end
	local spyTable = setmetatable({ calls = calls }, {
		__call = function(_, ...)
			return record(...)
		end,
	})
	return spyTable, record
end

return spy
