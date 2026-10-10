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
local PadMode = require(script.Parent.PadMode)
local TutorialOverlay = require(script.Parent.TutorialOverlay)
local TutorialHand = require(script.Parent.TutorialHand)
local TutorialArrow = require(script.Parent.TutorialArrow)
local TutorialGhostShot = require(script.Parent.TutorialGhostShot)
local TutorialGlow = require(script.Parent.TutorialGlow)
local Camera = require(script.Parent.Camera)
local Progression = require(script.Parent.Progression)
local Menus = require(script.Parent.Menus)
local LuckyClient = require(script.Parent.LuckyClient)
local TutorialSoft = require(script.Parent.TutorialSoft)
local TutorialHints = require(script.Parent.TutorialHints)

local Tutorial = {}

local player = Players.LocalPlayer

local overlay: TutorialOverlay.Overlay
local hand: TutorialHand.Hand
local arrow: TutorialArrow.Arrow
local glow: TutorialGlow.Glow
local ghost: TutorialGhostShot.Ghost

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
	if PadMode.active() then
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

-- The soft part's icons pop in one after another (Config.Tutorial.Soft.RevealOrder), from
-- the first frame this client sees the Soft step until the Icons moment is saved.
local softSince: number? = nil
local iconsReportedAt = -math.huge

-- The menu items hidden now (every frame: the soft part's stagger and its quest change it).
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
	if step == "Soft" and not TutorialAnchors.seen("Icons") then
		local now = os.clock()
		softSince = softSince or now
		local Soft = Config.Tutorial.Soft
		local due = (now - (softSince :: number)) / Soft.StaggerSeconds
		for i, item in Soft.RevealOrder do
			if i - 1 > due then
				hidden[item] = true
			end
		end
		if due >= #Soft.RevealOrder - 1 and now - iconsReportedAt >= Timing.ReportAgainSeconds then
			iconsReportedAt = now
			Tutorial.report("Seen", "Icons")
		end
	end
	-- A step's new icons wait while a block opens (Place's open moves the server to Cues at the
	-- E-hold: Cues comes after the reel and its reveal; the designer, 2026-10-09).
	if not broken and step ~= "" and LuckyClient.busy() then
		for item, from in Steps.Reveal do
			if from == step then
				hidden[item] = true
			end
		end
	end
	-- The Win a Match quest takes the daily win track's place until it is won.
	if not broken and TutorialSoft.questOn() then
		hidden.WinTrack = true
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

