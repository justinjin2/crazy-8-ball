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
local Progression = require(script.Parent.Progression)
local Menus = require(script.Parent.Menus)
local LuckyClient = require(script.Parent.LuckyClient)

local Tutorial = {}

local player = Players.LocalPlayer

local overlay: TutorialOverlay.Overlay
local hand: TutorialHand.Hand
local arrow: TutorialArrow.Arrow

local ULTS = Config.UI.UltScreen.Column.Name

local Copy = Strings.Tutorial
local L = Config.Tutorial.Lessons

-- The HUD items the tutorial brings in one by one.
local ITEMS = { "Shop", "Inventory", "Abilities", "Rank", "FreeReward", "Trade" }

-- What is hidden at a step: the matchmaking bar's Play Global on the pads (MatchBar; the
-- server brings game 1's bot and starts game 2's search by itself), game 1's post-match row
-- with Leave only (the bot has jumped off: no rematch), and game 2's with Lobby only
-- (PostMatch: no rematch, no Play another).
local HOST_HIDES: { [string]: { string } } = {
	Request = { "HostGlobal" },
	Queue = { "HostGlobal" },
	Block = { "Rematch" },
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

-- The pad steps (designer, 2026-10-07: the tutorial only teaches stepping on the pad): the
-- server calls the tutorial bot (game 1) or starts the search (game 2) by itself, so there is
-- nothing to point at, only the wait.
local function padScene(): string
	arrow:show(nil)
	overlay:dim(nil)
	hand:hide()
	overlay:say(Copy.Finding)
	return "calling"
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
-- moves on: a suggestion, never a wall), and when RareBlock first found it still open.
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

-- The Block step (designer, 2026-10-04): Bronze's lucky block (BronzeBlockKind) sits in the hotbar;
-- the hand points at its slot (hold it), then at the ground (throw it), then at the block on
-- the floor (its open prompt). The server moves on once it is opened (LuckyBlockService).
local function blockScene(device: string, fresh: boolean): string
	local kind: string = Config.Tutorial.BronzeBlockKind
	local part = LuckyClient.livePart(kind)
	if part then
		-- Thrown: the hand on the block and its prompt (read each frame: it rolls).
		local target = TutorialOverlay.worldTarget(function(): Vector3?
			local now = LuckyClient.livePart(kind)
			return if now then now.Position else nil
		end, Config.Tutorial.Lessons.BlockPadPx)
		overlay:dim(target)
		hand:point(target)
		overlay:say(words(Copy.BlockOpen, device))
		return "BlockOpen" .. device
	end
	if LuckyClient.heldKind() == kind then
		overlay:dim(nil)
		if device == "gamepad" then
			hand:gesture("hold", Enum.KeyCode.ButtonR2)
		else
			hand:hide()
		end
		overlay:say(words(Copy.BlockThrow, device))
		return "BlockThrow" .. device
	end
	local slot = LuckyClient.slotOf(kind)
	if slot == nil then
		lineOnly(nil)
		return "BlockNone"
	end
	local key = "BlockHold" .. slot .. device
	pointAt("HotbarSlot" .. slot, words(Copy.BlockHold, device), device, fresh or shownKey ~= key)
	return key
end

-- The RareBlock step: the win's Rare block counts down in the hotbar; the hand points at its
-- slot, and a tap on it (LuckyClient sets BlockTapped) tells the server it was seen.
local function rareBlockScene(device: string, fresh: boolean): string
	if fresh then
		TutorialAnchors.setFlag("BlockTapped", false)
	end
	if TutorialAnchors.flag("BlockTapped") then
		if shownKey ~= "RareSeen" then
			Tutorial.report("RareSeen")
		end
		lineOnly(nil)
		return "RareSeen"
	end
	local slot = LuckyClient.slotOf("Rare", true)
	if slot == nil then
		lineOnly(nil)
		return "RareNone"
	end
	local key = "RareBlock" .. slot .. device
	pointAt("HotbarSlot" .. slot, Copy.RareBlock, device, shownKey ~= key)
	return key
end

