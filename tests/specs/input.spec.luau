--!nocheck
-- Phones and tablets: on-screen buttons press keys through Shared/KeyInput,
-- the same path as the keyboard (FarmingClient, RacingClient).
local fs = require("@lune/fs")
local R = require("../lib/runner")
local Loader = require("../lib/loader")
local roblox = require("@lune/roblox")
local Enum = roblox.Enum

R.describe("KeyInput (keyboard + touch buttons)", function()
	R.it("a button press reaches every began handler with its KeyCode, a release every ended handler", function()
		local env = Loader.boot()
		local KeyInput = env.requirePath("ReplicatedStorage.Shared.KeyInput")
		local got = {}
		KeyInput.began(function(input, processed) table.insert(got, "began " .. input.KeyCode.Name .. tostring(processed)) end)
		local c = KeyInput.began(function(input) table.insert(got, "second " .. input.KeyCode.Name) end)
		KeyInput.ended(function(input) table.insert(got, "ended " .. input.KeyCode.Name) end)
		KeyInput.press(Enum.KeyCode.E)
		KeyInput.release(Enum.KeyCode.E)
		env.mock.advance(0.1)
		c:Disconnect()
		KeyInput.press(Enum.KeyCode.F)
		env.mock.advance(0.1)
		table.sort(got)
		R.expect(table.concat(got, ", ")).toBe("began Efalse, began Ffalse, ended E, second E")
	end)

	R.it("a gamepad button arrives as the key it stands for", function()
		local env = Loader.boot()
		local KeyInput = env.requirePath("ReplicatedStorage.Shared.KeyInput")
		local got
		KeyInput.began(function(input) got = input.KeyCode end)
		local uis = env.game:GetService("UserInputService")
		uis.InputBegan:Fire({ KeyCode = Enum.KeyCode.ButtonX, UserInputType = Enum.UserInputType.Gamepad1 }, false)
		env.mock.advance(0.1)
		R.expect(got).toBe(Enum.KeyCode.E)
	end)

	R.it("gameplay clients take keys only through KeyInput (so touch buttons work everywhere)", function()
		local bad = {}
		for _, f in ipairs({
			"roblox/StarterPlayer/StarterPlayerScripts/FarmingClient.client.lua",
			"roblox/StarterPlayer/StarterPlayerScripts/RacingClient.client.lua",
		}) do
			local src = fs.readFile(f)
			if src:find("UserInputService.InputBegan", 1, true) or src:find("UserInputService.InputEnded", 1, true) then
				table.insert(bad, f)
			end
		end
		R.expect(bad).toBeEmpty("clients reading the keyboard directly")
	end)

	R.it("every touch button's key is one the clients handle", function()
		local src = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/TouchControls.client.lua")
		local farming = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/FarmingClient.client.lua")
		local racing = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/RacingClient.client.lua")
		local missing = {}
		local section = nil
		for line in src:gmatch("[^\n]+") do
			if line:find("FARMING = {", 1, true) then section = farming end
			if line:find("RACING = {", 1, true) then section = racing end
			local key = line:match("key = Enum%.KeyCode%.(%w+)")
			if key and section and not section:find("KeyCode." .. key, 1, true) then
				table.insert(missing, key)
			end
		end
		R.expect(missing).toBeEmpty("buttons whose key nothing handles")
	end)
end)