-- A new scene's anchor the gamepad's selection goes to once it is on screen (a menu's cue
-- card only shows after the menu has unrolled; the menu's own focus lands first).
local selectWanted: string? = nil

-- On a gamepad, a new scene (`fresh`) puts the selection on `anchor` as soon as it is on
-- screen and a stop, so A presses what the line names.
local function selectOn(anchor: string, device: string, fresh: boolean)
	if fresh then
		selectWanted = if device == "gamepad" then anchor else nil
	end
	local object = TutorialAnchors.get(anchor)
	if
		selectWanted == anchor
		and object
		and object.Selectable
		and TutorialAnchors.showing(anchor)
	then
		selectWanted = nil
		GuiService.SelectedObject = object
	end
end

-- Points at a GUI anchor with the dim and the line (at `place`, see TutorialOverlay.say), the
-- gamepad's selection on it when the scene is new (as soon as it is on screen). Nothing while
-- the anchor is not on screen. `clear`: no dim, only the gold ring, and the hand from the
-- side, so what is round the anchor stays in full view.
local function pointAt(
	anchor: string,
	text: string,
	device: string,
	fresh: boolean,
	place: string?,
	clear: boolean?
)
	selectOn(anchor, device, fresh)
	if not TutorialAnchors.showing(anchor) then
		lineOnly(nil)
		return
	end
	local target = TutorialOverlay.guiTarget(anchor)
	if clear then
		overlay:dim(target, false, true)
	else
		overlay:dim(target)
	end
	hand:point(target, clear)
	overlay:say(text, place)
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
local zoomFrom = 0 -- the zoom when the zoom lesson began

-- The table and pocket of a lesson's pot (TutorialAimPocket), or nil.
local function lessonPocket(): (number?, number?)
	local id = player:GetAttribute("TutorialTable")
	local pocket = player:GetAttribute("TutorialAimPocket")
	if type(id) == "number" and id > 0 and type(pocket) == "number" and pocket > 0 then
		return id, pocket
	end
	return nil, nil
end

-- The controller's power button (A: hold it to fill the bar; R2 shoots).
local POWER_UP = PadMode.key(Config.Input.Gamepad.Shoot.Up) :: Enum.KeyCode

-- The shoot prompt: the hand on the bar (or A held), the device's line.
local function shootPrompt(device: string)
	if device == "gamepad" then
		hand:gesture("hold", POWER_UP)
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
		zoomFrom = Camera.getZoom()
	end
	if aimPart == "zoom" then
		local zoom = Camera.getZoom()
		local moved = math.max(zoom / math.max(zoomFrom, 1e-3), zoomFrom / math.max(zoom, 1e-3))
		if zoom >= L.ZoomedOut or moved >= L.ZoomMovedRatio then
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
			hand:gesture("stickY", Enum.KeyCode.Thumbstick2)
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
	local id, pocket = lessonPocket()
	glow:show(id, pocket)
	overlay:dim(nil)
	local balls = player:GetAttribute("TutorialComboBalls")
	local pair = if type(balls) == "string" then string.split(balls, ",") else {}
	local a, b = tonumber(pair[1]), tonumber(pair[2])
	if id and pocket and a and b then
		ghost:show(id, a, b, pocket)
	else
		ghost:hide()
	end
	if os.clock() - aimPartAt >= L.ComboShootSeconds then
		shootPrompt(device)
		return "ComboShoot"
	end
	-- The ghost replay shows the shot: the cue ball into "this ball" (the back one), it into
	-- "that one" (between it and the glowing pocket), that one in.
	hand:hide()
	overlay:say(Copy.Combo)
	return "Combo"
end

local function game1Scene(device: string, fresh: boolean): string
	arrow:show(nil)
	if Tutorial.path() ~= "S" then
		-- A fair first game (path R): the first-time hints teach the pool controls.
		glow:hide()
		TutorialAnchors.setMinPower(nil)
		if fresh or lastLesson ~= "fair" then
			lastLesson = "fair"
			lineOnly(nil)
		end
		return "game1Fair"
	end
	local lesson = player:GetAttribute("TutorialLesson")
	lesson = if type(lesson) == "string" then lesson else ""
	local newLesson = lesson ~= lastLesson
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
			-- The bar lit as on a computer: A fills it (the hand holds A), R2 shoots.
			overlay:dim(TutorialOverlay.guiTarget("PowerBar"))
			hand:gesture("hold", POWER_UP)
		else
			local bar = TutorialOverlay.guiTarget("PowerBar")
			overlay:dim(bar)
			hand:gesture("pull", bar)
		end
		overlay:say(words(Copy.Break, device))
	elseif lesson == "Aim" then
		return "game1" .. aimLesson(device, newLesson) .. device
	elseif lesson == "Combo" then
		return "game1" .. comboLesson(device, newLesson) .. device
	elseif lesson == "Ability" then
		if newLesson then
			-- The aim opens on the planned pot (they are free to change it).
			local angle = player:GetAttribute("TutorialAimAngle")
			if type(angle) == "number" then
				TutorialAnchors.suggestAim(angle)
			end
		end
		overlay:dim(TutorialOverlay.guiTargets({ "UltButton", "UltPrompt" }))
		if device == "gamepad" then
			hand:gesture("hold", (Enum.KeyCode :: any)[Config.UI.Ults.GamepadKey])
		else
			-- A small hand at the prompt's right end: the key it names stays in sight.
			hand:point(TutorialOverlay.guiTarget("UltPrompt", L.PromptHandPadPx), true, true)
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
				if centre == nil then
					return nil, nil
				end
				local play = TutorialOverlay.areas().play
				local toMiddle = Vector2.new(play.x + play.w / 2, play.y + play.h / 2) - centre
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

-- A popup, a menu or the block screens (the upgrade screen, a block opening from its E-hold
-- to its reveal) are up: the chain's pointers wait.
local function busy(): boolean
	return Progression.isBusy() or LuckyClient.busy()
end

-- A step's done report, sent again every Timing.ReportAgainSeconds while the scene holds: the
-- server may not have seen the step's moment yet (it watches some once a second) and drops
-- an early report.
local reportedAt: { [string]: number } = {}
local function reportDone(kind: string)
	local now = os.clock()
	if now - (reportedAt[kind] or -math.huge) >= Timing.ReportAgainSeconds then
		reportedAt[kind] = now
		Tutorial.report(kind)
	end
end

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
	if now - (resultClearAt :: number) >= 1 then
		reportDone("ResultDone")
		return "resultDone"
	end
	return "resultWait"
end

-- Rank: open it, CLAIM, close it.
local function rankScene(device: string, fresh: boolean): string
	local pending = player:GetAttribute("RankPending") == true
	local open = Menus.isOpen(RANKED)
	if pending then
		if open then
			-- The rewards stay lit and uncovered: they see what they claim (the designer).
			local key = "rankClaim" .. device
			pointAt(
				"RankClaim",
				words(Copy.RankClaim, device),
				device,
				shownKey ~= key,
				"Near",
				true
			)
			return key
		end
		if busy() then
			lineOnly(nil)
			return "rankBusy"
		end
		pointAt("Rank", words(Copy.Rank, device), device, fresh or shownKey:sub(1, 8) ~= "rankOpen")
		return "rankOpen" .. device
	end
	if open then
		local key = "rankClose" .. device
		pointAt(RANKED .. "Close", words(Copy.RankClose, device), device, shownKey ~= key)
		return key
	end
	reportDone("RankClosed")
	lineOnly(nil)
	return "rankClosed"
end

-- Mystery: the Mystery block in the hotbar, then its upgrade screen (rigged by the server to
-- climb once); done once the block has landed back in its slot.
local function mysteryScene(device: string, fresh: boolean): string
	if TutorialAnchors.flag("MysteryLanded") then
		reportDone("MysteryDone")
		lineOnly(nil)
		return "mysteryDone"
	end
	if LuckyClient.isOpen() then
		-- The upgrade screen is up: its own Tap! button; the line says what the presses do.
		lineOnly(words(Copy.MysteryPress, device))
		return "mysteryPress" .. device
	end
	if busy() then
		lineOnly(nil)
		return "mysteryBusy"
	end
	local slot = LuckyClient.slotOf(Config.Tutorial.MysteryKind)
	if slot == nil then
		lineOnly(nil)
		return "mysteryNone"
	end
	if LuckyClient.aimedKind() == Config.Tutorial.MysteryKind then
		-- A controller picked it (LB / RB): R2 opens its upgrade screen.
		local key = "mysteryOpen" .. slot .. device
		pointAt("HotbarSlot" .. slot, words(Copy.MysteryOpen, device), device, false)
		return key
	end
	local key = "mystery" .. slot .. device
	pointAt("HotbarSlot" .. slot, words(Copy.Mystery, device), device, fresh or shownKey ~= key)
	return key
end

-- Place: big "Place it!" over the tutorial's block (the block its Mystery became: the server's
-- TutorialBlock attribute; after a rejoin, Bronze's Uncommon block): pick it in the hotbar,
-- place it on the ground, hold to open it (the tutorial's reel, the block's own roll).
local function placeScene(device: string, fresh: boolean): string
	if busy() then
		overlay:bigText(nil)
		lineOnly(nil)
		return "placeBusy"
	end
	local named = player:GetAttribute("TutorialBlock")
	local kind = if type(named) == "string" then named else Config.Tutorial.PlaceFallbackKind
	if LuckyClient.livePart(kind) then
		overlay:bigText(nil)
		lineOnly(words(Copy.Open, device))
		return "placeOpen" .. device
	end
	overlay:bigText(Copy.PlaceBig)
	if LuckyClient.heldKind() == kind then
		lineOnly(words(Copy.Place, device))
		return "placeGround" .. device
	end
	local slot = LuckyClient.slotOf(kind)
	if slot == nil then
		lineOnly(nil)
		return "placeNone"
	end
	local key = "placePick" .. slot .. device
	pointAt("HotbarSlot" .. slot, words(Copy.PlacePick, device), device, fresh or shownKey ~= key)
	return key
end

-- Cues: open Cues, the new cue, Equip, close.
local function cuesScene(device: string): string
	local open = Menus.isOpen(INVENTORY)
	if Tutorial.marked("Equipped") then
		if open then
			local key = "cuesClose" .. device
			pointAt(INVENTORY .. "Close", words(Copy.CuesClose, device), device, shownKey ~= key)
			return key
		end
		reportDone("CuesClosed")
		lineOnly(nil)
		return "cuesClosed"
	end
	if not open then
		if busy() then
			lineOnly(nil)
			return "cuesBusy"
		end
		local key = "cuesOpen" .. device
		pointAt("Inventory", words(Copy.CuesOpen, device), device, shownKey ~= key)
		return key
	end
	if TutorialAnchors.showing("InventoryEquip") then
		-- The line at the top: over Equip it would cover the cue's name and odds.
		local key = "cuesEquip" .. device
		pointAt("InventoryEquip", words(Copy.CuesEquip, device), device, shownKey ~= key)
		return key
	end
	local key = "cuesCard" .. device
	pointAt("InventoryCue", words(Copy.CuesCard, device), device, shownKey ~= key, "Near")
	return key
end

-- The Abilities step filled the code box in (once a step).
local filledCode = false

-- The spin screen's code box (its text box), or nil.
local function codeInput(): TextBox?
	local box = TutorialAnchors.get("CodeBox")
	local input = if box then box:FindFirstChildWhichIsA("TextBox", true) else nil
	return if input and input:IsA("TextBox") then input else nil
end

-- Abilities: open it, type the code, Redeem, SPIN, close.
local function abilitiesScene(device: string): string
	local open = Menus.isOpen(ULTS)
	local code: string = Config.Ults.CodeBanner.ActiveCode
	local row = Config.Daily.Codes[code]
	local spins = if row and row.Spins then row.Spins else 0
	if Tutorial.marked("Spun") then
		if open and not TutorialAnchors.flag("UltSpinning") then
			local key = "abilitiesClose" .. device
			pointAt("SpinBack", words(Copy.AbilitiesClose, device), device, shownKey ~= key, "Near")
			return key
		elseif not open then
			reportDone("AbilitiesClosed")
			lineOnly(nil)
			return "abilitiesClosed"
		end
		lineOnly(nil)
		return "abilitiesSpinning"
	end
	if not open then
		if busy() then
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
		local key = "abilitiesSpin" .. device
		pointAt("SpinButton", words(Copy.Spin, device), device, shownKey ~= key, "Near")
		return key
	end
	-- The box comes filled in on a controller (no typing there), and for anyone once the step's
	-- fallback time is up; the hand then moves to Redeem.
	local input = codeInput()
	if
		not filledCode
		and input
		and input.Text == ""
		and TutorialAnchors.showing("CodeBox")
		and (device == "gamepad" or Tutorial.since() >= fallbackOf("Abilities"))
	then
		input.Text = code
		filledCode = true
	end
	local filled = input ~= nil and string.upper(input.Text) == code
	if
		(TutorialAnchors.flag("CodeFocused") or filled) and TutorialAnchors.showing("CodeRedeem")
	then
		-- The box was clicked: no dim (it is typed into), the gold ring and the hand on Redeem
		-- (a controller's selection on it).
		local key = "abilitiesRedeem" .. device
		local target = TutorialOverlay.guiTarget("CodeRedeem")
		overlay:dim(target, false, true)
		hand:point(target)
		overlay:say(words(Copy.CodeRedeem, device), "Near")
		selectOn("CodeRedeem", device, shownKey ~= key)
		return key
	end
	local text = if device == "gamepad"
		then words(Copy.Code, device):format(spins)
		else words(Copy.Code, device):format(code, spins)
	-- The code box itself, on every screen (a phone's sits in the right column since
	-- 2026-10-10, no longer inside the Odds popup).
	pointAt("CodeBox", text, device, false, "Near")
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
		filledCode = false
	end
	if step ~= "Mystery" then
		TutorialAnchors.setFlag("MysteryLanded", false)
	end
	-- Never over a block screen (the upgrade screen, the reel, its reveal): they end by themselves.
	overlay:setNext(
		NEXT_STEPS[step] == true and Tutorial.since() >= fallbackOf(step) and not LuckyClient.busy(),
		function()
			Tutorial.report("Next")
		end
	)
	if step ~= "Arrow" then
		arrow:show(nil)
	end
	if step ~= "Place" then
		overlay:bigText(nil)
	end
	if step == "Arrow" then
		return arrowScene()
	elseif step == "Game1" then
		return game1Scene(device, fresh)
	elseif step == "Result" then
		return resultScene()
	elseif step == "Rank" then
		return rankScene(device, fresh)
	elseif step == "Mystery" then
		return mysteryScene(device, fresh)
	elseif step == "Place" then
		return placeScene(device, fresh)
	elseif step == "Cues" then
		return cuesScene(device)
	elseif step == "Abilities" then
		return abilitiesScene(device)
	end
	-- Pad, Soft: nothing guided on screen (the first-time hints may draw in the soft part).
	if fresh then
		lineOnly(nil)
	end
	return step
end

-- The menu open last frame: opening Shop or Abilities starts a visit of its funnel (the
-- server's Funnel; for every player, tutorial or not).
local lastMenu: string? = nil
local MENU_FUNNELS: { [string]: string } = { Shop = "ShopOpened", [ULTS] = "AbilitiesOpened" }

-- The device last reported to the server.
local reportedDevice = ""
-- The first-time hint drawn last (its key), and whether the hints failed (off this session).
local hintKey: string? = nil
local hintsBroken = false
local failHints = false -- QA: the hints' next frame fails (op "break" "Hints")

-- The first-time hints (TutorialHints) draw whenever no guided step is on screen: the
-- tutorial over or skipped, the soft part, a fair first game (path R).
local function hintTime(step: string): boolean
	return step == "" or step == "Soft" or (step == "Game1" and Tutorial.path() ~= "S")
end

local function runHints(step: string)
	local allowed = not broken and not hintsBroken and hintTime(step)
	local key: any = nil
	if not hintsBroken then
		local ok: boolean
		ok, key = pcall(function(): string?
			if failHints then
				failHints = false
				error("a test failure")
			end
			return TutorialHints.update({
				overlay = overlay,
				hand = hand,
				words = words,
			}, Tutorial.device(), allowed)
		end)
		if not ok then
			-- Once: the hints are not run again this session.
			hintsBroken = true
			warn(
				"[8ball] Tutorial: the first-time hints failed, off this session: " .. tostring(key)
			)
			Tutorial.report("Error", "Hints")
			key = nil
		end
	end
	if key == nil and hintKey ~= nil and (allowed or hintsBroken) then
		lineOnly(nil) -- the hint is gone (a guided scene draws its own instead)
	end
	hintKey = key
end
-- When the scene showing now began (os.clock), for its re-prompts.
local keyAt = 0

-- The fail-safe: the tutorial ends here and now (the server ends it too and logs it). `part`:
-- "Scene" (a guided scene) or "Soft" (the soft part), the TutorialError's code.
local function breakDown(err: any, part: string)
	if broken then
		return
	end
	broken = true
	warn("[8ball] Tutorial: the " .. part .. " failed, the tutorial ends: " .. tostring(err))
	Tutorial.report("Error", part)
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
	pcall(TutorialSoft.stop)
end

local function update(dt: number)
	pcall(glow.update, glow, dt)
	pcall(ghost.update, ghost, dt)
	pcall(refreshHidden)
	-- The soft part outlives the tutorial's steps (its quest waits for a win).
	if not broken then
		local ok: boolean, err: any = pcall(TutorialSoft.update :: any, dt)
		if not ok then
			breakDown(err, "Soft")
		end
	end
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
		ghost:hide()
		runHints("")
		return
	end
	local ok, result = pcall(scene, Tutorial.step(), Tutorial.device())
	if not ok then
		ghost:hide()
		breakDown(result, "Scene")
		return
	end
	-- The combination's ghost replay shows only in its lesson.
	if string.sub(result, 1, 10) ~= "game1Combo" then
		ghost:hide()
	end
	runHints(Tutorial.step())
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
			elseif a == "hold" or a == "stick" or a == "stickY" then
				hand:gesture(a, (Enum.KeyCode :: any)[b])
			elseif a == "swipe" then
				hand:gesture("swipe", b == true)
			else
				hand:gesture(a) -- "scroll", "pinch"
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
				blockBusy = LuckyClient.busy(),
				cuesShown = TutorialAnchors.showing("Inventory"),
			}
		elseif op == "align" then
			-- The lit hole round anchor `a`: how far its middle sits from the anchor's, in pixels
			-- (0 when the layer's screen math holds on this screen, a notch or not); false
			-- when the anchor is not on screen.
			overlay:dim(TutorialOverlay.guiTarget(a))
			task.wait(0.1)
			local target = TutorialAnchors.get(a)
			local ring = overlay.ring
			if target == nil or not ring.Visible then
				return false
			end
			local mid = ring.AbsolutePosition + ring.AbsoluteSize / 2
			return (mid - (target.AbsolutePosition + target.AbsoluteSize / 2)).Magnitude
		elseif op == "areas" then
			-- The layer's areas (TutorialOverlay.areas) and where Skip and the line are.
			local skip, line = overlay.skip, overlay.line
			return {
				areas = TutorialOverlay.areas(),
				skip = {
					at = skip.AbsolutePosition,
					size = skip.AbsoluteSize,
					spot = overlay.skipSpot,
				},
				line = {
					at = line.AbsolutePosition,
					size = line.AbsoluteSize,
					words = line.TextBounds,
				},
			}
		elseif op == "big" then
			overlay:bigText(a)
		elseif op == "next" then
			if overlay.onNext then
				overlay.onNext()
			end
		elseif op == "break" then
			-- The fail-safe on purpose (QA): as if a scene (`a` "Soft": the soft part; "Hints":
			-- the first-time hints, on their next frame) had failed.
			if a == "Hints" then
				failHints = true
			else
				breakDown("a test failure", if a == "Soft" then "Soft" else "Scene")
			end
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
		elseif op == "notePress" then
			-- The soft part (QA): as if the button the tutorial knows as `a` was pressed.
			TutorialAnchors.notePress(a)
		elseif op == "soft" then
			return TutorialSoft.qaState()
		elseif op == "popup" then
			return TutorialSoft.qaPress(a)
		elseif op == "hint" then
			return TutorialHints.showing() or false
		end
		return true
	end
	hook.Parent = player:WaitForChild("PlayerScripts")
end

--- Builds the tutorial's layer. Call once from Main.
function Tutorial.start()
	overlay = TutorialOverlay.new()
	TutorialSoft.start()
	hand = TutorialHand.new(overlay.gui)
	arrow = TutorialArrow.new(overlay.gui)
	glow = TutorialGlow.new(overlay.gui)
	ghost = TutorialGhostShot.new()
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
