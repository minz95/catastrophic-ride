--!nocheck
-- server.luau
-- Boots the real server scripts inside the mock engine, with the virtual
-- clock, so whole phases (farming, crafting) can run in seconds.
--
--   local Server = require("./server")
--   local srv = Server.boot({ harness = { biome = "FOREST", players = 4, ... }, players = 4 })
--   srv.advance(10)   -- 10 virtual seconds

local serde = require("@lune/serde")
local Loader = require("./loader")
local Vector3 = require("@lune/roblox").Vector3

local Server = {}

-- Server scripts started in this order (GameBootstrap first, as in Studio the
-- module requires make the order mostly irrelevant). All three map builders
-- run, as in a live server; MapManager shows only the selected biome.
Server.DEFAULT_SCRIPTS = {
	"ServerScriptService.MapBuilders.ForestMapBuilder",
	"ServerScriptService.MapBuilders.OceanMapBuilder",
	"ServerScriptService.MapBuilders.SkyMapBuilder",
	"ServerScriptService.GameBootstrap",
	"ServerScriptService.MapManager",
	"ServerScriptService.ItemModelPreloader",
	"ServerScriptService.FarmingManager",
	"ServerScriptService.CraftingManager",
}

function Server.boot(opts)
	opts = opts or {}
	local env = Loader.boot({ quiet = opts.quiet })
	local Mock = env.mock
	Mock.swallowErrors = opts.swallowErrors

	local harness = opts.harness or { harness = "lune", autoStart = false }
	env.game.ServerScriptService:SetAttribute("HarnessArgs", serde.encode("json", harness))

	local srv = { env = env, mock = Mock, players = {} }

	-- Players must exist before SessionManager loads (it scans GetPlayers).
	for i = 1, opts.players or 0 do
		local p = Mock.addPlayer("Bot" .. i, 1000 + i, Vector3.new(i * 4, 3, 850))
		table.insert(srv.players, p)
	end

	-- e.g. set attributes the scripts read at start-up
	if opts.setup then opts.setup(env, Mock) end

	for _, path in ipairs(opts.scripts or Server.DEFAULT_SCRIPTS) do
		local ok, inst = pcall(env.find, path)
		if ok and inst then
			env.run(inst)
		end
	end

	srv.GameManager = env.requirePath("ServerScriptService.GameManager")
	srv.SessionManager = env.requirePath("ServerScriptService.SessionManager")
	srv.Telemetry = env.requirePath("ServerScriptService.Modules.Telemetry")
	srv.RemoteEvents = env.requirePath("ReplicatedStorage.RemoteEvents")

	function srv.advance(seconds, step, onStep)
		Mock.advance(seconds, step, onStep)
	end

	function srv.remote(name)
		return srv.RemoteEvents[name]
	end

	function srv.invoke(name, player, ...)
		return Mock.invoke(srv.RemoteEvents[name], player, ...)
	end

	return srv
end

return Server
