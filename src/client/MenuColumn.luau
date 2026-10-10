--!strict
-- MenuColumn: the left column (docs/prompts/ECONOMY_UI_PROMPT.md section 5; reference
-- 06-left-menu-buttons): Shop, Inventory, Ults and Free Reward, top to bottom, one tile
-- each (Ults: docs/prompts/ULTIMATES_PROMPT.md section 9.1, the spin screen UltScreen). A
-- tile is just its glossy icon, big, with no box behind it (designer, 2026-09-28: the blue
-- candy square went so the icons could be bigger), and the word (Strings.Menus.Column) in white
-- Fredoka with an ink outline across the icon's lower edge, real text, never in the image. It
-- keeps the kit candy's behaviour with the candy's face hidden: hover and gamepad selection
-- grow it a little; a press squishes and bounces it (UIAnim) with the Click sound, and opens
-- its menu (onPress).
--
-- Red dots, top right of a tile: Inventory (the CUES tile) shows how many owned cues are NEW
-- ("9+" past Config.UI.Menu.Column.DotMax; concept 2, 2026-10-08), or "!" while an Index
-- row's reward waits (the Cues menu's Index claims it); Free Reward shows "!" while the
-- RewardState says something can be claimed (`ready`: the day, a playtime gift, the group);
-- Shop shows a small
-- gold timer pill ("23:59:12", "6d 4h") while the VIP welcome offer or the Starter Pack window
-- is open (ItemState.offerEndsAt; nothing while unknown); Trade shows nothing; Ults shows "!"
-- while today's free ult spin is unused (the UltFreeSpin attribute).
--
-- The Ults tile shows only while the spin screen is live for this player (UltState.live:
-- Config.Ults.ScreenLive, Studio, or the developer flag); the column closes up without it.
--
-- Where: on a phone it starts just under the rank HUD's badge (which hangs below Roblox's 58 px
-- top row) and ends well above the money HUD; on a bigger screen it is centred on the left
-- edge. Both are measured from the rank and money HUDs' real positions (their Config sizes
-- until they have one), and a screen too short for it shrinks it. The host card sits on the
-- right, so the two never meet. Sizes in Config.UI.Menu.Column.
--
-- Gamepad (overnight assumption, 2026-09-28): a selected GUI button takes the left stick from
-- walking, so the tiles are never selectable; in the hub the D-pad opens them instead (up Shop,
-- right Inventory, down Free Reward, left the player list: Progression.padRoute), and while a
-- gamepad is the
-- last input each tile shows its D-pad glyph (Roblox's own, so it matches the controller). The
-- D-pad's four directions are taken, so Ults is gamepad X (Config.UI.UltScreen.Column.PadKey;
-- overnight assumption, 2026-09-28: X is the ult button in a match, so X means "ult"
-- everywhere). The column listens for it itself, only while the D-pad route is live.
--
-- Hidden until the save loads, in a match, and while the result screen, NEW RANK!, a lucky
-- block's reel or the teleport screen is up (Progression.update calls setVisible every frame).
--
-- GUI lane (designer 2026-10-03, C2): the tiles are Shop, Inventory, Abilities and Free Reward
-- (Config order). Rewards and Trade left the column. Free Reward is always there since the
-- Rewards menu was merged into it (designer's picks, 2026-10-08); turning gold rays stand
-- behind it while something can be claimed.
-- Hovering a tile (or a gamepad resting on it) sways it a little, as every candy does, and sun
-- rays fade in behind its icon (designer, 2026-10-03: no hard shake).
--
-- The CUES tile's icon is alive (CuesStrike, concept 2b, 2026-10-08): the Classic Cue with a
-- breathing glow and twinkles; a hover strikes a ball with it, a press (from the touch) or the
-- D-pad route strikes harder.
--
-- A pressed tile lingers (designer, 2026-10-09): its menu hides the HUD at once (HudFocus), so
-- the tile moves into its own ScreenGui (MenuColumnLinger, kept by the focus) at the same spot
-- and size, stays there over the blur for Column.LingerSeconds playing its press (the CUES
-- strike), pops out, and goes home to the column.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local CuesStrike = require(script.Parent.CuesStrike)
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local LuckyClient = require(script.Parent.LuckyClient)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)
local UltSpinState = require(script.Parent.UltSpinState)
local TutorialAnchors = require(script.Parent.TutorialAnchors)

