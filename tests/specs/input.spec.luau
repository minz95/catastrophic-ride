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
		local src = fs.readFile("roblox/ReplicatedStorage/Shared/TouchLayout.lua")
		local farming = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/FarmingClient.client.lua")
		-- FARMING's EMOTE (Q) opens EmoteUI's menu
		local farming = farming .. fs.readFile("roblox/StarterGui/EmoteUI/init.client.lua")
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

-- Launch audit (2026-10-30): phones and gamepads read "Press E", the touch
-- buttons ran off a 390-px phone screen, every respawn re-ran each client's
-- phase entry (music restarted, inventory bar emptied, the race gauge reset).
R.describe("controls named for the device (Shared/InputHints)", function()
	R.it("each action is its key on a keyboard, its pad button on a gamepad, its button on a phone", function()
		local env = Loader.boot()
		local H = env.requirePath("ReplicatedStorage.Shared.InputHints")
		R.expect(H.key("grab", "keyboard")).toBe("E")
		R.expect(H.key("grab", "gamepad")).toBe("X")
		R.expect(H.key("grab", "touch")).toBe("GRAB")
		R.expect(H.hold("steal", "touch")).toBe("[Hold GRAB]")
		R.expect(H.tag("boost", "gamepad")).toBe("[B]")
		R.expect(H.key("climb", "gamepad")).toBe("A")
	end)

	R.it("every touch name is a TouchControls button that presses that action's key", function()
		local env = Loader.boot()
		local H = env.requirePath("ReplicatedStorage.Shared.InputHints")
		local src = fs.readFile("roblox/ReplicatedStorage/Shared/TouchLayout.lua")
		local buttons = {}
		for text, key in src:gmatch('text = "([^"]+)",%s*key = Enum%.KeyCode%.(%w+)') do buttons[text] = key end
		local bad = {}
		for action, a in pairs(H.ACTIONS) do
			-- their own screen buttons; drop is a double tap on a bag slot
			-- (FarmingUI), emote the 😀 icon (TouchControls)
			local onScreen = action == "shop" or action == "guide" or action == "help"
				or action == "drop" or action == "emote"
			if not onScreen and buttons[a.touch] ~= a.code then
				table.insert(bad, action .. " → " .. tostring(a.touch))
			end
		end
		table.sort(bad)
		R.expect(bad).toBeEmpty("touch names with no button for their key")
	end)

	R.it("the gamepad map gives SKY climb / dive and the emote / taunt key, each button once", function()
		local env = Loader.boot()
		local KeyInput = env.requirePath("ReplicatedStorage.Shared.KeyInput")
		local seen = {}
		for button, kc in pairs(KeyInput.GAMEPAD) do seen[kc.Name] = button end
		R.expect(seen.Space ~= nil and seen.LeftControl ~= nil and seen.Q ~= nil).toBe(true)
	end)

	R.it("no keyboard-only control text in what a phone or gamepad player sees", function()
		local bad = {}
		local checks = {
			["roblox/StarterPlayer/StarterPlayerScripts/FarmFx.client.lua"] = { "Mash E or punch (F)" },
			["roblox/StarterPlayer/StarterPlayerScripts/FarmingClient.client.lua"] = { '"[E] Pick Up"', '"[Hold E] Steal' },
			["roblox/StarterPlayer/StarterPlayerScripts/RacingClient.client.lua"] = { '"BOOST  [F]"' },
			["roblox/StarterGui/FarmingUI/init.client.lua"] = { '"[E] Pick up' },
			["roblox/StarterGui/HUD/init.client.lua"] = { '"[ SHIFT = Drift', '"[E]"' },
			["roblox/StarterGui/ItemGuideUI/init.client.lua"] = { "press E in the race", '"E: "' },
			["roblox/StarterGui/TutorialUI/init.client.lua"] = { 'hintBtn.Text             = "[ H ] Controls"', '"Click & drag"' },
		}
		for f, needles in pairs(checks) do
			local src = fs.readFile(f)
			for _, n in ipairs(needles) do
				if src:find(n, 1, true) then table.insert(bad, f .. ": " .. n) end
			end
		end
		table.sort(bad)
		R.expect(bad).toBeEmpty("keyboard-only text")
	end)
end)

