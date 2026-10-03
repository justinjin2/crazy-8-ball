--!strict
-- Tutorial: the first-time tutorial on the client (docs/prompts/TUTORIAL_PROMPT.md). The server
-- decides the step (the TutorialStep attribute; Tutorial/Steps); this module shows it: the
-- instruction line, the light dim, the hand, the floor arrow, which menu items hide, and the
-- Skip button. It tells the server only what the client alone sees (TutorialEvent).
--
-- Every prompt is device-specific (designer, 2026-10-03): the words and the hand's gesture
-- follow the last input used (mouse and keyboard, touch, gamepad).
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
local TutorialReveal = require(script.Parent.TutorialReveal)
local TutorialCasePill = require(script.Parent.TutorialCasePill)
local Progression = require(script.Parent.Progression)
local Menus = require(script.Parent.Menus)
local ItemState = require(script.Parent.ItemState)

local Tutorial = {}

local player = Players.LocalPlayer

local overlay: TutorialOverlay.Overlay
local hand: TutorialHand.Hand
local arrow: TutorialArrow.Arrow
local reveal: TutorialReveal.Reveal
local pill: TutorialCasePill.Pill

local ULTS = Config.UI.UltScreen.Column.Name

local Copy = Strings.Tutorial
local L = Config.Tutorial.Lessons

-- The HUD items the tutorial brings in one by one.
local ITEMS = { "Shop", "Inventory", "Abilities", "Rank", "FreeReward", "Trade" }

-- The host card's parts hidden at a step, so it shows only the button the step teaches
-- (QueueMenu reads them: HostMore is vs PC, solo and fill with PC; HostLevels the PC levels),
-- game 1's post-match row with Leave only (the bot has jumped off: no rematch), and game 2's
-- with Lobby only (PostMatch: no rematch, no Play another).
local HOST_HIDES: { [string]: { string } } = {
	Request = { "HostMore", "HostLevels", "HostGlobal" },
	Queue = { "HostMore", "HostLevels", "HostRequest" },
	Drop = { "Rematch" },
	Equip = { "Rematch" },
	Game2 = { "Rematch", "Another", "Cancel" },
	Lobby = { "Rematch", "Another", "Cancel" },
}

-- The step whose scene is showing, and the device it was built for.
local shownKey = ""
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

--- The player's tutorial step ("" when it is over).
function Tutorial.step(): string
	local step = player:GetAttribute("TutorialStep")
	return if type(step) == "string" then step else ""
end

--- Whether the tutorial runs now (any step).
function Tutorial.active(): boolean
	return Tutorial.step() ~= ""
end

--- Tells the server something only the client sees (the server checks it against the step).
function Tutorial.report(kind: string, data: any?)
	Net.get("TutorialEvent"):FireServer(kind, data)
end

-- The menu items hidden at this step.
local function refreshHidden()
	local step = Tutorial.step()
	local hidden: { [string]: boolean } = {}
	for _, item in ITEMS do
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

-- The floor point of table `id`'s queue pad, if it is there.
local function padPoint(id: number): Vector3?
	local zones = workspace:FindFirstChild("TableZones")
	local pad = zones and zones:FindFirstChild(("QueuePad_%02d"):format(id))
	if pad and pad:IsA("BasePart") then
		return pad.Position + Vector3.new(0, pad.Size.Y / 2, 0)
	end
	return nil
end

-- The words for this device from a { Mouse, Touch, Gamepad } set.
local function words(set: { [string]: string }, device: string): string
	return if device == "gamepad"
		then set.Gamepad
		elseif device == "touch" then set.Touch
		else set.Mouse
end

-- The arrow steps: lead to the reserved table's pad.
local function arrowScene(): string
	local id = player:GetAttribute("TutorialTable")
	local goal = if type(id) == "number" and id > 0 then padPoint(id) else nil
	arrow:show(goal)
	overlay:dim(nil)
	hand:hide()
	overlay:say(if goal then Copy.JoinTable else Copy.WaitTable)
	return "arrow" .. tostring(id)
end