local C = Config.UI.Menu.Column
local S = Config.Multiplayer.Style
local K = Config.UI.Kit
local RANK = Config.UI.Progress.RankHud
local MONEY = Config.UI.Progress.MoneyHud
local WORDS: { [string]: string } = table.clone(Strings.Menus.Column :: any)
local COPY = Strings.Menus
local ULTS = Config.UI.UltScreen.Column.Name -- the spin screen's tile ("Ults"), last
local ORDER: { string } = table.clone(C.Order)
-- The tutorial lane's names for the tiles (TutorialAnchors): the tile -> the item.
local TUTORIAL_ITEMS: { [string]: string } = {
	Shop = "Shop",
	Inventory = "Inventory",
	FreeReward = "FreeReward",
	Trade = "Trade",
	[ULTS] = "Abilities",
}
if not table.find(ORDER, ULTS) then
	table.insert(ORDER, ULTS)
end
local PAD_KEYS: { [string]: string } = table.clone(C.PadKeys :: any)
PAD_KEYS[ULTS] = PAD_KEYS[ULTS] or Config.UI.UltScreen.Column.PadKey
WORDS[ULTS] = WORDS[ULTS] or Strings.Ults.Screen.Column
local ULT_KEY: Enum.KeyCode? = nil
do
	local ok, code = pcall(function()
		return (Enum.KeyCode :: any)[Config.UI.UltScreen.Column.PadKey]
	end)
	if ok and typeof(code) == "EnumItem" then
		ULT_KEY = code :: Enum.KeyCode
	end
end
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
-- The tiles' words (Config): drawn in WORD_FONT, measured with WORD_MEASURE.
local WORD_FONT = Font.new(C.LabelFont.Family, (Enum.FontWeight :: any)[C.LabelFont.Weight])
local WORD_MEASURE: Enum.Font = (Enum.Font :: any)[C.LabelFont.Measure]
local FREE = "FreeReward" -- the Free Reward tile (GUI lane)

type Tile = {
	name: string,
	rays: ImageLabel?, -- Free Reward's turning rays
	button: TextButton,
	body: Frame, -- the candy's body: everything on the tile squishes and grows with it
	icon: ImageLabel,
	strike: CuesStrike.Strike?, -- the CUES tile's striking cue
	word: TextLabel,
	dot: Frame,
	dotText: TextLabel,
	timer: Frame?,
	timerText: TextLabel?,
	glyph: ImageLabel,
}

export type Options = {
	rankHud: any?, -- RankHud (its `holder`): the column starts under it on a phone
	money: any?, -- MoneyHud (its `root`): the column always ends above it
	onPress: (name: string) -> (), -- a tile was pressed: open its menu (Menus.open)
	shopNew: (() -> number)?, -- the Shop's groups with something new (its red dot)
}

local MenuColumn = {}
MenuColumn.__index = MenuColumn

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function isGamepad(): boolean
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