R.describe("driving with a stick (Studio Device Simulator, iPhone XR, 2026-10-30)", function()
	R.it("the race reads Roblox's control module move vector: the seat's ThrottleFloat stayed 0 and the car stood still", function()
		local rc = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/RacingClient.client.lua")
		R.expect(rc:find(":GetMoveVector()", 1, true) ~= nil).toBe(true)
		R.expect(rc:find("th, st = -mv.Z, mv.X", 1, true) ~= nil).toBe(true)
	end)
	R.it("gamepad triggers are gas and brake through KeyInput", function()
		local env = Loader.boot()
		local KeyInput = env.requirePath("ReplicatedStorage.Shared.KeyInput")
		R.expect(KeyInput.GAMEPAD.ButtonR2.Name).toBe("Up")
		R.expect(KeyInput.GAMEPAD.ButtonL2.Name).toBe("Down")
	end)
	R.it("screens lay out for thumbs on a touch screen in use, not only on a touch-only device", function()
		local env = Loader.boot()
		local H = env.requirePath("ReplicatedStorage.Shared.InputHints")
		R.expect(type(H.touchUI)).toBe("function")
		local side = fs.readFile("roblox/ReplicatedStorage/Shared/SideButtons.lua")
		R.expect(side:find("InputHints.touchUI()", 1, true) ~= nil).toBe(true)
	end)
end)

R.describe("race on a phone (Studio Device Simulator, 2026-10-30)", function()
	R.it("reset and taunt are icons at the top left, not buttons over the road", function()
		local env = Loader.boot()
		local T = env.requirePath("ReplicatedStorage.Shared.TouchLayout")
		local keys = {}
		for _, b in ipairs(T.LAYOUT.RACING) do keys[b.key.Name] = true end
		R.expect(keys.R).toBe(nil)
		R.expect(keys.Q).toBe(nil)
		local icons = {}
		for _, b in ipairs(T.ICONS.RACING) do icons[b.key.Name] = true end
		R.expect(icons.R and icons.Q).toBe(true)
		R.expect(T.ICONS.RESULTS).toBe(nil)   -- it lay on the reward box
	end)
	R.it("keys are let go when the window loses focus (Cmd+Tab left SKY's dive held)", function()
		local rc = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/RacingClient.client.lua")
		R.expect(rc:find("WindowFocusReleased:Connect(_releaseAllKeys)", 1, true) ~= nil).toBe(true)
		R.expect(rc:find("if _cpFrame then _cpFrame.Visible = false end", 1, true) ~= nil).toBe(true)
	end)
	R.it("race seats hide Roblox's own speed bar", function()
		local vb = fs.readFile("roblox/ServerScriptService/Modules/VehicleBuilder.lua")
		R.expect(vb:find("seat.HeadsUpDisplay = false", 1, true) ~= nil).toBe(true)
	end)
	R.it("no key list on a touch screen (it is for keyboards)", function()
		local tut = fs.readFile("roblox/StarterGui/TutorialUI/init.client.lua")
		R.expect(tut:find("return UserInputService.TouchEnabled or", 1, true) ~= nil).toBe(true)
	end)
end)