-- The pad steps: light the one host-card button the step teaches, the hand tapping it.
local function padScene(anchor: string, set: { [string]: string }, device: string): string
	arrow:show(nil)
	if player:GetAttribute("TutorialCalling") == true then
		overlay:dim(nil)
		hand:hide()
		overlay:say(Copy.Finding)
		return "calling"
	end
	if not TutorialAnchors.showing(anchor) then
		overlay:dim(nil)
		hand:hide()
		overlay:say(nil)
		return "wait" .. anchor
	end
	local target = TutorialOverlay.guiTarget(anchor)
	overlay:dim(target)
	hand:point(target)
	local text = words(set, device)
	if device == "gamepad" then
		-- Put the gamepad on the button so A presses it; once moved off, Y comes back to it.
		local button = TutorialAnchors.get(anchor)
		if shownKey:sub(1, #anchor) ~= anchor and button then
			GuiService.SelectedObject = button
		end
		local selected = GuiService.SelectedObject
		if selected == nil or selected ~= button then
			text = set.GamepadFocus or text
		end
	end
	overlay:say(text)
	return anchor .. device .. text
end

-- The lesson shown last (game 1), so a new one can start its own way (the aim suggestion).
local lastLesson = ""

-- Nothing on screen but the line (or nothing at all).
local function lineOnly(text: string?)
	overlay:dim(nil)
	hand:hide()
	overlay:say(text)
end

-- Game 1's lessons (the TutorialLesson attribute, set by the server's TutorialGames).
local function game1Scene(device: string): string
	arrow:show(nil)
	local lesson = player:GetAttribute("TutorialLesson")
	lesson = if type(lesson) == "string" then lesson else ""
	local fresh = lesson ~= lastLesson
	lastLesson = lesson
	TutorialAnchors.setAimLock(if lesson == "Break" then Config.Tutorial.Break.Angle else nil)
	if lesson == "Break" then
		if device == "gamepad" then
			overlay:dim(nil)
			hand:gesture("hold", Enum.KeyCode.ButtonA)
		else
			local bar = TutorialOverlay.guiTarget("PowerBar")
			overlay:dim(bar)
			hand:gesture("pull", bar)
		end
		overlay:say(words(Copy.Break, device))
	elseif lesson == "Aim" then
		if fresh then
			TutorialAnchors.resetTurn()
			local angle = player:GetAttribute("TutorialAimAngle")
			if type(angle) == "number" then
				TutorialAnchors.suggestAim(angle + math.rad(L.AimOffsetDegrees))
			end
		end
		overlay:dim(nil)
		if TutorialAnchors.turned() < L.AimTurnedDegrees then
			if device == "gamepad" then
				hand:gesture("stick", Enum.KeyCode.Thumbstick1)
			else
				hand:gesture("swipe", device == "mouse")
			end
			overlay:say(words(Copy.Aim, device))
		else
			if device == "gamepad" then
				hand:gesture("hold", Enum.KeyCode.ButtonA)
			else
				hand:gesture("pull", TutorialOverlay.guiTarget("PowerBar"))
			end
			overlay:say(words(Copy.AimShoot, device))
		end
	elseif lesson == "Ability" then
		local button = TutorialOverlay.guiTarget("UltButton")
		overlay:dim(button)
		if device == "gamepad" then
			hand:gesture("hold", (Enum.KeyCode :: any)[Config.UI.Ults.GamepadKey])
		else
			hand:point(button)
		end
		overlay:say(words(Copy.Ability, device))
	elseif lesson == "Pick" then
		if TutorialAnchors.flag("UltPicked") then
			local confirm = TutorialOverlay.guiTarget("UltConfirm")
			overlay:dim(confirm)
			hand:point(confirm)
			overlay:say(words(Copy.PickConfirm, device), "Low")
		else
			local id = player:GetAttribute("TutorialPickBall")
			local ring = TutorialOverlay.guiTarget("PickBall" .. tostring(id))
			overlay:dim(ring)
			hand:point(ring)
			overlay:say(words(Copy.Pick, device), "Low")
		end
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
		local pocket =
			TutorialOverlay.guiTarget("Pocket" .. tostring(player:GetAttribute("TutorialPocket")))
		overlay:dim(pocket)
		hand:point(pocket)
		overlay:say(words(Copy.Eight, device))
	else
		lineOnly(nil)
	end
	return "game1" .. lesson .. device
end

-- The match's Rare Case on its timer (the newest Rare timer, the first win's): when it is
-- ready, or nil.
local function rareReadyAt(): number?
	local items = ItemState.items()
	local latest: number? = nil
	for _, timer in (items and items.timers) or {} do
		if timer.id == "Rare" and (latest == nil or timer.readyAt > latest) then
			latest = timer.readyAt
		end
	end
	return latest
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

-- The step after game 1 shown last, so a new one can start its own way.
local lastAfter = ""
-- The Equip step: whether the Inventory has been opened (closing it again without equipping
-- moves on: a suggestion, never a wall), and when RareDrop first found it still open.
local equipVisited = false
local inventoryLeftAt: number? = nil
local INVENTORY = "Inventory"

