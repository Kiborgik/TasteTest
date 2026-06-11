--[[
	strictTable.luau — factory helper that produces tables with strict-mode
	__index. Reading a non-canonical key errors with a drift message. Catches
	test drift at the access line, not as confusing nils downstream.

	Lifted from Fixtures.luau's strictWrap pattern, plus adds construction-time
	validation of override keys.

	Usage:
		local makePlayerData = TasteTest.strictTable("Fixtures.playerData", {
			coins = true, inventory = true, pickaxeLevel = true,
		}, function(overrides)
			return {
				coins = overrides.coins or 100,
				inventory = overrides.inventory or {},
				pickaxeLevel = overrides.pickaxeLevel or 1,
			}
		end)

		local d = makePlayerData({ coins = 500 })
		print(d.coins)         -- 500
		print(d.unknown)       -- ERROR: drift message

		makePlayerData({ coiins = 500 })  -- ERROR at construction
]]

local function strictTable(name, canonicalKeys, factory)
	return function(overrides)
		if overrides == nil then
			overrides = {}
		elseif type(overrides) ~= "table" then
			error(string.format(
				"%s: overrides must be a table or nil, got %s",
				name, type(overrides)
			), 2)
		end

		-- Validate override keys against the canonical set.
		for k in pairs(overrides) do
			if not canonicalKeys[k] then
				local allowed = {}
				for canonical in pairs(canonicalKeys) do
					table.insert(allowed, canonical)
				end
				table.sort(allowed)
				error(string.format(
					"%s unknown override key '%s'. Allowed: %s",
					name, tostring(k), table.concat(allowed, ", ")
				), 2)
			end
		end

		local data = factory(overrides)
		return setmetatable(data, {
			__metatable = false, -- prevent metatable replacement by accident
			__index = function(_, k)
				if type(k) ~= "string" then return nil end
				if canonicalKeys[k] then return nil end
				error(
					(
						"%s accessed field '%s' that the factory doesn't declare.\n"
						.. "  Either:\n"
						.. "    (a) production code added a new read of '%s' — update %s's canonical key set, OR\n"
						.. "    (b) this is a typo in the test or predicate."
					):format(name, k, k, name),
					2
				)
			end,
		})
	end
end

return strictTable
