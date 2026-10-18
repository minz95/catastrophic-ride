--!nocheck
-- loader.luau
-- Mirrors Rojo's file→instance rules so game code can be required under Lune
-- exactly as it is in Studio (`game.ReplicatedStorage.Shared.Constants`,
-- `script.Parent.Constants`, ...).
--
--   foo.lua / foo.luau           → ModuleScript "foo"
--   foo.server.lua               → Script "foo"
--   foo.client.lua               → LocalScript "foo"
--   dir/init.lua                 → ModuleScript "dir" (children = dir contents)
--   dir/init.server.lua / .client→ Script / LocalScript "dir"
--   dir/init.meta.json           → className override
--   anything else                → Folder
--
-- Usage:
--   local Loader = require("./loader")
--   local env = Loader.boot()                  -- fresh mock DataModel
--   local Constants = env.require(env.game.ReplicatedStorage.Shared.Constants)

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")

local Mock = require("./mock")

local Loader = {}

local ROOT = "roblox"

-- Sources are read once, on the main thread. Lune's fs calls are async: a
-- read inside a mock-managed coroutine would yield that coroutine to Lune's
-- own scheduler, which can then resume it later in the middle of another boot.
local SOURCE_CACHE = {}
local function source(path)
	local s = SOURCE_CACHE[path]
	if not s then
		s = fs.readFile(path)
		SOURCE_CACHE[path] = s
	end
	return s
end
Loader.source = source

local function stripExt(name)
	for _, suffix in ipairs({ ".server.luau", ".server.lua", ".client.luau", ".client.lua", ".luau", ".lua" }) do
		if name:sub(-#suffix) == suffix then
			local kind = "ModuleScript"
			if suffix:find("server") then
				kind = "Script"
			elseif suffix:find("client") then
				kind = "LocalScript"
			end
			return name:sub(1, -#suffix - 1), kind
		end
	end
	return nil
end

local function mapDirectory(path, name, parent)
	-- Directory: look for init file / meta
	local initKind, initPath
	for _, candidate in ipairs({
		{ "init.server.luau", "Script" },
		{ "init.server.lua", "Script" },
		{ "init.client.luau", "LocalScript" },
		{ "init.client.lua", "LocalScript" },
		{ "init.luau", "ModuleScript" },
		{ "init.lua", "ModuleScript" },
	}) do
		if fs.isFile(path .. "/" .. candidate[1]) then
			initPath = path .. "/" .. candidate[1]
			initKind = candidate[2]
			break
		end
	end
	local className = initKind or "Folder"
	if fs.isFile(path .. "/init.meta.json") then
		local meta = serde.decode("json", fs.readFile(path .. "/init.meta.json"))
		className = meta.className or className
	end
	local inst = Mock.Instance.new(className)
	inst.Name = name
	if initPath then
		inst.SourcePath = initPath
		source(initPath)
	end
	inst.Parent = parent

	local entries = fs.readDir(path)
	table.sort(entries)
	for _, entry in ipairs(entries) do
		local full = path .. "/" .. entry
		if entry:match("^init%.") then
			continue
		end
		if fs.isDir(full) then
			mapDirectory(full, entry, inst)
		else
			local base, kind = stripExt(entry)
			if base then
				local child = Mock.Instance.new(kind)
				child.Name = base
				child.SourcePath = full
				source(full)
				child.Parent = inst
			end
		end
	end
	return inst
end

local function mapProjectNode(node, inst, baseDir)
	for key, child in pairs(node) do
		if key:sub(1, 1) == "$" then
			continue
		end
		local target = inst:FindFirstChild(key)
		if child["$path"] then
			local p = baseDir .. "/" .. child["$path"]
			if target then
				-- Merge directory contents into the existing service
				for _, entry in ipairs(fs.readDir(p)) do
					local full = p .. "/" .. entry
					if fs.isDir(full) then
						mapDirectory(full, entry, target)
					elseif not entry:match("^init%.") then
						local base, kind = stripExt(entry)
						if base then
							local s = Mock.Instance.new(kind)
							s.Name = base
							s.SourcePath = full
							source(full)
							s.Parent = target
						end
					end
				end
				if fs.isFile(p .. "/init.meta.json") then
					-- className already set by service
				end
			else
				mapDirectory(p, key, inst)
			end
		elseif target then
			mapProjectNode(child, target, baseDir)
		end
	end
end

--- Boots a fresh mock DataModel populated from roblox/default.project.json.
-- @returns env { game, workspace, require, run, mock }
function Loader.boot(opts)
	opts = opts or {}
	Mock.reset()
	Mock.quiet = opts.quiet ~= false
	local game = Mock.game

	local project = serde.decode("json", source(ROOT .. "/default.project.json"))
	mapProjectNode(project.tree, game, ROOT)

	local cache = {}
	local requireFn

	local function load(scriptInst, sourceOverride)
		local path = scriptInst.SourcePath
		local text = sourceOverride or source(path)
		local env = Mock.environment(scriptInst, requireFn)
		local chunk = luau.load(text, {
			debugName = path or scriptInst:GetFullName(),
			environment = env,
		})
		return chunk
	end

	requireFn = function(target)
		if type(target) == "string" then
			error("string require not supported in mock: " .. target)
		end
		if not Mock.isInstance(target) then
			error("require expected ModuleScript, got " .. typeof(target))
		end
		if cache[target] ~= nil then
			return cache[target].value
		end
		if not target.SourcePath and not target.Source then
			error("ModuleScript has no source: " .. target:GetFullName())
		end
		local chunk = load(target, target.Source)
		local value = chunk()
		cache[target] = { value = value }
		return value
	end

	local env = {
		game = game,
		workspace = Mock.workspace,
		mock = Mock,
		require = requireFn,
	}

	--- Runs a Script/LocalScript (or arbitrary source as if it were one).
	function env.run(scriptInst, sourceOverride)
		local chunk = load(scriptInst, sourceOverride)
		return chunk()
	end

	--- Resolves a dotted path like "ReplicatedStorage.Shared.Constants".
	function env.find(path)
		local node = game
		for segment in path:gmatch("[^%.]+") do
			node = node:FindFirstChild(segment)
			if not node then
				error("path not found: " .. path)
			end
		end
		return node
	end

	function env.requirePath(path)
		return requireFn(env.find(path))
	end

	return env
end

return Loader