-- The Equip step (designer, 2026-10-03): the hand on Inventory, then the new cue's card, then
-- its Equip. The server moves on when a cue is equipped (or SkippedEquip).
local function equipScene(device: string, fresh: boolean): string
	if fresh then
		equipVisited = false
	end
	if Progression.isBusy() then
		lineOnly(nil)
		return "Equipbusy"
	end
	if not Menus.isOpen(INVENTORY) then
		if equipVisited or shownKey == "EquipSkipped" then
			if shownKey ~= "EquipSkipped" then
				Tutorial.report("SkippedEquip")
			end
			equipVisited = false
			lineOnly(nil)
			return "EquipSkipped"
		end
		local key = "EquipOpen" .. device
		pointAt("Inventory", words(Copy.EquipOpen, device), device, shownKey ~= key)
		return key
	end
	equipVisited = true
	if TutorialAnchors.showing("InventoryEquip") then
		local key = "EquipButton" .. device
		pointAt("InventoryEquip", words(Copy.EquipButton, device), device, shownKey ~= key, "Near")
		return key
	end
	local key = "EquipCard" .. device
	pointAt("InventoryCue", words(Copy.EquipCard, device), device, shownKey ~= key, "Near")
	return key
end

-- After game 1 (step 5): the two cases, then the Abilities screen.
local function afterScene(step: string, device: string): string
	arrow:show(nil)
	local fresh = step ~= lastAfter
	lastAfter = step
	local ultsOpen = Menus.isOpen(ULTS)
	if step == "Equip" then
		reveal:hide()
		return equipScene(device, fresh)
	end
	if step == "RareDrop" and Menus.isOpen(INVENTORY) then
		-- Just equipped: the Inventory stays a moment (its "Equipped" notice), then closes.
		local now = os.clock()
		local since: number = inventoryLeftAt or now
		inventoryLeftAt = since
		if now - since >= Config.Tutorial.EquipCloseSeconds then
			Menus.close(INVENTORY)
		end
		reveal:hide()
		lineOnly(nil)
		return "RareDropInventory"
	end
	inventoryLeftAt = nil
	if step == "Drop" or step == "RareDrop" then
		-- Wait for the result screen, NEW RANK! and the case opening.
		if Progression.isBusy() then
			reveal:hide()
			lineOnly(nil)
			return step .. "busy"
		end
		if step == "Drop" then
			if ItemState.caseCount(Config.Tutorial.BronzeDropTier) <= 0 then
				reveal:hide()
				lineOnly(nil)
				return "dropEmpty"
			end
			reveal:show("Drop", Config.Tutorial.BronzeDropTier, nil, function()
				Progression.openCase(Config.Tutorial.BronzeDropTier)
			end, nil)
			pointAt("OpenNow", words(Copy.Drop, device), device, fresh)
		else
			reveal:show("Rare", "Rare", rareReadyAt(), nil, function()
				Tutorial.report("RareSeen")
			end)
			pointAt("RevealOk", Copy.RareDrop, device, fresh)
		end
		return step .. device
	end
	reveal:hide()
	if step == "Abilities" then
		if ultsOpen then
			Tutorial.report("OpenedAbilities")
			lineOnly(nil)
		else
			pointAt("Abilities", words(Copy.Abilities, device), device, false)
		end
	elseif not ultsOpen then
		-- The Abilities screen closed (Back, or early): the server moves the step on.
		if fresh or shownKey ~= "closed" .. step then
			Tutorial.report("ClosedAbilities")
		end
		lineOnly(nil)
		return "closed" .. step
	elseif step == "Spin" then
		pointAt("SpinButton", words(Copy.Spin, device), device, fresh, "Near")
	elseif step == "Code" then
		if TutorialAnchors.flag("UltSpinning") then
			lineOnly(nil)
		elseif TutorialAnchors.showing("CodeBox") then
			pointAt("CodeBox", Copy.Code, device, false, "Near")
		else
			pointAt("UltOddsButton", words(Copy.CodeOdds, device), device, fresh, "Near")
		end
	elseif step == "Back" then
		if TutorialAnchors.flag("UltSpinning") then
			lineOnly(nil)
		else
			pointAt("SpinBack", words(Copy.Back, device), device, fresh, "Near")
		end
	end
	return step .. device
end

-- The real server's nudges (step 7): the menu each one opens and the anchor the hand points at.
local NUDGE_MENUS: { [string]: string } = {
	Rank = "Ranked",
	Inventory = "Inventory",
	Shop = "Shop",
	FreeReward = "Rewards",
	CaseReady = "Inventory",
}
local NUDGE_ANCHORS: { [string]: string } = {
	Rank = "Rank",
	Inventory = "Inventory",
	Shop = "Shop",
	FreeReward = "FreeReward",
	CaseReady = "Inventory",
}

