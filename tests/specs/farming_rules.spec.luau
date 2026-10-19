--!nocheck
-- Shared/FarmingRules over many generated cases (the FARMING decisions as
-- pure functions; FarmingManager only does the I/O).
local R = require("../lib/runner")
local Loader = require("../lib/loader")

local env = Loader.boot()
local Rules = env.requirePath("ReplicatedStorage.Shared.FarmingRules")
local ItemConfig = env.requirePath("ServerScriptService.Modules.ItemConfig")
local Constants = env.requirePath("ReplicatedStorage.Shared.Constants")

local names = {}
for name, cfg in pairs(ItemConfig) do
	if type(cfg) == "table" and cfg.rarity then table.insert(names, name) end
end
table.sort(names)
local function rank(n) return Rules.RARITY_RANK[ItemConfig[n].rarity] end

-- deterministic LCG
local state = 12345
local function rnd(n)
	state = (state * 1103515245 + 12345) % 2147483648
	return (state % n) + 1
end

R.describe("FarmingRules.pickupSlot (500 random inventories)", function()
	R.it("adds while there is room, swaps only for a strictly rarer item, never exceeds the size", function()
		local bad = {}
		local size = Constants.INVENTORY_SIZE
		for _ = 1, 500 do
			local inv = {}
			for i = 1, rnd(size + 1) - 1 do inv[i] = names[rnd(#names)] end
			local new = names[rnd(#names)]
			local action, idx = Rules.pickupSlot(inv, new, ItemConfig, size)
			local weakest = math.huge
			for _, n in ipairs(inv) do weakest = math.min(weakest, rank(n)) end
			if #inv < size and action ~= "add" then table.insert(bad, "room but " .. action) end
			if #inv >= size then
				if rank(new) > weakest then
					if action ~= "swap" or rank(inv[idx]) ~= weakest then
						table.insert(bad, string.format("rarer %s should replace a rank-%d item", new, weakest))
					end
				elseif action ~= "full" then
					table.insert(bad, string.format("%s is not rarer than rank %d but got %s", new, weakest, action))
				end
			end
		end
		R.expect(bad).toBeEmpty("wrong pickup decisions")
	end)
end)

R.describe("FarmingRules.contestWinner", function()
	R.it("more presses win; a tie goes to the player who arrived first", function()
		for a = 0, 30 do
			for b = 0, 30 do
				local want = a >= b and 1 or 2
				R.expect(Rules.contestWinner(a, b)).toBe(want)
			end
		end
		R.expect(Rules.contestWinner(nil, nil)).toBe(1)
	end)
end)

R.describe("FarmingRules.canSteal", function()
	local base = {
		now = 100, thiefCooldownEnd = 0, farmingTimeLeft = 60, disableBefore = Constants.STEAL_DISABLE_BEFORE,
		thiefItems = 2, victimItems = 3, inventorySize = Constants.INVENTORY_SIZE,
		distance = 2, range = Constants.STEAL_RANGE, victimInvincibleEnd = 0,
	}
	local function with(t)
		local s = table.clone(base)
		for k, v in pairs(t) do s[k] = v end
		return s
	end
	R.it("allows a plain steal", function()
		R.expect((Rules.canSteal(base))).toBe(true)
	end)
	R.it("refuses for every single blocking reason", function()
		local cases = {
			{ { thiefCooldownEnd = 101 }, "cooldown" },
			{ { farmingTimeLeft = base.disableBefore - 0.1 }, "too late" },
			{ { victimItems = 0 }, "victim has nothing" },
			{ { thiefItems = base.inventorySize }, "thief is full" },
			{ { distance = base.range + 0.1 }, "too far" },
			{ { victimInvincibleEnd = 101 }, "victim protected" },
			{ { thiefBusy = true }, "already stealing" },
			{ { victimUnderAttack = true }, "victim under attack" },
			{ { self = true }, "self" },
		}
		for _, c in ipairs(cases) do
			local ok, why = Rules.canSteal(with(c[1]))
			R.expect(ok).toBe(false)
			R.expect(why).toBe(c[2])
		end
	end)
end)

R.describe("FarmingRules.stealOutcome", function()
	-- A steal is blocked only by enough taps inside the defence window
	-- (it used to be blocked by one DefendSteal call made at any time).
	R.it("needs STEAL_DEFEND_PRESSES taps in the window", function()
		local need = Constants.STEAL_DEFEND_PRESSES
		R.expect(Rules.stealOutcome(need, need)).toBe("defended")
		R.expect(Rules.stealOutcome(need + 4, need)).toBe("defended")
		R.expect(Rules.stealOutcome(need - 1, need)).toBe("stolen")
		R.expect(Rules.stealOutcome(0, need)).toBe("stolen")
		R.expect(Rules.stealOutcome(nil, need)).toBe("stolen")
	end)
end)
