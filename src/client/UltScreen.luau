--!strict
-- UltScreen: the ult spin screen (docs/prompts/ULTIMATES_PROMPT.md section 9; reference 09,
-- Untitled Boxing Game's style screen), a full menu opened through Menus ("Ults": the left
-- column's 5th tile, gamepad X in the hub, the leave reminder's button). One menu at a time,
-- Modal; B, Escape and BACK TO MENU close it. Not the white menu frame: a dark stage
-- (UltStage: the camera cuts to a hidden room with the avatar in its idle and its rarity aura)
-- with the kit's parts over it. While it is open the HUD, Roblox's touch controls and walking
-- are put away, and all come back as they were when it closes.
--
-- Layout on a computer (Config.UI.UltScreen.Full, section 9.3): top centre "CURRENT ULT:", the
-- equipped ult's icon and its name huge in its rarity colour with a thick ink outline (the two
-- centred together; the spin's cycling names bring their icons too), its description; left
-- the three slot cards (UltSlots); right the odds bars and the code box (UltOdds); bottom
-- centre LUCKY SPINS, the big gold SPIN (FREE SPIN while today's free spin is unused, SLOT
-- LOCKED greyed while the selected slot is locked) and SPINS LEFT; bottom right pity, the money
-- and the buy row (UltBuy); bottom left the red BACK TO MENU, with Fast Open's Skip and AUTO
-- SPIN beside it (UltFast). On a phone (Short, section 9.5) the slots are a compact column,
-- the odds open from an "Odds" button and the buy row from "Buy spins", each in a popup.
--
-- The server decides everything (UltRequest through UltSpinState): a spin is answered, rolled
-- and saved before anything moves here, then UltSpinAnim plays what came back (the snapshot
-- that arrives meanwhile is held until it lands, so the name is never given away). Replacing
-- an Epic or better asks first (the kit's dialog card, no dim). Codes go through the Rewards
-- service (RewardRequest "Redeem").
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Catalog = require(Shared:WaitForChild("Ults"):WaitForChild("Catalog"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local TutorialAnchors = require(script.Parent.TutorialAnchors)
local ItemState = require(script.Parent.ItemState)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local RewardsParts = require(script.Parent.RewardsParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)
local UltBuy = require(script.Parent.UltBuy)
local UltFast = require(script.Parent.UltFast)
local UltOdds = require(script.Parent.UltOdds)
local Parts = require(script.Parent.UltScreenParts)
local UltSlots = require(script.Parent.UltSlots)
local UltSpinAnim = require(script.Parent.UltSpinAnim)
local UltSpinState = require(script.Parent.UltSpinState)
local UltStage = require(script.Parent.UltStage)

local C = Config.UI.UltScreen
local K = Config.UI.Kit
local W = Strings.Ults.Screen
local SPINS = Strings.Ults.Spins
local SHOP = Strings.Menus.Shop
local CODES = Strings.Menus.Rewards
local NAME = C.Column.Name -- the Menus name ("Ults")
local FREEZE_ACTION = "8ballUltScreenFreeze"
-- The keys that walk and jump, held while the screen is open (a text box still types).
local FREEZE_KEYS = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
	Enum.KeyCode.Space,
}

local UltScreen = {}
UltScreen.__index = UltScreen

local instance: any = nil

--------------------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------------------

--- Build the screen (closed) and register it with Menus as "Ults". `screen` is the shared HUD
--- ScreenGui: the screen makes its own ScreenGui just over it (with the menus) and puts the HUD
--- away while it is open. Once per session; later calls return the same screen.
function UltScreen.start(screen: ScreenGui): any
	if instance then
		return instance
	end
	UltSpinState.start()
	local self: any = setmetatable({}, UltScreen)
	instance = self
	self.screen = screen
	self.opened = false
	self.spinning = false
	self.latest = UltSpinState.get()
	self.geo = nil :: Parts.Geo?
	self.layoutQueued = false
	self.pulse = nil :: UIAnim.Handle?
	self.dialog = nil :: MenuFrame.Dialog?
	self.saved = nil :: any

	local gui = Instance.new("ScreenGui")
	gui.Name = "UltScreen"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = screen.DisplayOrder + C.DisplayOrderAbove
	gui.Enabled = false
	gui.Parent = screen.Parent
	self.gui = gui
	-- The free part of Roblox's top bar row (right of its buttons), measured.
	local probe = Instance.new("ScreenGui")
	probe.Name = "UltScreenTopbar"
	probe.ResetOnSpawn = false
	probe.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	probe.Parent = screen.Parent
	local area = HudParts.frame(probe, "Area")
	area.Size = UDim2.fromScale(1, 1)
	self.topbar = area

	local root = HudParts.frame(gui, "Root")
	root.Size = UDim2.fromScale(1, 1)
	root.SelectionGroup = true
	root.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	root.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	self.root = root
	-- The floor: swallows presses on the stage and frees a mouse shift-lock holds (Modal).
	local floor = Parts.catcher(root, "Floor")
	floor.ZIndex = 1
	self.floor = floor
	local content = HudParts.frame(root, "Content")
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = 2
	self.content = content

	self:buildTitle(content)
	self.slots = UltSlots.new(content, {
		select = function(slot: number)
			self:select(slot)
		end,
		lock = function(slot: number, locked: boolean)
			self:lock(slot, locked)
		end,
		purchase = function(slot: number)
			self:purchaseSlot(slot)
		end,
	})
	self.oddsPopup = Parts.popup(root, "OddsPopup", W.Odds)
	self.odds = UltOdds.new(content, {
		redeem = function(text: string, done: (string, string) -> ())
			self:redeem(text, done)
		end,
		relayout = function()
			self:layout()
		end,
	})
	self.oddsButton = HudParts.candy(content, W.Odds, function()
		UISound.play("Click")
		self:layout()
		self.oddsPopup.open(self.odds:first())
	end, "Blue", "Odds")
	self.oddsButton.Name = "OddsButton"
	self.oddsButton.ZIndex = 5
	TutorialAnchors.set("UltOddsButton", self.oddsButton) -- the tutorial lane's hand (phone)
	HudParts.setMinHit(self.oddsButton, C.TouchPx)

	self.buyPopup = Parts.popup(root, "BuyPopup", W.BuySpins)
	self.buy = UltBuy.new(content, {
		buyMoney = function(pack: number)
			self:buyMoney(pack)
		end,
		buyProduct = function(key: string)
			self:buyProduct(key)
		end,
		jumpToMoney = function(gap: number)
			self:jumpToMoney(gap)
		end,
	})
	self.buy.onRelayout = function()
		self:layout()
	end
	self.buyButton = HudParts.candy(content, W.BuySpins, function()
		UISound.play("Click")
		self:openBuy()
	end, "Blue", "UltSpin")
	self.buyButton.Name = "BuySpinsButton"
	self.buyButton.ZIndex = 5
	HudParts.setMinHit(self.buyButton, C.TouchPx)

	self.fast = UltFast.new(content, root, {
		start = function(stopAt: string, lucky: boolean)
			self:autoStart(stopAt, lucky)
		end,
		stop = function()
			self:autoStop()
		end,
		geo = function(): Parts.Geo?
			return self.geo
		end,
	})
	self:buildSpin(content)
	self.back = HudParts.candy(content, W.Back, function()
		UISound.play("Click")
		Menus.close(NAME)
	end, "Red")
	self.back.Name = "Back"
	self.back.ZIndex = 5
	TutorialAnchors.set("SpinBack", self.back) -- the tutorial lane's hand
	TutorialAnchors.setProbe("UltSpinning", function(): boolean
		return self.spinning == true
	end)
	HudParts.setMinHit(self.back, C.TouchPx)
	-- Where the server's answers show: a line just over LUCKY SPINS.
	local noticeHolder = HudParts.frame(content, "Notices")
	noticeHolder.ZIndex = 20
	self.noticeHolder = noticeHolder

	self.anim = UltSpinAnim.new(root, {
		showName = function(id: string, pop: boolean)
			self:showName(id, pop)
		end,
		nameCenter = function(): Vector2
			return self.nameLabel.AbsolutePosition + self.nameLabel.AbsoluteSize / 2
		end,
		-- GUI lane (step 13): the result's tier word sat in the description's row.
		tierGone = function()
			if self.opened and not self.anim:isPlaying() and not self.descLabel.Visible then
				self.descLabel.Visible = true
				UIAnim.popIn(self.descLabel)
			end
		end,
	})
	self.stage = UltStage.new()

	UltSpinState.Changed:Connect(function(state: any)
		self:onState(state)
	end)
	UltSpinState.Auto:Connect(function(message: any)
		self:onAuto(message)
	end)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:queueLayout()
	end)
	-- Studio QA: a PreviewSize attribute (Vector2) on the ScreenGui lays the screen out in a box
	-- that size at the top left, standing in for a phone (the brief's phone-frame check).
	gui:GetAttributeChangedSignal("PreviewSize"):Connect(function()
		self:queueLayout()
	end)
	area:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:queueLayout()
	end)
	UserInputService.LastInputTypeChanged:Connect(function()
		if not self.opened then
			return
		end
		local selected = GuiService.SelectedObject
		if Parts.isGamepad() and (selected == nil or not selected:IsDescendantOf(gui)) then
			self:focus()
		end
	end)

	Menus.register(NAME, {
		open = function(_tab: string?)
			self:enter()
		end,
		close = function()
			self:leave()
		end,
		isOpen = function(): boolean
			return self.opened
		end,
		root = gui,
		ensureSelection = function()
			self:focus()
		end,
		notice = function(text: string, toneName: string?)
			self:notice(text, toneName)
		end,
	})
	return self
end

function UltScreen.buildTitle(self: any, parent: Instance)
	local current = HudParts.text(parent, "Current", C.Full.CurrentTextPx, W.Current)
	current.TextWrapped = false
	current.ZIndex = 5
	current.AnchorPoint = Vector2.new(0.5, 0)
	local name = HudParts.text(parent, "UltName", C.Full.NameTextPx, "")
	name.TextWrapped = false
	name.ZIndex = 5
	name.AnchorPoint = Vector2.new(0.5, 0)
	-- The ult's icon left of the name (placeName centres the two together).
	local icon = HudParts.icon(parent, "", "UltIcon")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Visible = false
	icon.ZIndex = 5
	self.nameIcon = icon
	self.nameRow = nil :: any -- set by layout: where the name's row is and how wide it may be
	local desc =
		HudParts.text(parent, "Description", C.Full.DescTextPx, "", HudParts.color(C.DescColor))
	desc.ZIndex = 5
	desc.AnchorPoint = Vector2.new(0.5, 0)
	local pity = HudParts.pill(parent, "PityHit", HudParts.tone("Gold"))
	pity.AnchorPoint = Vector2.new(0, 0)
	pity.ZIndex = 6
	pity.Visible = false
	local pityText = HudParts.text(pity, "Words", K.Text.Min, W.PityHit)
	pityText.TextWrapped = false
	pityText.Size = UDim2.fromScale(1, 1)
	pityText.ZIndex = 7
	self.currentLabel, self.nameLabel, self.descLabel = current, name, desc
	self.pityPill, self.pityText = pity, pityText
end

function UltScreen.buildSpin(self: any, parent: Instance)
	local lucky = HudParts.candy(parent, W.LuckySpins:format("0"), function()
		UISound.play("Click")
		self:spin(true, false)
	end, "Green", "Lucky")
	lucky.Name = "LuckySpins"
	lucky.ZIndex = 5
	HudParts.setMinHit(lucky, C.TouchPx)
	-- The green-to-teal gradient over the green candy, left to right.
	local parts = HudParts.candyParts(lucky)
	if parts then
		local tint = HudParts.frame(parts.face, "Tint")
		tint.Size = UDim2.fromScale(1, 1)
		tint.BackgroundTransparency = 0
		tint.BackgroundColor3 = Color3.new(1, 1, 1)
		HudParts.corner(tint, K.ButtonCornerPx)
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(HudParts.color(C.LuckyFrom), HudParts.color(C.LuckyTo))
		gradient.Transparency = NumberSequence.new(1, C.LuckyTintTransparency)
		gradient.Parent = tint
	end
	local spin = HudParts.candy(parent, W.Spin, function()
		UISound.play("Click")
		self:spin(false, false)
	end, "Yellow", "UltSpin")
	spin.Name = "Spin"
	spin.ZIndex = 5
	TutorialAnchors.set("SpinButton", spin) -- the tutorial lane's hand
	local left = HudParts.text(parent, "SpinsLeft", C.Full.SpinsLeftTextPx, "")
	left.AutoLocalize = false
	left.TextWrapped = false
	left.ZIndex = 5
	left.AnchorPoint = Vector2.new(0.5, 0)
	self.luckyButton, self.spinButton, self.spinsLeft = lucky, spin, left
	spin.NextSelectionUp = lucky
	lucky.NextSelectionDown = spin
end

--------------------------------------------------------------------------------------------
-- Opening and closing
--------------------------------------------------------------------------------------------

function UltScreen.isOpen(self: any): boolean
	return self.opened
end

-- Open (Menus' handle): only while the screen is live for this player.
function UltScreen.enter(self: any)
	if self.opened then
		return
	end
	local state = self.latest or UltSpinState.get()
	if type(state) ~= "table" or state.live ~= true then
		return
	end
	self.latest = state
	self.opened = true
	-- Put the HUD, Roblox's touch controls and walking away (back as they were on close).
	self.saved = {
		hud = self.screen.Enabled,
		touch = GuiService.TouchControlsEnabled,
	}
	self.screen.Enabled = false
	self.saved.others = {}
	local playerGui = self.gui.Parent
	for _, name in C.HideGuis do
		local other = playerGui and playerGui:FindFirstChild(name)
		if other and other:IsA("ScreenGui") then
			self.saved.others[other] = other.Enabled
			other.Enabled = false
		end
	end
	GuiService.TouchControlsEnabled = false
	ContextActionService:BindActionAtPriority(FREEZE_ACTION, function(): Enum.ContextActionResult
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, table.unpack(FREEZE_KEYS))
	self.gui.Enabled = true
	self.floor.Modal = true
	self.stage:open(Catalog.rarity(state.equipped))
	self:layout()
	self:draw(state)
	self.content.Visible = false
	UIAnim.popIn(self.content)
	if Parts.isGamepad() then
		self:focus()
	end
end

-- Close (Menus' handle): a spin still cycling is cut short (its result is saved already), a
-- running Auto Spin is stopped, the camera, the HUD and the controls come back.
function UltScreen.leave(self: any)
	if not self.opened then
		return
	end
	self.opened = false
	self.anim:cancel()
	self.spinning = false
	if self.dialog then
		self.dialog.cancel()
		self.dialog = nil
	end
	self.oddsPopup.close()
	self.buyPopup.close()
	self.fast:closePopup()
	if self.fast.running then
		task.spawn(UltSpinState.request, "AutoStop")
	end
	if self.pulse then
		self.pulse.stop()
		self.pulse = nil
	end
	self.pityPill.Visible = false
	self.stage:close()
	ContextActionService:UnbindAction(FREEZE_ACTION)
	local saved = self.saved
	self.saved = nil
	if saved then
		self.screen.Enabled = saved.hud
		for other, enabled in saved.others or {} do
			other.Enabled = enabled
		end
		GuiService.TouchControlsEnabled = saved.touch
	end
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(self.gui) then
		GuiService.SelectedObject = nil
	end
	self.floor.Modal = false
	self.gui.Enabled = false
end

--- Put a gamepad on SPIN.
function UltScreen.focus(self: any)
	if not self.opened then
		return
	end
	local spin: TextButton = self.spinButton
	if spin.Selectable and spin.Visible then
		GuiService.SelectedObject = spin
	else
		self.slots:focus()
	end
end

--- A short line from the server's answer, just over LUCKY SPINS ("Ink", "Red", "Green").
function UltScreen.notice(self: any, text: string, toneName: string?)
	if self.opened then
		MenuFrame.showNotice(self.noticeHolder, text, toneName)
	end
end

--------------------------------------------------------------------------------------------
-- The state
--------------------------------------------------------------------------------------------

function UltScreen.onState(self: any, state: any)
	self.latest = state
	if not self.opened then
		return
	end
	if state.live ~= true then
		Menus.close(NAME)
		return
	end
	if self.spinning then
		return -- drawn once the spin lands, so the name is never given away
	end
	self:draw(state)
end

--- Show an ult's name at the top, upper case in its rarity colour (Mythic shimmers).
function UltScreen.showName(self: any, id: string, pop: boolean)
	local label: TextLabel = self.nameLabel
	label.Text = string.upper(Catalog.name(id))
	Parts.paint(label, Catalog.rarity(id))
	self.nameIcon.Image = Catalog.icon(id)
	self:placeName()
	if pop then
		UIAnim.bounce(label)
		UIAnim.bounce(self.nameIcon)
	end
end

-- The icon and the name side by side, centred together on the name's row (from layout): the
-- name keeps its size and only shrinks when the two would be wider than the row.
function UltScreen.placeName(self: any)
	local row = self.nameRow
	if not row then
		return
	end
	local label: TextLabel = self.nameLabel
	local icon: ImageLabel = self.nameIcon
	local shown = icon.Image ~= ""
	local iconPx = if shown then row.icon else 0
	local gap = if shown then row.gap else 0
	local room = math.max(1, row.width - iconPx - gap)
	local textW = math.ceil(Parts.textWidth(label.Text, row.text)) + 2 * row.outline + 4
	local nameW = math.min(textW, room)
	local left = row.x - math.floor((iconPx + gap + nameW) / 2)
	icon.Visible = shown
	icon.Size = UDim2.fromOffset(iconPx, iconPx)
	icon.Position = UDim2.fromOffset(left, row.y + math.floor(row.height / 2))
	label.Position = UDim2.fromOffset(left + iconPx + gap + math.floor(nameW / 2), row.y)
	label.Size = UDim2.fromOffset(nameW, row.height)
end

function UltScreen.draw(self: any, state: any)
	local equipped = if type(state.equipped) == "string" and Catalog.exists(state.equipped)
		then state.equipped
		else Config.Ults.Default
	self:showName(equipped, false)
	local desc = Catalog.description(equipped)
	self.descLabel.Text = if Catalog.built(equipped) then desc else W.DescriptionSoon:format(desc)
	-- GUI lane (step 13): the result's tier word holds the row for a moment first.
	self.descLabel.Visible = not self.anim:tierShowing()
	self.stage:setRarity(Catalog.rarity(equipped), false)
	self.slots:draw(state)
	self.odds:draw(state)
	self.buy:draw(state)
	self.fast:draw(state)

	local spins = if type(state.spins) == "number" then state.spins else 0
	local luckySpins = if type(state.luckySpins) == "number" then state.luckySpins else 0
	local locked = state.spinReason == "Locked"
	local free = state.freeSpinReady == true
	local spin: TextButton = self.spinButton
	HudParts.setText(spin, if locked then W.SlotLocked elseif free then W.FreeSpin else W.Spin)
	HudParts.setTone(spin, if locked then "Grey" else "Yellow")
	HudParts.setButtonIcon(spin, if locked then "Lock" else "UltSpin")
	HudParts.setEnabled(spin, not self.spinning, self.spinning)
	self.spinsLeft.Text = W.SpinsLeft:format(Format.commas(spins))
	HudParts.setText(self.luckyButton, W.LuckySpins:format(Format.commas(luckySpins)))
	self.luckyButton.Visible = state.restricted ~= true
	HudParts.setEnabled(self.luckyButton, not self.spinning, self.spinning)
	-- FREE SPIN breathes while it waits.
	local breathe = free and not locked and not self.spinning
	if breathe and not self.pulse then
		self.pulse = UIAnim.pulse(spin)
	elseif not breathe and self.pulse then
		self.pulse.stop()
		self.pulse = nil
	end
	self:queueLayout()
end

--------------------------------------------------------------------------------------------
-- Spinning
--------------------------------------------------------------------------------------------

--- Spin into the selected slot (a Lucky Spin with `lucky`). `confirm`: the player said yes to
--- replacing an Epic or better. The server answers first; then the spin plays.
function UltScreen.spin(self: any, lucky: boolean, confirm: boolean)
	local state = self.latest
	if not self.opened or self.spinning or type(state) ~= "table" then
		return
	end
	if self.fast.running then
		self:notice(SPINS.Reasons.AutoRunning, "Ink")
		return
	end
	local can = if lucky then state.canLucky else state.canSpin
	local why = if lucky then state.luckyReason else state.spinReason
	if can ~= true and why ~= nil and why ~= "Confirm" then
		self:notice(Parts.reason(why), "Red")
		if why == "NoSpins" or why == "NoLucky" then
			self:offerBuy()
		end
		return
	end
	self.spinning = true
	HudParts.setEnabled(self.spinButton, false, true)
	HudParts.setEnabled(self.luckyButton, false, true)
	if self.pulse then
		self.pulse.stop()
		self.pulse = nil
	end
	self.pityPill.Visible = false
	local reply =
		UltSpinState.request("Spin", { lucky = lucky, confirm = if confirm then true else nil })
	if not self.opened then
		self.spinning = false
		return
	end
	if not reply.ok then
		self.spinning = false
		if self.latest then
			self:draw(self.latest)
		end
		if reply.reason == "Confirm" then
			self:askReplace(reply, lucky)
		else
			self:notice(Parts.reason(reply), "Red")
			if reply.reason == "NoSpins" or reply.reason == "NoLucky" then
				self:offerBuy()
			end
		end
		return
	end
	self.descLabel.Visible = false
	local result = { id = reply.id, rarity = reply.rarity, wasPity = reply.wasPity == true }
	self.anim:play(result, self.fast:skipping(), function(silent: boolean)
		self.spinning = false
		if not self.opened then
			return
		end
		if not silent then
			self.stage:setRarity(result.rarity, true)
			self.stage:bounce()
			if result.wasPity then
				UIAnim.popIn(self.pityPill)
			end
		end
		if self.latest then
			self:draw(self.latest)
		end
		-- SPIN was switched off while it spun: a gamepad lands back on it.
		local selected = GuiService.SelectedObject
		if Parts.isGamepad() and (selected == nil or not selected:IsDescendantOf(self.gui)) then
			self:focus()
		end
	end)
end

--- "Replace BLACK FLASH?": the kit's dialog card, no dim; the name in its rarity colour.
function UltScreen.askReplace(self: any, reply: any, lucky: boolean)
	local current = if type(reply.current) == "string" then reply.current else ""
	local title = SPINS.Reasons.Confirm:format(string.upper(Catalog.name(current)))
	local dialog = MenuFrame.ask(self.root, {
		title = title,
		text = W.ReplaceText:format(Catalog.name(current)),
		yes = W.ReplaceYes,
		no = W.ReplaceNo,
		yesTone = "Red",
		noTone = "Blue",
	}, function(yes: boolean)
		self.dialog = nil
		if yes then
			task.spawn(function()
				self:spin(lucky, true)
			end)
		end
	end)
	self.dialog = dialog
	-- The heading in the ult's rarity colour (the newest dialog layer's title).
	local layers = self.root:GetChildren()
	for index = #layers, 1, -1 do
		local layer = layers[index]
		local card = if layer.Name == "Confirm" then layer:FindFirstChild("Dialog") else nil
		local heading = card and card:FindFirstChild("Title")
		if heading and heading:IsA("TextLabel") and heading.Text == title then
			Parts.paint(heading, Catalog.rarity(current))
			break
		end
	end
end

-- Out of spins: the buy row (the popup on a phone; a gamepad lands on BUY 1).
function UltScreen.offerBuy(self: any)
	local g: Parts.Geo? = self.geo
	if g and g.short then
		self:openBuy()
	elseif Parts.isGamepad() then
		self.buy:focus()
	end
end

function UltScreen.openBuy(self: any)
	self:layout()
	local list = self.buy:buttons()
	self.buyPopup.open(list[3] or list[1])
end

--------------------------------------------------------------------------------------------
-- Slots, buying, codes, Auto Spin
--------------------------------------------------------------------------------------------

function UltScreen.select(self: any, slot: number)
	if self.spinning then
		return
	end
	task.spawn(function()
		local reply = UltSpinState.request("Select", { slot = slot })
		if not reply.ok then
			self:notice(Parts.reason(reply), "Red")
		elseif self.opened then
			UIAnim.bounce(self.nameLabel)
			UIAnim.bounce(self.nameIcon)
		end
	end)
end

function UltScreen.lock(self: any, slot: number, locked: boolean)
	task.spawn(function()
		local reply = UltSpinState.request("Lock", { slot = slot, locked = locked })
		if not reply.ok then
			self:notice(Parts.reason(reply), "Red")
		end
	end)
end

function UltScreen.purchaseSlot(self: any, slot: number)
	local state = self.latest
	local passes = if type(state) == "table" and type(state.slotPasses) == "table"
		then state.slotPasses
		else {}
	local key = passes[slot]
	if type(key) == "string" and key ~= "" then
		self:buyProduct(key)
	end
end

function UltScreen.buyProduct(self: any, key: string)
	task.spawn(function()
		local reply = UltSpinState.request("BuyProduct", { product = key })
		if reply.ok then
			self:notice(W.Prompted, "Ink")
		else
			self:notice(Parts.reason(reply), if reply.reason == "ComingSoon" then "Ink" else "Red")
		end
	end)
end

function UltScreen.buyMoney(self: any, pack: number)
	task.spawn(function()
		local reply = UltSpinState.request("BuySpins", { pack = pack, currency = "Money" })
		if reply.ok then
			UISound.play("Claim")
			self:notice(if pack == 1 then W.BoughtOne else SPINS.Bought:format(pack), "Green")
		elseif reply.reason == "NotEnoughMoney" and type(reply.need) == "number" then
			self:jumpToMoney(reply.need)
		else
			self:notice(Parts.reason(reply), "Red")
		end
	end)
end

--- "Need $X more": the Shop's Money tab (it closes this screen) with how much is missing.
function UltScreen.jumpToMoney(_self: any, gap: number)
	if Menus.open("Shop", "Money") then
		Menus.notice(SHOP.NeedNotice:format(Format.money(gap)), "Ink")
	end
end

function UltScreen.redeem(_self: any, text: string, done: (string, string) -> ())
	task.spawn(function()
		local reply = ItemState.request("RewardRequest", "Redeem", text)
		if reply.ok then
			UISound.play("Claim")
			done(CODES.Redeemed:format(RewardsParts.summary(RewardsParts.reward(reply))), "Green")
		else
			done(MenuFrame.reason(reply), "Red")
		end
	end)
end

function UltScreen.autoStart(self: any, stopAt: string, lucky: boolean)
	if self.spinning then
		return
	end
	task.spawn(function()
		local reply = UltSpinState.request("AutoStart", { stopAt = stopAt, lucky = lucky })
		if reply.ok then
			self.fast:setRunning(true, 0)
		else
			self:notice(Parts.reason(reply), "Red")
		end
	end)
end

function UltScreen.autoStop(_self: any)
	task.spawn(UltSpinState.request, "AutoStop")
end

-- Auto Spin's messages: each result shown quickly, and why it stopped.
function UltScreen.onAuto(self: any, message: any)
	if message.kind == "Spin" then
		self.fast:setRunning(true, if type(message.n) == "number" then message.n else 0)
		if self.opened and type(message.id) == "string" and Catalog.exists(message.id) then
			local rarity = Catalog.rarity(message.id) or "Common"
			self.anim:quick({ id = message.id, rarity = rarity })
			self.stage:setRarity(rarity, true)
			self.stage:bounce()
		end
	elseif message.kind == "Stop" then
		self.fast:setRunning(false, 0)
		local reason = if type(message.reason) == "string" then message.reason else "Stopped"
		local stops: { [string]: string } = SPINS.AutoStops :: any
		local words = stops[reason]
		local name = if type(message.id) == "string" then Catalog.name(message.id) else ""
		local text = if words
			then (if string.find(words, "%s", 1, true) then words:format(name) else words)
			else Parts.reason(reason)
		self:notice(text, if reason == "Reached" then "Green" else "Ink")
	end
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

function UltScreen.queueLayout(self: any)
	if self.layoutQueued then
		return
	end
	self.layoutQueued = true
	task.defer(function()
		self.layoutQueued = false
		self:layout()
	end)
end

--- Size and place everything for the screen (Full on a computer or tablet, Short on a phone).
function UltScreen.layout(self: any)
	local gui: ScreenGui = self.gui
	local size = gui.AbsoluteSize
	local preview = if RunService:IsStudio() then gui:GetAttribute("PreviewSize") else nil
	if typeof(preview) == "Vector2" then
		size = preview
		self.root.Size = UDim2.fromOffset(preview.X, preview.Y)
	else
		self.root.Size = UDim2.fromScale(1, 1)
	end
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local origin = gui.AbsolutePosition
	local area: Frame = self.topbar
	local topRow = area.AbsolutePosition.Y + area.AbsoluteSize.Y - origin.Y
	if area.AbsoluteSize.Y <= 0 then
		topRow = GuiService:GetGuiInset().Y
	end
	topRow = math.clamp(topRow, 0, size.Y / 4)
	local freeLeft = math.clamp(area.AbsolutePosition.X - origin.X, 0, size.X / 2)
	local freeRight = if area.AbsoluteSize.X > 0
		then math.clamp(freeLeft + area.AbsoluteSize.X, size.X / 2, size.X)
		else size.X
	local g = Parts.geo(size, topRow, freeLeft, freeRight)
	self.geo = g
	local W_, H = size.X, size.Y
	local m, gap = g.px("MarginPx"), g.px("GapPx")
	local cx = math.floor(W_ / 2)

	-- Bottom left: BACK TO MENU.
	local backW, backH = g.px("BackWidthPx"), g.px("BackHeightPx")
	HudParts.setButtonTextSize(self.back, g.text("BackTextPx"))
	local backY = H - m - backH
	self.back.Position = UDim2.fromOffset(m, backY)
	self.back.Size = UDim2.fromOffset(backW, backH)

	-- Bottom centre: LUCKY SPINS, SPIN, SPINS LEFT.
	local spinW, spinH = g.px("SpinWidthPx"), g.px("SpinHeightPx")
	local leftText = g.text("SpinsLeftTextPx")
	local leftH = leftText + 6
	HudParts.setTextSize(self.spinsLeft, leftText)
	self.spinsLeft.Position = UDim2.fromOffset(cx, H - m - leftH)
	self.spinsLeft.Size = UDim2.fromOffset(spinW + 2 * gap, leftH)
	local spinY = H - m - leftH - 4 - spinH
	self.spinButton.Position = UDim2.fromOffset(cx - math.floor(spinW / 2), spinY)
	self.spinButton.Size = UDim2.fromOffset(spinW, spinH)
	HudParts.setButtonTextSize(self.spinButton, g.text("SpinTextPx"))
	local luckyW, luckyH = g.px("LuckyWidthPx"), g.px("LuckyHeightPx")
	local luckyY = spinY - gap - luckyH
	self.luckyButton.Position = UDim2.fromOffset(cx - math.floor(luckyW / 2), luckyY)
	self.luckyButton.Size = UDim2.fromOffset(luckyW, luckyH)
	HudParts.setButtonTextSize(self.luckyButton, g.text("LuckyTextPx"))
	local stackTop = if self.luckyButton.Visible then luckyY else spinY
	self.noticeHolder.Position = UDim2.fromOffset(0, 0)
	self.noticeHolder.Size =
		UDim2.fromOffset(W_, math.max(1, stackTop - gap + Config.UI.Menu.Notice.BottomPx))

	-- Top centre: CURRENT ULT:, the name, the description (the skip hint in its place).
	local oddsW = g.px("OddsWidthPx")
	local openW, openH = g.px("OpenWidthPx"), g.px("OpenHeightPx")
	local sideRoom = if g.short then openW else oddsW
	local titleRoom = math.max(160, W_ - 2 * (m + sideRoom + gap))
	local rowRoom = math.max(160, 2 * (math.min(cx - g.freeLeft, g.freeRight - cx) - m))
	local y = g.px("TitleTopPx")
	local currentText = g.text("CurrentTextPx")
	HudParts.setTextSize(self.currentLabel, currentText)
	self.currentLabel.Position = UDim2.fromOffset(cx, y)
	self.currentLabel.Size = UDim2.fromOffset(math.min(titleRoom, rowRoom), currentText + 6)
	local pityW = math.ceil(Parts.textWidth(W.PityHit, K.Text.Min)) + 16
	local currentW = math.ceil(Parts.textWidth(W.Current, currentText))
	self.pityPill.Position = UDim2.fromOffset(cx + math.floor(currentW / 2) + gap, y)
	self.pityPill.Size = UDim2.fromOffset(pityW, currentText + 6)
	y += currentText + 6
	local nameText = g.text("NameTextPx")
	HudParts.setTextSize(self.nameLabel, nameText)
	Parts.setOutline(self.nameLabel, g.px("NameOutlinePx"))
	local nameH = nameText + 8
	local nameW = if y < topRow then math.min(titleRoom, rowRoom) else titleRoom
	self.nameRow = {
		x = cx,
		y = y,
		width = nameW,
		height = nameH,
		text = nameText,
		outline = g.px("NameOutlinePx"),
		icon = math.min(g.px("NameIconPx"), nameH + 2 * gap),
		gap = gap,
	}
	self:placeName()
	y += nameH
	local descText = g.text("DescTextPx")
	local descW = math.min(g.px("DescWidthPx"), titleRoom)
	HudParts.setTextSize(self.descLabel, descText)
	self.descLabel.Position = UDim2.fromOffset(cx, y)
	self.descLabel.Size = UDim2.fromOffset(descW, 2 * (descText + 4))
	self.anim:layout(Vector2.new(cx, y), descW, g.short)

	-- The right side: the odds column and the buy area (computer), or the Odds and Buy spins
	-- buttons that open them in popups (phone).
	local buyW = self.buy:width(g)
	local statusW = if g.short then math.max(openW, math.floor(buyW * 0.6)) else buyW
	local fastW = g.px("FastWidthPx")
	local popupW = math.min(g.px("PopupWidthPx"), W_ - 2 * m - 40)
	if g.short then
		-- Odds button top right under Roblox's row, Fast Open under it.
		self.oddsButton.Visible = true
		self.oddsButton.Position = UDim2.fromOffset(W_ - m - openW, topRow + 4)
		self.oddsButton.Size = UDim2.fromOffset(openW, openH)
		HudParts.setButtonTextSize(self.oddsButton, g.text("OpenTextPx"))
		self.fast:layout(g, openW)
		self.fast.holder.Position = UDim2.fromOffset(W_ - m - openW, topRow + 4 + openH + gap)
		-- The odds in their popup.
		local body = self.oddsPopup.body
		self.odds.scroll.Parent = body
		self.odds.codeCard.Parent = self.odds.scroll
		local bodyH = math.max(120, H - 2 * m - g.px("PopupClosePx") - 3 * (gap + 4) - 8)
		self.odds.scroll.Position = UDim2.fromOffset(0, 0)
		self.odds.scroll.Size = UDim2.fromOffset(popupW, bodyH)
		self.odds:layout(g, popupW, true)
		self.oddsPopup.place(popupW, bodyH, g)
		-- Buy spins bottom right, pity and money over it; the rows in their popup.
		self.buyButton.Visible = true
		local buyY = H - m - openH
		self.buyButton.Position = UDim2.fromOffset(W_ - m - openW, buyY)
		self.buyButton.Size = UDim2.fromOffset(openW, openH)
		HudParts.setButtonTextSize(self.buyButton, g.text("OpenTextPx"))
		local statusH = self.buy:layoutStatus(g, statusW)
		self.buy.status.Position = UDim2.fromOffset(W_ - m - statusW, buyY - gap - statusH)
		self.buy.rows.Parent = self.buyPopup.body
		self.buy.rows.Position = UDim2.fromOffset(0, 0)
		local rowsW = math.min(popupW, buyW + 2 * gap)
		local rowsH = self.buy:layoutRows(g, rowsW)
		self.buyPopup.place(rowsW, rowsH, g)
	else
		self.oddsButton.Visible = false
		self.buyButton.Visible = false
		if self.oddsPopup.isOpen() then
			self.oddsPopup.close()
		end
		if self.buyPopup.isOpen() then
			self.buyPopup.close()
		end
		-- The buy area bottom right: the rows, pity and money over them.
		self.buy.rows.Parent = self.content
		local rowsH = self.buy:layoutRows(g, buyW)
		local rowsY = H - m - rowsH
		self.buy.rows.Position = UDim2.fromOffset(W_ - m - buyW, rowsY)
		local statusH = self.buy:layoutStatus(g, statusW)
		local statusY = rowsY - gap - statusH
		self.buy.status.Position = UDim2.fromOffset(W_ - m - statusW, statusY)
		-- The code box on its own between the slot cards and SPIN when there is room (placed
		-- once the slots are), else under the odds.
		local stackLeft = cx - math.floor(math.max(spinW, luckyW) / 2)
		local codeRoomLeft = m + g.px("SlotWidthPx") + 2 * gap
		local codeRoom = stackLeft - 2 * gap - codeRoomLeft
		local codeOwn = codeRoom >= g.px("CodeCardMinWidthPx")
		self.odds.codeCard.Parent = if codeOwn then self.content else self.odds.scroll
		-- The odds column from the top right down to the buy area.
		local oddsTop = if g.freeRight >= W_ - m then m else topRow + m
		self.odds.scroll.Parent = self.content
		self.odds.scroll.Position = UDim2.fromOffset(W_ - m - oddsW, oddsTop)
		self.odds.scroll.Size = UDim2.fromOffset(oddsW, math.max(80, statusY - gap - oddsTop))
		self.odds:layout(g, oddsW, false)
		-- Fast Open between BACK TO MENU and SPIN, or over BACK TO MENU when that is too tight.
		local fastH = self.fast:layout(g, fastW)
		local fastX = m + backW + 2 * gap
		local spinLeft = cx - math.floor(spinW / 2)
		if fastX + fastW <= spinLeft - 2 * gap then
			self.fast.holder.Position = UDim2.fromOffset(fastX, H - m - fastH)
		else
			self.fast.holder.Position = UDim2.fromOffset(m, backY - gap - fastH)
		end
	end

	-- Left: the slot cards, between the title row and BACK TO MENU (and Fast Open over it).
	local slotsTop = topRow + m
	local slotsBottom = backY - gap
	if not g.short and self.fast.holder.Visible then
		local fastY = self.fast.holder.Position.Y.Offset
		if self.fast.holder.Position.X.Offset <= m then
			slotsBottom = fastY - gap
		end
	end
	local count = Config.Ults.Slots
	local slotsH = count * g.px("SlotHeightPx") + (count - 1) * g.px("SlotGapPx")
	local slotsY = if g.short
		then slotsTop
		else math.max(slotsTop, math.floor(slotsTop + (slotsBottom - slotsTop - slotsH) / 2))
	self.slots:layout(g, m, slotsY)

	-- The code box on its own: centred left to right between the slot cards and the SPIN
	-- stack, and top to bottom between the third card's top and SPIN's bottom (above Fast
	-- Open when that sits in the same gap).
	local card: Frame = self.odds.codeCard
	if card.Parent == self.content then
		local left = m + g.px("SlotWidthPx") + 2 * gap
		local right = cx - math.floor(math.max(spinW, luckyW) / 2) - 2 * gap
		local cardW = math.min(g.px("CodeCardWidthPx"), right - left)
		local cardH = self.odds:layoutCode(g, cardW)
		local top = slotsY + (count - 1) * (g.px("SlotHeightPx") + g.px("SlotGapPx"))
		local bottom = spinY + spinH
		local fast = self.fast.holder
		if fast.Visible and fast.Position.X.Offset > m then
			bottom = math.min(bottom, fast.Position.Y.Offset - gap)
		end
		local cardY = math.floor(top + (bottom - top - cardH) / 2)
		cardY = math.clamp(cardY, topRow + m, math.max(topRow + m, bottom - cardH))
		card.Position = UDim2.fromOffset(math.floor(left + (right - left - cardW) / 2), cardY)
	end
end

--------------------------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------------------------

--- Open the screen (through Menus, so any other menu closes first). False while it is not
--- live for this player, in a match or under a popup.
function UltScreen.open(): boolean
	return Menus.open(NAME)
end

return UltScreen