-- The nudge the server names (TutorialNudge; "" while the player is at a table): the hand
-- and the light dim on its button while nothing else is up; once its menu opens the server
-- is told (Rank's is done by its claim, so the hand moves on to CLAIM). An ignored nudge
-- stays, and comes back after a match, until it is answered (designer, 2026-10-03).
local function nudgeScene(device: string): string
	arrow:show(nil)
	local name = player:GetAttribute("TutorialNudge")
	if type(name) ~= "string" or NUDGE_MENUS[name] == nil then
		lineOnly(nil)
		return "nudgeNone"
	end
	local menu = NUDGE_MENUS[name]
	if Menus.isOpen(menu) then
		if name == "Rank" then
			-- The claim block says it itself ("Rewards ready!"): the hand alone.
			local key = "nudgeClaim"
			pointAt("RankClaim", "", device, shownKey ~= key)
			return key
		end
		if shownKey ~= "nudged" .. name then
			Tutorial.report("Nudged", name)
		end
		lineOnly(nil)
		return "nudged" .. name
	end
	if Progression.isBusy() then
		lineOnly(nil)
		return "nudgeBusy"
	end
	local key = "nudge" .. name
	pointAt(NUDGE_ANCHORS[name], Copy.Nudge[name], device, shownKey ~= key)
	return key
end

-- Builds the scene for the step now (the line, the dim, the hand, the arrow). Cheap enough
-- to run every frame: each piece only changes when its input does.
local function scene(step: string, device: string): string
	if step ~= "Game1" then
		TutorialAnchors.setAimLock(nil)
		lastLesson = ""
	end
	if step == "Arrow1" or step == "Arrow2" then
		return arrowScene()
	elseif step == "Request" then
		return padScene("Request", Copy.Request, device)
	elseif step == "Queue" then
		return padScene("GlobalQueue", Copy.Queue, device)
	elseif step == "Lobby" then
		arrow:show(nil)
		local fresh = shownKey:sub(1, 5) ~= "Lobby"
		pointAt("Lobby", words(Copy.Lobby, device), device, fresh)
		return "Lobby" .. device
	elseif step == "Game1" then
		return game1Scene(device)
	elseif Steps.atLeast(step, "Drop") and not Steps.atLeast(step, "Arrow2") then
		return afterScene(step, device)
	elseif step == "Nudges" then
		return nudgeScene(device)
	end
	reveal:hide()
	lastAfter = ""
	-- Steps still to come keep the screen clear.
	arrow:show(nil)
	overlay:dim(nil)
	hand:hide()
	overlay:say(nil)
	return step
end

-- The menu open last frame: opening Shop or Abilities starts a visit of its funnel (the
-- server's Funnel; for every player, tutorial or not).
local lastMenu: string? = nil
local MENU_FUNNELS: { [string]: string } = { Shop = "ShopOpened", [ULTS] = "AbilitiesOpened" }

local function update(dt: number)
	local menu = Menus.current()
	if menu ~= lastMenu then
		lastMenu = menu
		local kind = if menu then MENU_FUNNELS[menu] else nil
		if kind then
			Tutorial.report(kind)
		end
	end
	reveal:update()
	-- The Rare Case timer beside Inventory, in the real server, while no menu or popup is up
	-- (TutorialCaseAt: when it is ready, kept by the server past the timer's end).
	local caseAt = player:GetAttribute("TutorialCaseAt")
	local showPill = Tutorial.step() == "Nudges" and not Progression.isBusy()
	pill:update(if showPill and type(caseAt) == "number" then caseAt else nil, dt)
	if not Tutorial.active() then
		shownKey = ""
		TutorialAnchors.setAimLock(nil)
		reveal:hide()
		return
	end
	shownKey = scene(Tutorial.step(), Tutorial.device())
end

local function refresh()
	refreshHidden()
	overlay:setSkip(Tutorial.active(), function()
		Tutorial.report("Skip")
	end)
	if not Tutorial.active() then
		overlay:clear()
		hand:hide()
		arrow:show(nil)
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
		end
		return true
	end
	hook.Parent = player:WaitForChild("PlayerScripts")
end

--- Builds the tutorial's layer. Call once from Main.
function Tutorial.start()
	overlay = TutorialOverlay.new()
	hand = TutorialHand.new(overlay.gui)
	arrow = TutorialArrow.new()
	reveal = TutorialReveal.new(overlay.gui)
	pill = TutorialCasePill.new(overlay.gui)
	player:GetAttributeChangedSignal("TutorialStep"):Connect(refresh)
	refresh()
	RunService.RenderStepped:Connect(update)
	startQA()
end

return Tutorial
