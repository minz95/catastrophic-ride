-- SoundFx.lua
-- Client-side sound player shared by SoundClient, RacingClient and the
-- crafting screen (one cache per client). Ids and volumes: Shared/SoundConfig.
-- `pitch` is the playback speed (1 = as recorded).

local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local SoundConfig = require(script.Parent.SoundConfig)

local SoundFx = {}

local _cache = {}   -- key → Sound

--- A 2D Sound for a SoundConfig entry, or nil when it has no id.
function SoundFx.make(cfg, parent)
	if not cfg or not cfg.id or cfg.id == "" then return nil end
	local s = Instance.new("Sound")
	s.SoundId = cfg.id
	s.Volume = cfg.volume or 0.5
	s.Looped = cfg.looped or false
	s.PlaybackSpeed = cfg.pitch or 1
	s.RollOffMaxDistance = 0
	s.Parent = parent or SoundService
	return s
end

--- Plays SoundConfig.SFX[key] once (overlapping plays get a clone).
function SoundFx.play(key)
	local cfg = SoundConfig.SFX[key]
	if not cfg then return end
	local s = _cache[key]
	if not s or not s.Parent then
		s = SoundFx.make(cfg, SoundService)
		_cache[key] = s
	end
	if not s then return end
	if s.IsPlaying then
		local clone = s:Clone()
		clone.Parent = SoundService
		clone:Play()
		Debris:AddItem(clone, 5)
	else
		s:Play()
	end
end

return SoundFx