R.describe("touch buttons", function()
	local src = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/TouchControls.client.lua")
	R.it("are laid out from the viewport (they ran off a 390-px phone screen)", function()
		R.expect(src:find("ViewportSize", 1, true) ~= nil).toBe(true)
		R.expect(src:find("PositionTracker", 1, true) ~= nil).toBe(true)   -- not over the race position list
		R.expect(src:find('WaitForChild("PlayerGui")', 1, true) ~= nil).toBe(true)
	end)
	R.it("let go of every held key on a touch's end, a cancel or a phase change (GUARD / DRIFT stayed held)", function()
		R.expect(src:find("UserInputState.Cancel", 1, true) ~= nil).toBe(true)
		R.expect(src:find("if phase ~= _phase then releaseAll() end", 1, true) ~= nil).toBe(true)
	end)
	R.it("the emote menu opens from KeyInput (touch EMOTE button, gamepad), not the keyboard alone", function()
		local emote = fs.readFile("roblox/StarterGui/EmoteUI/init.client.lua")
		R.expect(emote:find("UserInputService.InputBegan", 1, true)).toBe(nil)
		R.expect(emote:find("KeyInput.began", 1, true) ~= nil).toBe(true)
	end)
end)

R.describe("client start-up and respawns", function()
	R.it("a client never makes its own RemoteEvents (a local copy no server listens to)", function()
		local src = fs.readFile("roblox/ReplicatedStorage/RemoteEvents/init.lua")
		local clientPart = src:match("if IS_CLIENT then(.-)\nend\n")
		R.expect(clientPart ~= nil).toBe(true)
		R.expect(clientPart:find("Instance.new", 1, true)).toBe(nil)
		R.expect(clientPart:find("WaitForChild", 1, true) ~= nil).toBe(true)
	end)

	R.it("phase entry runs once per phase: the respawn resend of the same phase is skipped", function()
		local bad = {}
		for _, f in ipairs({
			"roblox/StarterPlayer/StarterPlayerScripts/RacingClient.client.lua",
			"roblox/StarterPlayer/StarterPlayerScripts/SoundClient.client.lua",
			"roblox/StarterPlayer/StarterPlayerScripts/EffectFx.client.lua",
			"roblox/StarterGui/FarmingUI/init.client.lua",
			"roblox/StarterGui/CraftingUI/init.client.lua",
			"roblox/StarterGui/TutorialUI/init.client.lua",
			"roblox/StarterGui/HUD/init.client.lua",
		}) do
			if not fs.readFile(f):find("if phase == _lastPhase then return end", 1, true) then table.insert(bad, f) end
		end
		R.expect(bad).toBeEmpty("clients that enter a phase again on every respawn")
	end)

	R.it("a respawn resends the bag, and the crafting screen joins a running CRAFTING with its draft", function()
		local sm = fs.readFile("roblox/ServerScriptService/SessionManager.lua")
		R.expect(sm:find("RemoteEvents.InventoryUpdated:FireClient(player, data.inventory)", 1, true) ~= nil).toBe(true)
		local craft = fs.readFile("roblox/StarterGui/CraftingUI/init.client.lua")
		R.expect(craft:find('_onPhase(ReplicatedStorage:GetAttribute("Phase"))', 1, true) ~= nil).toBe(true)
		R.expect(craft:find("CraftDraftSlots", 1, true) ~= nil).toBe(true)
		R.expect(craft:find("UIScale", 1, true) ~= nil).toBe(true)   -- 810 × 476 cut off on phones
	end)

	R.it("the boost bar finds the HUD ScreenGui (not the LocalScript named HUD) and again after a rebuild", function()
		local src = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/RacingClient.client.lua")
		R.expect(src:find('PlayerGui:FindFirstChild("HUD")', 1, true)).toBe(nil)
		R.expect(src:find('g.Name == "HUD" and g:IsA("ScreenGui")', 1, true) ~= nil).toBe(true)
		R.expect(src:find("IsDescendantOf(LocalPlayer.PlayerGui)", 1, true) ~= nil).toBe(true)
	end)

	R.it("the harness bot driver and its debug prints stay out of live games", function()
		local bot = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/BotDriver.client.lua")
		R.expect(bot:find("IsStudio() then return end", 1, true) ~= nil).toBe(true)
		local farming = fs.readFile("roblox/StarterPlayer/StarterPlayerScripts/FarmingClient.client.lua")
		R.expect(farming:find("print(", 1, true)).toBe(nil)
	end)
end)
