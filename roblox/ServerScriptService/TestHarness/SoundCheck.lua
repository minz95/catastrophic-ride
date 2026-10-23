-- SoundCheck.lua
-- Studio harness for audio (edit mode, no session): every id in
-- Shared/SoundConfig is loaded as a real Sound (permission and length), and
-- opts.search runs AssetService:SearchAudio so new ids come from the Creator
-- Store instead of guesses. Runner.runSounds / tools/studio/sim.py "sounds".

local AssetService = game:GetService("AssetService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundCheck = {}

local function idOf(v)
	if type(v) ~= "string" or v == "" then return nil end
	return v:match("%d+")
end

--- { [path] = id string or "" } for every sound entry in SoundConfig.
function SoundCheck.entries(cfg)
	local out = {}
	local function walk(prefix, t)
		if type(t) ~= "table" then return end
		if t.id ~= nil then out[prefix] = t.id; return end
		for k, v in pairs(t) do walk(prefix == "" and tostring(k) or (prefix .. "." .. tostring(k)), v) end
	end
	walk("", { BGM = cfg.BGM, AMBIENCE = cfg.AMBIENCE, SFX = cfg.SFX })
	return out
end

--- Loads one asset id as a Sound: { ok, length, status }.
function SoundCheck.load(id)
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Parent = workspace
	local status = "?"
	pcall(function()
		ContentProvider:PreloadAsync({ s }, function(_, st) status = st.Name end)
	end)
	local t0 = os.clock()
	while not s.IsLoaded and os.clock() - t0 < 6 do task.wait(0.1) end
	local res = { ok = s.IsLoaded and s.TimeLength > 0, length = math.floor(s.TimeLength * 10) / 10, status = status }
	s:Destroy()
	return res
end

local function search(q)
	local params = Instance.new("AudioSearchParams")
	params.SearchKeyword = q.keyword or ""
	if q.music ~= nil then params.AudioSubType = q.music and Enum.AudioSubType.Music or Enum.AudioSubType.SoundEffect end
	if q.minDur then params.MinDuration = q.minDur end
	if q.maxDur then params.MaxDuration = q.maxDur end
	local found = {}
	local ok, err = pcall(function()
		-- q.creators: keep only these uploaders (licensed catalogues)
		local allow = nil
		if q.creators then
			allow = {}
			for _, c in ipairs(q.creators) do allow[c] = true end
		end
		local pages = AssetService:SearchAudio(params)
		for _ = 1, q.pages or 1 do
			for _, a in ipairs(pages:GetCurrentPage()) do
				if #found >= (q.limit or 6) then break end
				local creator = a.CreatorName or (a.Creator and a.Creator.Name)
				if not allow or allow[creator] then
					table.insert(found, { id = tostring(a.Id), title = a.Title, artist = a.Artist, creator = creator, duration = a.Duration })
				end
			end
			if #found >= (q.limit or 6) or pages.IsFinished then break end
			pages:AdvanceToNextPageAsync()
		end
	end)
	if not ok then return { error = tostring(err) } end
	for _, f in ipairs(found) do
		local l = SoundCheck.load(f.id)
		f.ok, f.length = l.ok, l.length
	end
	return found
end

--- opts: { search = { { key = "BGM.RACING.FOREST", keyword = "...", music = true, minDur, maxDur, limit }, ... } }
function SoundCheck.run(opts)
	opts = opts or {}
	local cfg = require(ReplicatedStorage.Shared.SoundConfig)
	local report = { kind = "sounds", configured = {}, searches = {} }
	local tried = {}
	for path, raw in pairs(SoundCheck.entries(cfg)) do
		local id = idOf(raw)
		if not id then
			report.configured[path] = { id = "", ok = false, status = "empty" }
		else
			tried[id] = tried[id] or SoundCheck.load(id)
			local l = tried[id]
			report.configured[path] = { id = id, ok = l.ok, length = l.length, status = l.status }
		end
	end
	for _, q in ipairs(opts.search or {}) do
		report.searches[q.key or q.keyword] = search(q)
	end
	return report
end

function SoundCheck.summarize(report)
	local bad, good, keys = 0, 0, {}
	for k in pairs(report.configured) do table.insert(keys, k) end
	table.sort(keys)
	local lines = {}
	for _, k in ipairs(keys) do
		local c = report.configured[k]
		if c.ok then good += 1 else bad += 1; table.insert(lines, "  missing " .. k .. " (" .. (c.id ~= "" and c.id or "empty") .. ", " .. tostring(c.status) .. ")") end
	end
	table.insert(lines, 1, string.format("SoundCheck: %d sounds load, %d missing", good, bad))
	return table.concat(lines, "\n")
end

return SoundCheck
