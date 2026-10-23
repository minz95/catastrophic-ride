-- Analytics.lua
-- Thin wrapper over Roblox AnalyticsService (Creator Dashboard → Analytics).
-- Retention (D1 / D7 / D30), sessions and playtime come from the dashboard
-- itself; these events say WHERE players drop off and what they earn:
--   onboarding funnel  first session: joined → first pickup → car built →
--                      raced → finished → reward
--   "Round" funnel     every round: farming → crafting → car built → racing
--                      → finished → results
--   economy            coins earned (source) / spent (sink)
--   progression        level reached
--   custom             "ReturnDay" (days since the first round, on the first
--                      round of each day), "RoundPlace"
-- Off in Studio and harness sessions. Tests set Analytics.sink to record
-- the calls. Every call is pcall'ed: analytics never breaks the game.

local AnalyticsService = game:GetService("AnalyticsService")

local Analytics = {}

Analytics.enabled = false
Analytics.sink = nil   -- tests: function(method, args) end

local function enum(group, name)
	local ok, v = pcall(function() return Enum[group][name] end)
	return ok and v or name
end

local function call(method, ...)
	if Analytics.sink then
		Analytics.sink(method, table.pack(...))
		return
	end
	if not Analytics.enabled then return end
	local args = table.pack(...)
	local ok, err = pcall(function()
		AnalyticsService[method](AnalyticsService, table.unpack(args, 1, args.n))
	end)
	if not ok then warn("[Analytics] " .. method .. ": " .. tostring(err)) end
end

function Analytics.onboarding(player, step, stepName)
	call("LogOnboardingFunnelStepEvent", player, step, stepName)
end

function Analytics.funnelStep(player, funnel, sessionId, step, stepName)
	call("LogFunnelStepEvent", player, funnel, sessionId, step, stepName)
end

function Analytics.earn(player, currency, amount, balance, transaction)
	if amount <= 0 then return end
	call("LogEconomyEvent", player, enum("AnalyticsEconomyFlowType", "Source"), currency, amount, balance,
		transaction or "Gameplay")
end

function Analytics.spend(player, currency, amount, balance, itemSku)
	if amount <= 0 then return end
	call("LogEconomyEvent", player, enum("AnalyticsEconomyFlowType", "Sink"), currency, amount, balance,
		"Shop", itemSku)
end

function Analytics.levelReached(player, level)
	call("LogProgressionCompleteEvent", player, "Level", level, "Level " .. level)
end

function Analytics.custom(player, name, value)
	call("LogCustomEvent", player, name, value)
end

return Analytics
