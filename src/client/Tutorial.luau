--!strict
-- Tutorial: tutorial v2 on the client (docs/prompts/TUTORIAL_V2_PROMPT.md). The server decides
-- the step (the TutorialStep attribute; Tutorial/Steps); this module shows it: the instruction
-- line, the light dim, the hand, the arrow, which menu items hide, the Skip button, and a Next
-- button when a step's fallback time is up. It tells the server only what the client alone
-- sees (TutorialEvent), and the device it plays on (the funnels' field).
--
-- Every prompt is device-specific: the words and the hand's gesture follow the last input used
-- (mouse and keyboard, touch, gamepad). The fail-safe: an error in a scene ends the tutorial
-- gracefully (the server is told; everything shows at once, the game plays on).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Strings = require(Shared.Strings)
local Steps = require(Shared.Tutorial.Steps)
local TutorialAnchors = require(script.Parent.TutorialAnchors)
local TutorialOverlay = require(script.Parent.TutorialOverlay)
local TutorialHand = require(script.Parent.TutorialHand)
local TutorialArrow = require(script.Parent.TutorialArrow)
local TutorialGlow = require(script.Parent.TutorialGlow)
local Camera = require(script.Parent.Camera)
local Progression = require(script.Parent.Progression)
local Menus = require(script.Parent.Menus)
local LuckyClient = require(script.Parent.LuckyClient)

local Tutorial = {}

local player = Players.LocalPlayer

local overlay: TutorialOverlay.Overlay
local hand: TutorialHand.Hand
local arrow: TutorialArrow.Arrow
local glow: TutorialGlow.Glow

local ULTS = Config.UI.UltScreen.Column.Name
local INVENTORY = "Inventory"
local RANKED = "Ranked"

local Copy = Strings.Tutorial
local L = Config.Tutorial.Lessons
local Timing = Config.Tutorial.Timing

-- What else is hidden at a step: a pad's Play Global (the bot comes by itself), and the
-- rematch row of game 1's result (only Continue: the bot does not play again).
local HOST_HIDES: { [string]: { string } } = {
	Pad = { "HostGlobal" },
	Game1 = { "Rematch", "Another" },
	Result = { "Rematch", "Another" },
}

-- The scene showing now (its key), and the step it belongs to.
local shownKey = ""
local shownStep = ""
-- The fail-safe tripped: the tutorial shows nothing more this session.
local broken = false
-- Studio only (TutorialClientQA "forceDevice"): the device the prompts are built for, to check
-- the touch and gamepad words and gestures without the emulator.
local forcedDevice: string? = nil

--- The input the player is using now: "mouse", "touch" or "gamepad".
function Tutorial.device(): string
	if forcedDevice then
		return forcedDevice
	end
	local last = UserInputService:GetLastInputType()
	if last.Name:match("^Gamepad") then
		return "gamepad"
	elseif last == Enum.UserInputType.Touch then
		return "touch"
	elseif
		last == Enum.UserInputType.None
		and UserInputService.TouchEnabled
		and not UserInputService.MouseEnabled
	then
		return "touch"
	end
	return "mouse"
end

--- The device for the funnels' field: "Console", "Phone", "Tablet" or "PC".
function Tutorial.deviceKind(): string
	if GuiService:IsTenFootInterface() then
		return "Console"
	end
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		local camera = workspace.CurrentCamera
		local short = if camera then math.min(camera.ViewportSize.X, camera.ViewportSize.Y) else 0
		return if short < Config.Tutorial.Device.PhoneBelowPx then "Phone" else "Tablet"
	end
	return "PC"
end

--- The player's tutorial step ("" when it is over).
function Tutorial.step(): string
	local step = player:GetAttribute("TutorialStep")
	return if type(step) == "string" then step else ""
end

--- Whether the tutorial runs now (any step).
function Tutorial.active(): boolean
	return Tutorial.step() ~= "" and not broken
end

--- Game 1's path ("S", "R" or "").
function Tutorial.path(): string
	local p = player:GetAttribute("TutorialPath")
	return if type(p) == "string" then p else ""
end

--- Seconds since the current step began (the server's clock).
function Tutorial.since(): number
	local at = player:GetAttribute("TutorialStepAt")
	return if type(at) == "number" then workspace:GetServerTimeNow() - at else 0
end

--- Whether the server saw moment `name` in the current step (TutorialMarks: RankClaimed,
--- Equipped, Redeemed, Spun).
function Tutorial.marked(name: string): boolean
	local marks = player:GetAttribute("TutorialMarks")
	return type(marks) == "string" and table.find(string.split(marks, ","), name) ~= nil
end

--- Tells the server something only the client sees (the server checks it against the step).
function Tutorial.report(kind: string, data: any?)
	Net.get("TutorialEvent"):FireServer(kind, data)
end

-- The fallback time of `step` (Config.Tutorial.Timing).
local function fallbackOf(step: string): number
	return Timing.Fallback[step] or Timing.FallbackSeconds
end

-- The menu items hidden at this step.
local function refreshHidden()
	local step = if broken then "" else Tutorial.step()
	local hidden: { [string]: boolean } = {}
	for item in Steps.Reveal do
		if not Steps.shows(if step == "" then nil else step, item) then
			hidden[item] = true
		end
	end
	local hostHides: { string } = HOST_HIDES[step] or {}
	for _, item in hostHides do
		hidden[item] = true
	end
	TutorialAnchors.setHidden(hidden)
end

-- Table `id`'s queue pad, if it is there.
local function padOf(id: number): BasePart?
	local zones = workspace:FindFirstChild("TableZones")
	local pad = zones and zones:FindFirstChild(("QueuePad_%02d"):format(id))
	return if pad and pad:IsA("BasePart") then pad else nil
end

-- The words for this device from a { Mouse, Touch, Gamepad } set (a gamepad line's {tokens}
-- become Roblox's button pictures in the overlay).
local function words(set: { [string]: string }, device: string): string
	return if device == "gamepad"
		then set.Gamepad
		elseif device == "touch" then set.Touch
		else set.Mouse
end

-- Nothing on screen but the line (or nothing at all).
local function lineOnly(text: string?)
	overlay:dim(nil)
	hand:hide()
	overlay:say(text)
end

-- Points at a GUI anchor with the dim and the line (at `place`, see TutorialOverlay.say), the
-- gamepad's selection on it when the scene is new. Nothing while the anchor is not on screen.
local function pointAt(anchor: string, text: string, device: string, fresh: boolean, place: string?)
	if not TutorialAnchors.showing(anchor) then
		lineOnly(nil)
		return
	end
	local target = TutorialOverlay.guiTarget(anchor)
	overlay:dim(target)
	hand:point(target)
	overlay:say(text, place)
	local object = TutorialAnchors.get(anchor)
	if fresh and device == "gamepad" and object and object.Selectable then
		GuiService.SelectedObject = object
	end
end

---------------------------------------------------------------------------------------------
-- Joining game 1
---------------------------------------------------------------------------------------------

-- The arrow: to the reserved table's pad ("Need help?" once its fallback time is up; after
-- the re-prompt time it pulses harder).
local function arrowScene(): string
	local id = player:GetAttribute("TutorialTable")
	local pad = if type(id) == "number" and id > 0 then padOf(id) else nil
	local goal = if pad then pad.Position + Vector3.new(0, pad.Size.Y / 2, 0) else nil
	arrow:show(goal, pad)
	arrow:setUrgent(Tutorial.since() >= Timing.RepromptSeconds)
	overlay:dim(nil)
	hand:hide()
	local late = Tutorial.since() >= fallbackOf("Arrow")
	overlay:say(
		if goal == nil then Copy.WaitTable elseif late then Copy.ArrowHelp else Copy.JoinTable
	)
	return "arrow" .. tostring(id) .. tostring(late)
end

---------------------------------------------------------------------------------------------
-- Game 1 (path S: the lessons, the TutorialLesson attribute set by TutorialGames)
---------------------------------------------------------------------------------------------

-- The lesson shown last, so a new one can start its own way (the aim suggestion).
local lastLesson = ""
-- The aim lesson's part (turn 2): "aim" (adjust the angle), "zoom" (zoom out, the pocket
-- glows), "zoomed" ("You can zoom in and out any time."), "shoot"; and when it began.
local aimPart = "aim"
local aimPartAt = 0

-- The table and pocket of a lesson's pot (TutorialAimPocket), or nil.
local function lessonPocket(): (number?, number?)
	local id = player:GetAttribute("TutorialTable")
	local pocket = player:GetAttribute("TutorialAimPocket")
	if type(id) == "number" and id > 0 and type(pocket) == "number" and pocket > 0 then
		return id, pocket
	end
	return nil, nil
end

-- The shoot prompt: the hand on the bar (or R2 held), the device's line.
local function shootPrompt(device: string)
	if device == "gamepad" then
		hand:gesture("hold", Enum.KeyCode.ButtonR2)
	else
		hand:gesture("pull", TutorialOverlay.guiTarget("PowerBar"))
	end
	overlay:say(words(Copy.Shoot, device))
end

-- The aim lesson (turn 2): adjust the angle, zoom out to see it better (the pocket glows), then
-- shoot.
local function aimLesson(device: string, fresh: boolean): string
	local now = os.clock()
	if fresh then
		TutorialAnchors.resetTurn()
		local angle = player:GetAttribute("TutorialAimAngle")
		if type(angle) == "number" then
			TutorialAnchors.suggestAim(angle + math.rad(L.AimOffsetDegrees))
		end
		aimPart, aimPartAt = "aim", now
	end
	overlay:dim(nil)
	if aimPart == "aim" and TutorialAnchors.turned() >= L.AimTurnedDegrees then
		Tutorial.report("Lesson", "Aimed")
		aimPart, aimPartAt = "zoom", now
	end
	if aimPart == "zoom" then
		if Camera.getZoom() >= L.ZoomedOut then
			Tutorial.report("Lesson", "Zoomed")
			aimPart, aimPartAt = "zoomed", now
		elseif now - aimPartAt >= Timing.ZoomSkipSeconds then
			aimPart, aimPartAt = "shoot", now -- not zooming: the pocket still glows
		end
	end
	if aimPart == "zoomed" and now - aimPartAt >= L.ZoomDoneSeconds then
		aimPart, aimPartAt = "shoot", now
	end
	if aimPart ~= "aim" then
		glow:show(lessonPocket())
	else
		glow:hide()
	end
	if aimPart == "aim" then
		if device == "gamepad" then
			hand:gesture("stick", Enum.KeyCode.Thumbstick1)
		else
			hand:gesture("swipe", device == "mouse")
		end
		overlay:say(words(Copy.Aim, device))
	elseif aimPart == "zoom" then
		if device == "gamepad" then
			hand:gesture("stick", Enum.KeyCode.Thumbstick2)
		else
			hand:gesture(if device == "touch" then "pinch" else "scroll")
		end
		overlay:say(words(Copy.Zoom, device))
	elseif aimPart == "zoomed" then
		hand:hide()
		overlay:say(Copy.ZoomDone)
	else
		shootPrompt(device)
	end
	return "Aim" .. aimPart
end

-- The combination (designer, 2026-10-09): the aim opens on it, the hand points at the two
-- balls, their pocket glows; after a moment the line says to shoot.
local function comboLesson(device: string, fresh: boolean): string
	if fresh then
		local angle = player:GetAttribute("TutorialAimAngle")
		if type(angle) == "number" then
			TutorialAnchors.suggestAim(angle)
		end
		aimPartAt = os.clock()
	end
	glow:show(lessonPocket())
	overlay:dim(nil)
	if os.clock() - aimPartAt >= L.ComboShootSeconds then
		shootPrompt(device)
		return "ComboShoot"
	end
	local id = player:GetAttribute("TutorialTable")
	local balls = player:GetAttribute("TutorialComboBalls")
	local pair = if type(balls) == "string" then string.split(balls, ",") else {}
	local a, b = tonumber(pair[1]), tonumber(pair[2])
	if type(id) == "number" and a and b then
		-- "Hit this ball" (the back one); "into that one" sits between it and the glowing pocket.
		hand:point(TutorialOverlay.worldTarget(function(): Vector3?
			return TutorialAnchors.worldPoint(id, "ball", a)
		end, 24))
	else
		hand:hide()
	end
	overlay:say(Copy.Combo)
	return "Combo"
end

local function game1Scene(device: string): string
	arrow:show(nil)
	if Tutorial.path() ~= "S" then
		glow:hide()
		TutorialAnchors.setMinPower(nil)
		lineOnly(nil)
		return "game1Fair"
	end
	local lesson = player:GetAttribute("TutorialLesson")
	lesson = if type(lesson) == "string" then lesson else ""
	local fresh = lesson ~= lastLesson
	lastLesson = lesson
	TutorialAnchors.setAimLock(if lesson == "Break" then Config.Tutorial.Break.Angle else nil)
	-- The break: a release under half power does nothing (the bar springs back, the line
	-- shakes: weakRelease).
	TutorialAnchors.setMinPower(if lesson == "Break" then L.BreakMinPower else nil)
	if lesson ~= "Aim" and lesson ~= "Combo" and lesson ~= "Eight" then
		glow:hide()
	end
	if lesson == "Break" then
		if device == "gamepad" then
			overlay:dim(nil)
			hand:gesture("hold", Enum.KeyCode.ButtonR2)
		else
			local bar = TutorialOverlay.guiTarget("PowerBar")
			overlay:dim(bar)
			hand:gesture("pull", bar)
		end
		overlay:say(words(Copy.Break, device))
	elseif lesson == "Aim" then
		return "game1" .. aimLesson(device, fresh) .. device
	elseif lesson == "Combo" then
		return "game1" .. comboLesson(device, fresh) .. device
	elseif lesson == "Ability" then
		if fresh then
			-- The aim opens on the planned pot (they are free to change it).
			local angle = player:GetAttribute("TutorialAimAngle")
			if type(angle) == "number" then
				TutorialAnchors.suggestAim(angle)
			end
		end
		local button = TutorialOverlay.guiTarget("UltButton")
		overlay:dim(button)
		if device == "gamepad" then
			hand:gesture("hold", (Enum.KeyCode :: any)[Config.UI.Ults.GamepadKey])
		else
			hand:point(button)
		end
		overlay:say(words(Copy.Ability, device):format(Config.UI.Ults.KeyboardKey))
	elseif lesson == "BallInHand" then
		overlay:dim(nil)
		if device == "gamepad" then
			hand:gesture("stick", Enum.KeyCode.Thumbstick1)
		else
			local from = TutorialOverlay.guiTarget("CueBallHandle")
			hand:gesture("drag", from, function(): (Vector2?, Vector2?)
				-- Toward the middle of the screen (the table), DragPx long.
				local centre, size = from()
				local camera = workspace.CurrentCamera
				if centre == nil or camera == nil then
					return nil, nil
				end
				local toMiddle = camera.ViewportSize / 2 - centre
				local long = Vector2.new(L.DragPx[1], L.DragPx[2]).Magnitude
				if toMiddle.Magnitude < long / 2 then
					return centre + Vector2.new(L.DragPx[1], L.DragPx[2]), size
				end
				return centre + toMiddle.Unit * long, size
			end)
		end
		overlay:say(words(Copy.BallInHand, device))
	elseif lesson == "Eight" then
		-- The pocket the 8 sits by glows, the hand on its button (every pocket stays clickable).
		local id, at = player:GetAttribute("TutorialTable"), player:GetAttribute("TutorialPocket")
		glow:show(
			if type(id) == "number" then id else nil,
			if type(at) == "number" then at else nil
		)
		local pocket = TutorialOverlay.guiTarget("Pocket" .. tostring(at))
		overlay:dim(pocket)
		hand:point(pocket)
		overlay:say(words(Copy.Eight, device))
	elseif lesson == "Away" then
		lineOnly(Copy.Away)
	else
		lineOnly(nil)
	end
	return "game1" .. lesson .. device
end

---------------------------------------------------------------------------------------------
-- The chain after game 1 (Result .. Abilities)
---------------------------------------------------------------------------------------------

-- Result: the result screen, the first win's block and NEW RANK! play on their own; once
-- none of them is up, the step is done.
local resultClearAt: number? = nil
local function resultScene(): string
	lineOnly(nil)
	if Progression.isBusy() or Tutorial.since() < 1 then
		resultClearAt = nil
		return "resultBusy"
	end
	local now = os.clock()
	resultClearAt = resultClearAt or now
	if now - (resultClearAt :: number) >= 1 and shownKey ~= "resultDone" then
		Tutorial.report("ResultDone")
		return "resultDone"
	end
	return if shownKey == "resultDone" then "resultDone" else "resultWait"
end

-- Rank: open it, CLAIM, close it.
local function rankScene(device: string, fresh: boolean): string
	local pending = player:GetAttribute("RankPending") == true
	local open = Menus.isOpen(RANKED)
	if pending then
		if open then
			pointAt("RankClaim", words(Copy.RankClaim, device), device, fresh, "Near")
			return "rankClaim" .. device
		end
		if Progression.isBusy() then
			lineOnly(nil)
			return "rankBusy"
		end
		pointAt("Rank", words(Copy.Rank, device), device, fresh or shownKey:sub(1, 8) ~= "rankOpen")
		return "rankOpen" .. device
	end
	if open then
		lineOnly(words(Copy.RankClose, device))
		return "rankClose" .. device
	end
	if shownKey ~= "rankClosed" then
		Tutorial.report("RankClosed")
	end
	lineOnly(nil)
	return "rankClosed"
end

-- Mystery: the Mystery block in the hotbar (its upgrade screen is tutorial v2 step 9).
local function mysteryScene(device: string, fresh: boolean): string
	if Progression.isBusy() then
		lineOnly(nil)
		return "mysteryBusy"
	end
	local slot = LuckyClient.slotOf(Config.Tutorial.MysteryKind)
	if slot == nil then
		lineOnly(nil)
		return "mysteryNone"
	end
	local key = "mystery" .. slot .. device
	pointAt("HotbarSlot" .. slot, words(Copy.Mystery, device), device, fresh or shownKey ~= key)
	return key
end

-- Place: "Place it!", then open it (the reel lands the tutorial's cue).
local function placeScene(): string
	if Progression.isBusy() then
		lineOnly(nil)
		return "placeBusy"
	end
	lineOnly(nil)
	overlay:bigText(Copy.PlaceBig)
	return "place"
end

-- Cues: open Cues, the new cue, Equip, close.
local function cuesScene(device: string): string
	local open = Menus.isOpen(INVENTORY)
	if Tutorial.marked("Equipped") then
		if open then
			lineOnly(words(Copy.CuesClose, device))
			return "cuesClose" .. device
		end
		if shownKey ~= "cuesClosed" then
			Tutorial.report("CuesClosed")
		end
		lineOnly(nil)
		return "cuesClosed"
	end
	if not open then
		if Progression.isBusy() then
			lineOnly(nil)
			return "cuesBusy"
		end
		local key = "cuesOpen" .. device
		pointAt("Inventory", words(Copy.CuesOpen, device), device, shownKey ~= key)
		return key
	end
	if TutorialAnchors.showing("InventoryEquip") then
		local key = "cuesEquip" .. device
		pointAt("InventoryEquip", words(Copy.CuesEquip, device), device, shownKey ~= key, "Near")
		return key
	end
	local key = "cuesCard" .. device
	pointAt("InventoryCue", words(Copy.CuesCard, device), device, shownKey ~= key, "Near")
	return key
end

-- Abilities: open it, type the code, Redeem, SPIN, close.
local function abilitiesScene(device: string, fresh: boolean): string
	local open = Menus.isOpen(ULTS)
	local code: string = Config.Ults.CodeBanner.ActiveCode
	local row = Config.Daily.Codes[code]
	local spins = if row and row.Spins then row.Spins else 0
	if Tutorial.marked("Spun") then
		if open and not TutorialAnchors.flag("UltSpinning") then
			pointAt("SpinBack", words(Copy.AbilitiesClose, device), device, fresh, "Near")
			return "abilitiesClose" .. device
		elseif not open then
			if shownKey ~= "abilitiesClosed" then
				Tutorial.report("AbilitiesClosed")
			end
			lineOnly(nil)
			return "abilitiesClosed"
		end
		lineOnly(nil)
		return "abilitiesSpinning"
	end
	if not open then
		if Progression.isBusy() then
			lineOnly(nil)
			return "abilitiesBusy"
		end
		local key = "abilitiesOpen" .. device
		pointAt("Abilities", words(Copy.AbilitiesOpen, device), device, shownKey ~= key)
		return key
	end
	if TutorialAnchors.flag("UltSpinning") then
		lineOnly(nil)
		return "abilitiesSpinning"
	end
	if Tutorial.marked("Redeemed") then
		pointAt("SpinButton", words(Copy.Spin, device), device, fresh, "Near")
		return "abilitiesSpin" .. device
	end
	if TutorialAnchors.flag("CodeFocused") and TutorialAnchors.showing("CodeRedeem") then
		-- The box was clicked: no dim (it is typed into), the gold ring and the hand on Redeem.
		local target = TutorialOverlay.guiTarget("CodeRedeem")
		overlay:dim(target, false, true)
		hand:point(target)
		overlay:say(words(Copy.CodeRedeem, device), "Near")
		return "abilitiesRedeem" .. device
	end
	local text = if device == "gamepad"
		then words(Copy.Code, device):format(spins)
		else words(Copy.Code, device):format(code, spins)
	if TutorialAnchors.showing("CodeBox") then
		pointAt("CodeBox", text, device, false, "Near")
	else
		pointAt("UltOddsButton", text, device, fresh, "Near")
	end
	return "abilitiesCode" .. device
end

---------------------------------------------------------------------------------------------
-- The router
---------------------------------------------------------------------------------------------

-- The Next button for a chain step once its fallback time is up (never on a step whose
-- moves the server watches by itself).
local NEXT_STEPS: { [string]: boolean } = {
	Result = true,
	Rank = true,
	Mystery = true,
	Place = true,
	Cues = true,
	Abilities = true,
}

-- Builds the scene for the step now (the line, the dim, the hand, the arrow). Cheap enough
-- to run every frame: each piece only changes when its input does.
local function scene(step: string, device: string): string
	local fresh = step ~= shownStep
	shownStep = step
	if step ~= "Game1" then
		TutorialAnchors.setAimLock(nil)
		TutorialAnchors.setMinPower(nil)
		glow:hide()
		lastLesson = ""
	end
	if step ~= "Abilities" then
		TutorialAnchors.setFlag("CodeFocused", false)
	end
	overlay:setNext(NEXT_STEPS[step] == true and Tutorial.since() >= fallbackOf(step), function()
		Tutorial.report("Next")
	end)
	if step ~= "Arrow" then
		arrow:show(nil)
	end
	if step ~= "Place" then
		overlay:bigText(nil)
	end
	if step == "Arrow" then
		return arrowScene()
	elseif step == "Game1" then
		return game1Scene(device)
	elseif step == "Result" then
		return resultScene()
	elseif step == "Rank" then
		return rankScene(device, fresh)
	elseif step == "Mystery" then
		return mysteryScene(device, fresh)
	elseif step == "Place" then
		return placeScene()
	elseif step == "Cues" then
		return cuesScene(device)
	elseif step == "Abilities" then
		return abilitiesScene(device, fresh)
	end
	-- Pad, Soft: nothing guided on screen.
	lineOnly(nil)
	return step
end

-- The menu open last frame: opening Shop or Abilities starts a visit of its funnel (the
-- server's Funnel; for every player, tutorial or not).
local lastMenu: string? = nil
local MENU_FUNNELS: { [string]: string } = { Shop = "ShopOpened", [ULTS] = "AbilitiesOpened" }

-- The device last reported to the server.
local reportedDevice = ""
-- When the scene showing now began (os.clock), for its re-prompts.
local keyAt = 0

-- The fail-safe: the tutorial ends here and now (the server ends it too and logs it).
local function breakDown(err: any)
	if broken then
		return
	end
	broken = true
	warn("[8ball] Tutorial: a scene failed, the tutorial ends: " .. tostring(err))
	Tutorial.report("Error")
	pcall(function()
		overlay:clear()
		overlay:setSkip(false)
		hand:hide()
		arrow:show(nil)
		glow:hide()
		TutorialAnchors.setAimLock(nil)
		TutorialAnchors.setMinPower(nil)
	end)
	pcall(refreshHidden)
end

local function update(dt: number)
	pcall(glow.update, glow, dt)
	local menu = Menus.current()
	if menu ~= lastMenu then
		lastMenu = menu
		local kind = if menu then MENU_FUNNELS[menu] else nil
		if kind then
			Tutorial.report(kind)
		end
	end
	local kind = Tutorial.deviceKind()
	if kind ~= reportedDevice then
		reportedDevice = kind
		Tutorial.report("Device", kind)
	end
	if not Tutorial.active() then
		shownKey, shownStep = "", ""
		return
	end
	local ok, result = pcall(scene, Tutorial.step(), Tutorial.device())
	if not ok then
		breakDown(result)
		return
	end
	local now = os.clock()
	if result ~= shownKey then
		shownKey = result
		keyAt = now
	elseif now - keyAt >= Timing.RepromptSeconds then
		-- The same scene with its action still not done: the line pops and the hand pulses.
		keyAt = now
		if overlay.lineText or overlay.bigShown then
			overlay:nudge()
			hand:nudge()
		end
	end
end

local function refresh()
	refreshHidden()
	overlay:setSkip(Tutorial.active() and Steps.guided(Tutorial.step()), function()
		Tutorial.report("Skip")
	end)
	if not Tutorial.active() then
		overlay:clear()
		hand:hide()
		arrow:show(nil)
		glow:hide()
		TutorialAnchors.setAimLock(nil)
		TutorialAnchors.setMinPower(nil)
	end
end

-- Studio only: show each piece from a script (PlayerScripts.TutorialClientQA).
local function startQA()
	if not RunService:IsStudio() then
		return
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "TutorialClientQA"
	hook.OnInvoke = function(op: string, a: any, b: any): any
		if op == "say" then
			overlay:say(a)
		elseif op == "dim" then
			overlay:dim(if a then TutorialOverlay.guiTarget(a) else nil)
		elseif op == "dimAll" then
			overlay:dim(nil, true)
		elseif op == "point" then
			hand:point(TutorialOverlay.guiTarget(a))
		elseif op == "pointWorld" then
			hand:point(TutorialOverlay.worldTarget(a, 20))
		elseif op == "gesture" then
			if a == "pull" then
				hand:gesture("pull", TutorialOverlay.guiTarget(b))
			elseif a == "hold" or a == "stick" then
				hand:gesture(a, (Enum.KeyCode :: any)[b])
			elseif a == "swipe" then
				hand:gesture("swipe", b == true)
			end
		elseif op == "arrow" then
			arrow:show(a)
		elseif op == "clear" then
			overlay:clear()
			hand:hide()
			arrow:show(nil)
		elseif op == "device" then
			return Tutorial.device()
		elseif op == "forceDevice" then
			forcedDevice = if a == "mouse" or a == "touch" or a == "gamepad" then a else nil
			shownKey = ""
		elseif op == "state" then
			return {
				step = Tutorial.step(),
				key = shownKey,
				broken = broken,
				line = overlay.lineText,
				next = overlay.nextButton.Visible,
			}
		elseif op == "big" then
			overlay:bigText(a)
		elseif op == "next" then
			if overlay.onNext then
				overlay.onNext()
			end
		elseif op == "break" then
			-- The fail-safe on purpose (QA): as if a scene had failed.
			breakDown("a test failure")
		elseif op == "turn" then
			-- Game 1's aim lesson (QA): as if the aim had turned `a` degrees.
			TutorialAnchors.noteTurn(a)
		elseif op == "zoom" then
			-- The zoom lesson (QA): the camera zooms by `a` (above 1 zooms in, below 1 out).
			Camera.zoomBy(a)
			return Camera.getZoom()
		elseif op == "minPower" then
			return TutorialAnchors.minPower() or false
		elseif op == "weak" then
			TutorialAnchors.noteWeakRelease() -- the break's too-soft release: the line shakes
		elseif op == "aimPart" then
			return aimPart
		end
		return true
	end
	hook.Parent = player:WaitForChild("PlayerScripts")
end

--- Builds the tutorial's layer. Call once from Main.
function Tutorial.start()
	overlay = TutorialOverlay.new()
	hand = TutorialHand.new(overlay.gui)
	arrow = TutorialArrow.new(overlay.gui)
	glow = TutorialGlow.new(overlay.gui)
	overlay.avoid = function(): { Vector3 }
		local spots = {}
		local pocket = glow:point()
		if pocket then
			table.insert(spots, pocket)
		end
		-- The combination's two balls.
		local id = player:GetAttribute("TutorialTable")
		local pair = player:GetAttribute("TutorialComboBalls")
		if
			player:GetAttribute("TutorialLesson") == "Combo"
			and type(id) == "number"
			and type(pair) == "string"
		then
			for _, ball in string.split(pair, ",") do
				local n = tonumber(ball)
				local at = if n then TutorialAnchors.worldPoint(id, "ball", n) else nil
				if at then
					table.insert(spots, at)
				end
			end
		end
		return spots
	end
	TutorialAnchors.weakRelease:Connect(function()
		overlay:shake()
		hand:nudge()
	end)
	player:GetAttributeChangedSignal("TutorialStep"):Connect(refresh)
	refresh()
	RunService.RenderStepped:Connect(update)
	startQA()
end

return Tutorial