-- After game 1 (step 5): the game-1 block, Equip, the Rare block, then the Abilities screen.
local function afterScene(step: string, device: string): string
	arrow:show(nil)
	local fresh = step ~= lastAfter
	lastAfter = step
	local ultsOpen = Menus.isOpen(ULTS)
	if step == "Equip" then
		return equipScene(device, fresh)
	end
	if step == "RareBlock" and Menus.isOpen(INVENTORY) then
		-- Just equipped: the Inventory stays a moment (its "Equipped" notice), then closes.
		local now = os.clock()
		local since: number = inventoryLeftAt or now
		inventoryLeftAt = since
		if now - since >= Config.Tutorial.EquipCloseSeconds then
			Menus.close(INVENTORY)
		end
		lineOnly(nil)
		return "RareBlockInventory"
	end
	inventoryLeftAt = nil
	if step == "Block" or step == "RareBlock" then
		-- Wait for the result screen, NEW RANK! and the reel.
		if Progression.isBusy() then
			lineOnly(nil)
			return step .. "busy"
		end
		if step == "Block" then
			return blockScene(device, fresh)
		end
		return rareBlockScene(device, fresh)
	end
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
		elseif TutorialAnchors.flag("CodeFocused") and TutorialAnchors.showing("CodeRedeem") then
			-- The box was clicked: no dim (it is typed into), the gold ring and the hand on
			-- Redeem, trusting they type RELEASE (designer, 2026-10-03).
			local target = TutorialOverlay.guiTarget("CodeRedeem")
			overlay:dim(target, false, true)
			hand:point(target)
			overlay:say(words(Copy.CodeRedeem, device), "Near")
			return "CodeRedeem" .. device
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
	FreeReward = "FreeReward",
}
local NUDGE_ANCHORS: { [string]: string } = {
	Rank = "Rank",
	Inventory = "Inventory",
	Shop = "Shop",
	FreeReward = "FreeReward",
}

-- The nudge the server names (TutorialNudge; "" while the player is at a table): the hand
-- and the light dim on its button while nothing else is up; once its menu opens the server
-- is told (Rank's is done by its claim, so the hand moves on to CLAIM). An ignored nudge
-- stays, and comes back after a match, until it is answered (designer, 2026-10-03).
local function nudgeScene(device: string): string
	arrow:show(nil)
	local name = player:GetAttribute("TutorialNudge")
	if name == "BlockReady" then
		-- The Rare block's timer has ended: the hand on its hotbar slot ("Your block is
		-- ready!"); opening it ends the tutorial (the server watches the block).
		if Progression.isBusy() then
			lineOnly(nil)
			return "nudgeBusy"
		end
		local slot = LuckyClient.slotOf("Rare")
		if slot == nil then
			lineOnly(nil)
			return "nudgeBlockNone"
		end
		local key = "nudgeBlockReady" .. slot .. device
		pointAt("HotbarSlot" .. slot, Copy.Nudge.BlockReady, device, shownKey ~= key)
		return key
	end
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
	if step ~= "Code" then
		TutorialAnchors.setFlag("CodeFocused", false)
	end
	if step ~= "Game1" then
		TutorialAnchors.setAimLock(nil)
		lastLesson = ""
	end
	if step == "Arrow1" or step == "Arrow2" then
		return arrowScene()
	elseif step == "Request" then
		return padScene()
	elseif step == "Queue" then
		return padScene()
	elseif step == "Lobby" then
		arrow:show(nil)
		local fresh = shownKey:sub(1, 5) ~= "Lobby"
		pointAt("Lobby", words(Copy.Lobby, device), device, fresh)
		return "Lobby" .. device
	elseif step == "Game1" then
		return game1Scene(device)
	elseif Steps.atLeast(step, "Block") and not Steps.atLeast(step, "Arrow2") then
		return afterScene(step, device)
	elseif step == "Nudges" then
		return nudgeScene(device)
	end
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

local function update(_dt: number)
	local menu = Menus.current()
	if menu ~= lastMenu then
		lastMenu = menu
		local kind = if menu then MENU_FUNNELS[menu] else nil
		if kind then
			Tutorial.report(kind)
		end
	end
	if not Tutorial.active() then
		shownKey = ""
		TutorialAnchors.setAimLock(nil)
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
	player:GetAttributeChangedSignal("TutorialStep"):Connect(refresh)
	refresh()
	RunService.RenderStepped:Connect(update)
	startQA()
end

return Tutorial