-- "23:59:12" under a day, "6d 4h" from a day.
local function timeLeft(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= C.DaysFromSeconds then
		return COPY.TimeDays:format(s // 86400, (s % 86400) // 3600)
	end
	return COPY.TimeHours:format(s // 3600, (s % 3600) // 60, s % 60)
end

--- Build the column into `screen` (the shared HUD ScreenGui), hidden until the save loads.
function MenuColumn.new(screen: ScreenGui, opts: Options): any
	local self: any = setmetatable({}, MenuColumn)
	self.screen = screen
	self.rankHud = opts.rankHud
	self.money = opts.money
	self.onPress = opts.onPress
	self.opts = opts
	self.alive = true
	self.wanted = false -- Progression's say (the hub, no popup up)
	self.loaded = false -- the save is in (DataLoaded)
	self.showing = false
	self.routeLive = false -- the D-pad route opens menus now (no menu open)
	self.layoutQueued = false
	self.connections = {} :: { RBXScriptConnection }
	self.tiles = {} :: { [string]: Tile }
	self.freshTiles = {} :: { [string]: boolean } -- the soft part's click-once "!" (setFresh)

	-- The root holds the fit (a UIScale for a short screen); the body inside pops in and out.
	local root = HudParts.frame(screen, "MenuColumn")
	root.ZIndex = C.ZIndex
	self.root = root
	-- The hover rays' layer, under the column (UIAnim.sunRays places them by screen pixels).
	local raysLayer = HudParts.frame(screen, "MenuColumnRays")
	raysLayer.Size = UDim2.fromScale(1, 1)
	raysLayer.ZIndex = C.ZIndex - 1
	self.raysLayer = raysLayer
	TutorialAnchors.set("ColumnRays", raysLayer) -- the soft part's glows go under the column too
	local fit = Instance.new("UIScale")
	fit.Name = "Fit"
	fit.Parent = root
	self.fit = fit
	local body = HudParts.frame(root, "Body")
	body.Size = UDim2.fromScale(1, 1)
	body.Visible = false
	self.body = body

	for index, name in ORDER do
		self.tiles[name] = self:buildTile(body, name, index)
	end

	local function connect(signal: RBXScriptSignal, handler: (...any) -> ())
		table.insert(self.connections, signal:Connect(handler))
	end
	local function queueLayout()
		self:queueLayout()
	end
	connect(screen:GetPropertyChangedSignal("AbsoluteSize"), queueLayout)
	connect(screen:GetPropertyChangedSignal("AbsolutePosition"), queueLayout)
	local holder = self:rankHolder()
	if holder then
		connect(holder:GetPropertyChangedSignal("AbsoluteSize"), queueLayout)
		connect(holder:GetPropertyChangedSignal("AbsolutePosition"), queueLayout)
	end
	local moneyRoot = self:moneyRoot()
	if moneyRoot then
		connect(moneyRoot:GetPropertyChangedSignal("AbsoluteSize"), queueLayout)
		connect(moneyRoot:GetPropertyChangedSignal("AbsolutePosition"), queueLayout)
		-- The VIP tag and the luck's clover over the money pill (VipTag, LuckClover): the
		-- column keeps above them too.
		for _, name in { "VipTag", "LuckClover" } do
			local tag = moneyRoot:FindFirstChild(name)
			if tag and tag:IsA("GuiObject") then
				connect(tag:GetPropertyChangedSignal("Visible"), queueLayout)
			end
		end
	end
	connect(UserInputService.LastInputTypeChanged, function()
		self:refreshGlyphs()
	end)
	connect(UserInputService.GamepadConnected, function()
		self:refreshGlyphs()
	end)
	local player = Players.LocalPlayer
	if player then
		connect(player:GetAttributeChangedSignal("UltFreeSpin"), function()
			self:refreshDots()
		end)
		connect(player:GetAttributeChangedSignal("DataLoaded"), function()
			self.loaded = player:GetAttribute("DataLoaded") == true
			self:refreshVisible()
		end)
		self.loaded = player:GetAttribute("DataLoaded") == true
	else
		self.loaded = true -- an Edit-mode preview: no save
	end
	connect(ItemState.Changed.Items, function()
		self:refreshDots()
	end)
	connect(ItemState.Changed.Rewards, function()
		self:refreshFree()
	end)
	connect(ItemState.Changed.Shop, function()
		self:refreshTimer()
		self:refreshDots()
	end)
	-- The Ults tile follows whether the spin screen is live; gamepad X opens it in the hub.
	UltSpinState.start()
	connect(UltSpinState.Changed, function()
		self:refreshUlts()
	end)
	-- The tutorial lane: the tutorial brings the tiles in one by one, and its hand finds them.
	for name, item in TUTORIAL_ITEMS do
		local t: Tile? = self.tiles[name]
		if t then
			TutorialAnchors.set(item, t.button)
		end
	end
	connect(TutorialAnchors.Changed, function()
		self:refreshUlts()
	end)
	connect(UserInputService.InputBegan, function(input: InputObject, processed: boolean)
		if processed or ULT_KEY == nil or input.KeyCode ~= ULT_KEY then
			return
		end
		if not self.routeLive or not self.showing or not self:ultsShown() then
			return
		end
		if UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		self:press(ULTS)
	end)
	-- The Shop's timer counts down while the column shows.
	task.spawn(function()
		while self.alive do
			task.wait(C.TimerRefreshSeconds)
			if self.alive and self.showing then
				self:refreshTimer()
			end
		end
	end)
	-- Studio only (GuiQA "cuesStrike"): play the CUES tile's strike, `hard` as a press; with
	-- `at` (seconds) hold it at that moment for a screenshot (a negative `at`: back to rest).
	GuiQA.add("cuesStrike", function(hard: boolean?, at: number?)
		local t: Tile? = self.tiles.Inventory
		local strike: any = if t then t.strike else nil
		if strike then
			local kind = if hard then "Press" else "Hover"
			if at then
				strike:freeze(if at >= 0 then kind else nil, math.max(0, at))
			else
				strike:play(kind)
			end
		end
		return strike ~= nil
	end)
	self:refreshUlts()
	self:refreshFree()
	self:layout()
	self:refreshDots()
	self:refreshTimer()
	self:refreshGlyphs()
	self:refreshVisible()
	self.built = true -- from here a tile the tutorial reveals pops in
	return self
end

--- Whether the Ults tile shows (the spin screen is live for this player).
function MenuColumn.ultsShown(self: any): boolean
	local t: Tile? = self.tiles[ULTS]
	return t ~= nil and t.button.Visible
end

--- Show the Ults tile only while the spin screen is live for this player; the column closes up
--- round it.
function MenuColumn.refreshUlts(self: any)
	local t: Tile? = self.tiles[ULTS]
	if not t then
		return
	end
	local live = UltSpinState.isLive() and not TutorialAnchors.hidden(TUTORIAL_ITEMS[ULTS])
	local changed = false
	-- A tile the tutorial brings back pops in (a small HUD piece's entrance); on load it just
	-- shows.
	local function setShown(button: GuiObject, show: boolean)
		if show and self.built then
			UIAnim.popIn(button)
		else
			button.Visible = show
		end
	end
	if t.button.Visible ~= live then
		setShown(t.button, live)
		changed = true
	end
	-- The tutorial lane: the other tiles hide while the tutorial hides them.
	for name, item in TUTORIAL_ITEMS do
		local other: Tile? = self.tiles[name]
		if other and name ~= ULTS then
			local show = not TutorialAnchors.hidden(item)
			if other.button.Visible ~= show then
				setShown(other.button, show)
				changed = true
			end
		end
	end
	if changed then
		self:queueLayout()
		self:refreshDots()
	end
end

--- Free Reward's turning rays while the RewardState says something can be claimed.
function MenuColumn.refreshFree(self: any)
	local t: Tile? = self.tiles[FREE]
	if not t then
		return
	end
	local state = ItemState.rewards()
	local ready = type(state) == "table" and state.ready == true
	local rays = t.rays
	if rays then
		rays.Visible = ready
	end
	if ready and not self.freeLoop then
		-- Only the rays turn (a turn is smooth; a GUI move steps in whole pixels).
		self.freeLoop = UIAnim.loop(t.icon, function(clock: number)
			if rays then
				rays.Rotation = (clock * K.Motion.RaysDegreesPerSecond) % 360
			end
		end)
	elseif not ready and self.freeLoop then
		self.freeLoop.stop()
		self.freeLoop = nil
	end
	self:refreshDots()
end

--- Whether the Free Reward tile is up.
function MenuColumn.freeShown(self: any): boolean
	local t: Tile? = self.tiles[FREE]
	return t ~= nil and t.button.Visible
end

-- The tiles showing, in their order.
function MenuColumn.shownOrder(self: any): { string }
	local list: { string } = {}
	for _, name in ORDER do
		local t: Tile? = self.tiles[name]
		if t and t.button.Visible then
			table.insert(list, name)
		end
	end
	return list
end

-- One tile: a kit candy for its hover, squish and bounce, with its face (the box, outline and
-- words) hidden; then our icon, word, red dot, timer (the Shop) and D-pad glyph on its body.
function MenuColumn.buildTile(self: any, parent: Instance, name: string, index: number): Tile
	local button = HudParts.candy(parent, "", function()
		self:press(name)
	end, "Blue", nil)
	button.Name = name
	button.LayoutOrder = index
	-- Each tile draws over the one under it: a word on an icon's lower edge (the "y" of
	-- Inventory) reaches into the next tile's room, and the next tile's red dot hid it.
	button.ZIndex = #ORDER - index + 1
	-- Never a gamepad stop: a selected button would take the left stick from walking.
	button.Selectable = false
	local parts = HudParts.candyParts(button)
	parts.face.Visible = false
	local body: Frame = parts.body
	local icon = HudParts.icon(body, name, "Art")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.ZIndex = 3
	local strike: CuesStrike.Strike? = nil
	if name == "Inventory" and CuesStrike.ready() then
		local s = CuesStrike.new(icon, body)
		strike = s
		-- From the touch (a mouse button or a finger), so it shows before the menu opens.
		button.InputBegan:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				s:play("Press")
			end
		end)
	end
	local rays: ImageLabel? = nil
	if name == FREE then
		local r = Instance.new("ImageLabel")
		r.Name = "Rays"
		r.BackgroundTransparency = 1
		r.Image = K.Art.Rays
		r.ImageColor3 = HudParts.tone("Gold")
		r.ImageTransparency = C.FreeRaysTransparency
		r.AnchorPoint = Vector2.new(0.5, 0.5)
		r.ZIndex = 2
		r.Parent = body
		rays = r
	end
	-- Hover (or a gamepad resting on it): sun rays behind the icon, on a layer under the whole
	-- column so they never cover another tile's dot or words.
	HudParts.onLit(button, function(lit: boolean)
		UIAnim.sunRays(icon, lit, self.raysLayer)
		if lit and strike then
			strike:play("Hover")
		end
	end)
	local word = HudParts.text(body, "Word", C.LabelTextPx, WORDS[name] or name)
	word.TextWrapped = false
	word.FontFace = WORD_FONT
	word.AnchorPoint = Vector2.new(0.5, 0.5)
	word.ZIndex = 4
	local dot = HudParts.pill(body, "Dot", HudParts.tone("Red"))
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.ZIndex = 5
	dot.Visible = false
	local dotText = HudParts.text(dot, "Count", C.DotTextPx, "")
	dotText.AutoLocalize = false -- a number
	dotText.TextWrapped = false
	dotText.Size = UDim2.fromScale(1, 1)
	dotText.ZIndex = 6
	local timer: Frame?, timerText: TextLabel? = nil, nil
	if name == "Shop" then
		local pill = HudParts.pill(body, "Timer", HudParts.tone("Gold"))
		pill.AnchorPoint = Vector2.new(C.TimerOverTileShare, 0.5)
		pill.ZIndex = 5
		pill.Visible = false
		local words = HudParts.text(pill, "Time", C.TimerTextPx, "")
		words.AutoLocalize = false -- a time
		words.TextWrapped = false
		words.Size = UDim2.fromScale(1, 1)
		words.ZIndex = 6
		timer, timerText = pill, words
	end
	local glyph = Instance.new("ImageLabel")
	glyph.Name = "PadGlyph"
	glyph.BackgroundTransparency = 1
	glyph.ScaleType = Enum.ScaleType.Fit
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.ZIndex = 5
	glyph.Visible = false
	glyph.Parent = body
	return {
		name = name,
		rays = rays,
		button = button,
		body = body,
		icon = icon,
		strike = strike,
		word = word,
		dot = dot,
		dotText = dotText,
		timer = timer,
		timerText = timerText,
		glyph = glyph,
	}
end

function MenuColumn.rankHolder(self: any): GuiObject?
	local hud = self.rankHud
	local holder = if type(hud) == "table" then hud.holder else nil
	return if typeof(holder) == "Instance" and holder:IsA("GuiObject") then holder else nil
end

function MenuColumn.moneyRoot(self: any): GuiObject?
	local hud = self.money
	local root = if type(hud) == "table" then hud.root else nil
	return if typeof(root) == "Instance" and root:IsA("GuiObject") then root else nil
end

function MenuColumn.queueLayout(self: any)
	if self.layoutQueued then
		return
	end
	self.layoutQueued = true
	task.defer(function()
		self.layoutQueued = false
		if self.alive then
			self:layout()
		end
	end)
end

-- The rank HUD's lowest edge in the screen's pixels: measured, or from its Config size (it
-- hangs from the very top of the screen, over Roblox's top bar row).
function MenuColumn.rankBottom(self: any, origin: Vector2, short: boolean): number
	local holder = self:rankHolder()
	if holder and holder.AbsoluteSize.Y > 0 then
		return holder.AbsolutePosition.Y + holder.AbsoluteSize.Y - origin.Y
	end
	local badge = RANK.BadgePx * (if short then 1 else RANK.ComputerScale)
	return math.max(0, badge + RANK.TopMinPx - GuiService:GetGuiInset().Y)
end

-- The money HUD's top edge in the screen's pixels (the VIP tag's or the luck's clover's while
-- one shows over it): measured, or from its Config size.
function MenuColumn.moneyTop(self: any, origin: Vector2, size: Vector2, short: boolean): number
	local root = self:moneyRoot()
	if root and root.AbsoluteSize.Y > 0 then
		local top = root.AbsolutePosition.Y
		for _, name in { "VipTag", "LuckClover" } do
			local tag = root:FindFirstChild(name)
			if tag and tag:IsA("GuiObject") and tag.Visible and tag.AbsoluteSize.Y > 0 then
				top = math.min(top, tag.AbsolutePosition.Y)
			end
		end
		return top - origin.Y
	end
	local margin = if short then MONEY.ShortMarginPx else MONEY.MarginPx
	local icon = if short then MONEY.ShortIconSizePx else MONEY.IconSizePx
	return size.Y - margin - icon
end

--- Size and place the column: its tiles for a phone or a computer, under the rank HUD on a
--- phone or centred on the left edge, never over the rank or money HUDs.
function MenuColumn.layout(self: any)
	local screen: ScreenGui = self.screen
	local size = screen.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local short = size.Y < S.ShortHeight
	local tile = if short then C.ShortTilePx else C.TilePx
	local gap = if short then C.ShortGapPx else C.GapPx
	local margin = if short then C.ShortMarginPx else C.MarginPx
	local textPx = if short then C.ShortLabelTextPx else C.LabelTextPx
	local dotPx = if short then C.ShortDotPx else C.DotPx
	local timerPx = if short then C.ShortTimerPx else C.TimerPx
	local glyphPx = if short then C.ShortGlyphPx else C.GlyphPx
	local tiles = self:shownOrder()
	local count = #tiles
	local height = count * tile + (count - 1) * gap

	-- The words may be wider than a tile (they overhang both sides): the widest sets the room.
	local widest = 0
	for _, name in tiles do
		local words = WORDS[name] or name
		widest = math.max(
			widest,
			TextService:GetTextSize(words, textPx, WORD_MEASURE, Vector2.new(2000, 200)).X
		)
	end
	local labelW = math.clamp(math.ceil(widest) + 8, tile, round(tile * C.LabelMaxShare))
	local over = math.max(0, round((labelW - tile) / 2))
	local width = tile + 2 * over

	-- Between the rank HUD and the money HUD.
	local origin = screen.AbsolutePosition
	local minTop = self:rankBottom(origin, short) + C.BelowRankPx
	local maxBottom = self:moneyTop(origin, size, short) - C.AboveMoneyPx
	local scale = math.clamp((maxBottom - minTop) / height, C.MinScale, 1)
	local shown = height * scale
	local top = if short then minTop else round((size.Y - shown) / 2)
	top = math.clamp(top, minTop, math.max(minTop, maxBottom - shown))
	self.fit.Scale = scale
	self.root.Position = UDim2.fromOffset(margin, round(top))
	self.root.Size = UDim2.fromOffset(width, height)

	for index, name in tiles do
		local t: Tile = self.tiles[name]
		t.button.Position = UDim2.fromOffset(over, (index - 1) * (tile + gap))
		t.button.Size = UDim2.fromOffset(tile, tile)
		local iconSize = round(tile * C.IconShare)
		t.icon.Size = UDim2.fromOffset(iconSize, iconSize)
		t.icon.Position = UDim2.fromOffset(round(tile / 2), round(tile * C.IconCentreShare))
		local strike = t.strike
		if strike then
			strike:layout(iconSize, Vector2.new(round(tile / 2), round(tile * C.IconCentreShare)))
		end
		local rays = t.rays
		if rays then
			local raysPx = round(tile * C.FreeRaysShare)
			rays.Size = UDim2.fromOffset(raysPx, raysPx)
			rays.Position = t.icon.Position
		end
		HudParts.setTextSize(t.word, textPx)
		t.word.Size = UDim2.fromOffset(labelW, textPx + 6)
		t.word.Position = UDim2.fromOffset(round(tile / 2), round(tile * C.LabelCentreShare))
		t.dot.Position = UDim2.fromOffset(tile - C.DotInsetPx, C.DotInsetPx)
		HudParts.setTextSize(t.dotText, C.DotTextPx)
		self:sizeDot(t, dotPx)
		local timer = t.timer
		if timer then
			timer.Position = UDim2.fromOffset(tile, C.DotInsetPx)
			self:sizeTimer(t, timerPx)
		end
		t.glyph.Size = UDim2.fromOffset(glyphPx, glyphPx)
		t.glyph.Position = UDim2.fromOffset(C.GlyphInsetPx, C.GlyphInsetPx)
	end
	self.dotPx, self.timerPx = dotPx, timerPx
	self:placeShopDot()
end

-- The Shop's dot sits in its top-right corner, or just under the timer pill while that is up
-- (the soft part's click-once "!" shows with the timer).
function MenuColumn.placeShopDot(self: any)
	local t: Tile = self.tiles.Shop
	local below = if t.timer and t.timer.Visible then self.timerPx or C.TimerPx else 0
	t.dot.Position = UDim2.fromOffset(t.button.Size.X.Offset - C.DotInsetPx, C.DotInsetPx + below)
end

-- The dot is round for one character and widens for "9+".
function MenuColumn.sizeDot(_self: any, t: Tile, dotPx: number)
	local words =
		TextService:GetTextSize(t.dotText.Text, C.DotTextPx, FONT, Vector2.new(200, 100)).X
	t.dot.Size = UDim2.fromOffset(math.max(dotPx, math.ceil(words) + 10), dotPx)
end

function MenuColumn.sizeTimer(_self: any, t: Tile, timerPx: number)
	local timer, words = t.timer, t.timerText
	if not timer or not words then
		return
	end
	local width = TextService:GetTextSize(words.Text, C.TimerTextPx, FONT, Vector2.new(400, 100)).X
	timer.Size = UDim2.fromOffset(math.max(timerPx * 2, math.ceil(width) + 14), timerPx)
end

--------------------------------------------------------------------------------------------
-- Red dots, the Shop's timer, the D-pad glyphs
--------------------------------------------------------------------------------------------

local function setDot(self: any, t: Tile, text: string?)
	local show = text ~= nil and text ~= ""
	if show and t.dotText.Text ~= text then
		t.dotText.Text = text :: string
		self:sizeDot(t, self.dotPx or C.DotPx)
		if t.dot.Visible then
			UIAnim.bounce(t.dot)
		end
	end
	if show ~= t.dot.Visible then
		if show then
			UIAnim.popIn(t.dot)
		else
			t.dot.Visible = false
		end
	end
end

-- How many owned cues are NEW in the snapshot (0 before it).
local function newCues(): number
	local items = ItemState.items()
	local rows = if type(items) == "table" and type(items.cues) == "table" then items.cues else {}
	local n = 0
	for _, row in rows do
		if type(row) == "table" and row.new == true then
			n += 1
		end
	end
	return n
end

--- Read the red dots again: the NEW cues on CUES (else "!" while an Index row's reward
--- waits), "!" on Free Reward while something can be claimed, "!" on Ults while today's free
--- ult spin is unused.
function MenuColumn.refreshDots(self: any)
	local fresh = newCues()
	-- A cue won from a lucky block counts once its reel and reveal are over (the count would
	-- tell what the reel lands on; the designer, 2026-10-09). Read again when the opening ends.
	local shown = self.shownNew or 0
	if fresh > shown and LuckyClient.busy() then
		fresh = shown
		if not self.newWaiting then
			self.newWaiting = true
			task.spawn(function()
				while LuckyClient.busy() do
					task.wait(C.NewWaitSeconds)
				end
				self.newWaiting = false
				self:refreshDots()
			end)
		end
	end
	self.shownNew = fresh
	-- A tile with nothing else to say wears the soft part's click-once "!" (setFresh).
	local function orNew(name: string, text: string?): string?
		return text or (if self.freshTiles[name] then COPY.DotReady else nil)
	end
	setDot(
		self,
		self.tiles.Inventory,
		orNew(
			"Inventory",
			if fresh > C.DotMax
				then COPY.DotMore:format(C.DotMax)
				elseif fresh > 0 then tostring(fresh)
				elseif ItemState.indexReady() then COPY.DotReady
				else nil
		)
	)
	local freeTile: Tile? = self.tiles[FREE]
	if freeTile then
		local state = ItemState.rewards()
		local ready = type(state) == "table" and state.ready == true
		setDot(self, freeTile, orNew(FREE, if ready then COPY.DotReady else nil))
	end
	-- The Shop: how many of its jump groups hold something new (a restock, an offer), while
	-- its offer timer pill is not up in the same corner.
	local shopNew = if self.opts.shopNew then self.opts.shopNew() else 0
	local shopTile: Tile = self.tiles.Shop
	local timerUp = shopTile.timer ~= nil and shopTile.timer.Visible
	setDot(
		self,
		shopTile,
		orNew(
			"Shop",
			if shopNew > 0 and not timerUp then tostring(math.min(shopNew, C.DotMax)) else nil
		)
	)
	local ults: Tile? = self.tiles[ULTS]
	if ults then
		local free = UltSpinState.freeSpinReady() and UltSpinState.isLive()
		setDot(self, ults, if free then COPY.DotReady else nil)
	end
end

--- The soft part's click-once "!" on tile `name` (TutorialSoft), shown while the tile has no
--- other dot.
function MenuColumn.setFresh(self: any, name: string, on: boolean)
	if (self.freshTiles[name] == true) == on then
		return
	end
	self.freshTiles[name] = if on then true else nil
	self:refreshDots()
end

--- The Shop's timer pill: the time left in an open offer window, hidden when none is open.
function MenuColumn.refreshTimer(self: any)
	local t: Tile = self.tiles.Shop
	local timer, words = t.timer, t.timerText
	if not timer or not words then
		return
	end
	local now = workspace:GetServerTimeNow()
	local ends = ItemState.offerEndsAt(now)
	if not ends then
		if timer.Visible then
			timer.Visible = false
			self:placeShopDot()
		end
		return
	end
	local text = timeLeft(ends - now)
	if words.Text ~= text then
		local longer = #words.Text ~= #text
		words.Text = text
		if longer then
			self:sizeTimer(t, self.timerPx or C.TimerPx)
		end
	end
	if not timer.Visible then
		UIAnim.popIn(timer)
		self:placeShopDot()
	end
end

--- Roblox's own D-pad pictures (PlayStation or Xbox), shown while a gamepad is the last input
--- and the D-pad route is live.
function MenuColumn.refreshGlyphs(self: any)
	local show = isGamepad() and self.routeLive
	for name, t in self.tiles do
		local keyName = PAD_KEYS[name]
		local image = ""
		if show and keyName then
			local ok, found = pcall(function()
				return UserInputService:GetImageForKeyCode((Enum.KeyCode :: any)[keyName])
			end)
			image = if ok and type(found) == "string" then found else ""
		end
		t.glyph.Image = image
		t.glyph.Visible = show and image ~= ""
	end
end

--- Whether the D-pad opens menus right now (Progression: the hub, no menu open); the glyphs
--- show only then.
function MenuColumn.setPadRoute(self: any, live: boolean)
	if self.routeLive == live then
		return
	end
	self.routeLive = live
	self:refreshGlyphs()
end

--------------------------------------------------------------------------------------------
-- Showing, pressing
--------------------------------------------------------------------------------------------

function MenuColumn.refreshVisible(self: any)
	local show = self.wanted and self.loaded
	if show == self.showing then
		return
	end
	self.showing = show
	if show then
		self:layout()
		self:refreshDots()
		self:refreshTimer()
		UIAnim.popIn(self.body)
	else
		UIAnim.popOut(self.body)
	end
end

--- Show or hide the column (Progression: hidden in a match and under the popups). It pops in
--- and out, and stays hidden until the save is loaded. Cheap to call every frame.
function MenuColumn.setVisible(self: any, visible: boolean)
	if self.wanted == visible then
		return
	end
	self.wanted = visible
	self:refreshVisible()
end

function MenuColumn.isShown(self: any): boolean
	return self.showing
end

--- Press a tile as a tap would (the D-pad route): it bounces, clicks and opens its menu.
function MenuColumn.press(self: any, name: string)
	local t: Tile? = self.tiles[name]
	if not t or not self.showing then
		return
	end
	UISound.play("Click")
	UIAnim.bounce(t.button)
	local strike = t.strike
	if strike then
		strike:play("Press") -- the D-pad route's; a press already playing goes on
	end
	self:linger(t)
	self.onPress(name)
end

-- The ScreenGui a pressed tile lingers in: like the HUD's, made on the first press.
function MenuColumn.lingerGui(self: any): ScreenGui
	local gui: ScreenGui? = self.lingerScreen
	if gui and gui.Parent then
		return gui
	end
	local screen: ScreenGui = self.screen
	local made = Instance.new("ScreenGui")
	made.Name = "MenuColumnLinger"
	made.ResetOnSpawn = false
	made.IgnoreGuiInset = screen.IgnoreGuiInset
	made.ScreenInsets = screen.ScreenInsets
	made.ZIndexBehavior = screen.ZIndexBehavior
	made.DisplayOrder = screen.DisplayOrder
	made.Parent = screen.Parent
	self.lingerScreen = made
	return made
end

-- Tile `t` stays on screen for LingerSeconds while its menu opens, then pops out and goes home.
function MenuColumn.linger(self: any, t: Tile)
	self:endLinger()
	local gui = self:lingerGui()
	-- A copy of the column's root (place and fit) so the tile keeps its exact spot and size.
	local holder = HudParts.frame(gui, "Root")
	local at = self.root.AbsolutePosition - gui.AbsolutePosition
	holder.Position = UDim2.fromOffset(at.X, at.Y)
	holder.Size = self.root.Size
	holder.ZIndex = C.ZIndex
	local fit = Instance.new("UIScale")
	fit.Scale = self.fit.Scale
	fit.Parent = holder
	t.button.Parent = holder
	local token = {}
	self.lingering = { tile = t, holder = holder, token = token }
	task.delay(C.LingerSeconds, function()
		local now = self.lingering
		if now == nil or now.token ~= token then
			return
		end
		UIAnim.popOut(t.button, function()
			if self.lingering and self.lingering.token == token then
				self:endLinger()
			end
		end)
	end)
end

-- The lingering tile, if any, back in the column now.
function MenuColumn.endLinger(self: any)
	local now = self.lingering
	if now == nil then
		return
	end
	self.lingering = nil
	local button: TextButton = now.tile.button
	button.Parent = self.body
	button.Visible = true -- the pop out hid it; the column's own rules say again what shows
	UIAnim.scaleOf(button).Scale = 1
	now.holder:Destroy()
	self:refreshUlts()
end

--- A tile's button (for a flying chip or a tutorial pointer).
function MenuColumn.tile(self: any, name: string): TextButton?
	local t: Tile? = self.tiles[name]
	return if t then t.button else nil
end

--- A tile's centre in absolute pixels: where a cue (or a block) earned elsewhere flies to (the
--- Inventory tile), nil for an unknown name.
function MenuColumn.tileCenter(self: any, name: string): Vector2?
	local t: Tile? = self.tiles[name]
	if not t then
		return nil
	end
	return t.button.AbsolutePosition + t.button.AbsoluteSize / 2
end

--- Something landed on a tile (a cue flew into Inventory): it bounces.
function MenuColumn.bump(self: any, name: string)
	local t: Tile? = self.tiles[name]
	if t and self.showing then
		UIAnim.bounce(t.button)
	end
end

function MenuColumn.destroy(self: any)
	if not self.alive then
		return
	end
	self.alive = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.root:Destroy()
end

return MenuColumn
