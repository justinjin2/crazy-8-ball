--!strict
-- MenuColumn: the left column (docs/prompts/ECONOMY_UI_PROMPT.md section 5; reference
-- 06-left-menu-buttons): Shop, Inventory, Rewards, Trade and Ults, top to bottom, one tile
-- each (Ults: docs/prompts/ULTIMATES_PROMPT.md section 9.1, the spin screen UltScreen). A
-- tile is just its glossy icon, big, with no box behind it (designer, 2026-09-28: the blue
-- candy square went so the icons could be bigger), and the word (Strings.Menus.Column) in white
-- Fredoka with an ink outline across the icon's lower edge, real text, never in the image. It
-- keeps the kit candy's behaviour with the candy's face hidden: hover and gamepad selection
-- grow it a little; a press squishes and bounces it (UIAnim) with the Click sound, and opens
-- its menu (onPress).
--
-- Red dots, top right of a tile: Inventory counts unopened cases (the player's CasesUnopened
-- attribute, "9+" above 9); Rewards shows "!" while RewardReady is true; Shop shows a small
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
-- right Inventory, down Rewards, left Trade: Progression.padRoute), and while a gamepad is the
-- last input each tile shows its D-pad glyph (Roblox's own, so it matches the controller). The
-- D-pad's four directions are taken, so Ults is gamepad X (Config.UI.UltScreen.Column.PadKey;
-- overnight assumption, 2026-09-28: X is the ult button in a match, so X means "ult"
-- everywhere). The column listens for it itself, only while the D-pad route is live.
--
-- Hidden until the save loads, in a match, and while the result screen, NEW RANK!, the case
-- opening or the teleport screen is up (Progression.update calls setVisible every frame).
--
-- GUI lane (designer 2026-10-03, C2): the tiles are Shop, Inventory, Abilities and Free Reward
-- (Config order). Rewards and Trade left the column. Free Reward shows only while the group or
-- the favorite reward is left to claim (RewardState), bobbing in front of turning gold rays.
-- Hovering a tile (or pressing it) shakes its icon and bursts a glow behind it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)
local UltSpinState = require(script.Parent.UltSpinState)

local C = Config.UI.Menu.Column
local S = Config.Multiplayer.Style
local K = Config.UI.Kit
local RANK = Config.UI.Progress.RankHud
local MONEY = Config.UI.Progress.MoneyHud
local WORDS: { [string]: string } = table.clone(Strings.Menus.Column :: any)
local COPY = Strings.Menus
local ULTS = Config.UI.UltScreen.Column.Name -- the spin screen's tile ("Ults"), last
local ORDER: { string } = table.clone(C.Order)
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
local FREE = "FreeReward" -- the Free Reward tile (GUI lane)

type Tile = {
	name: string,
	rays: ImageLabel?, -- Free Reward's turning rays
	iconPos: UDim2?, -- the icon's laid-out place (Free Reward bobs round it)
	button: TextButton,
	body: Frame, -- the candy's body: everything on the tile squishes and grows with it
	icon: ImageLabel,
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

	-- The root holds the fit (a UIScale for a short screen); the body inside pops in and out.
	local root = HudParts.frame(screen, "MenuColumn")
	root.ZIndex = C.ZIndex
	self.root = root
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
	end
	connect(UserInputService.LastInputTypeChanged, function()
		self:refreshGlyphs()
	end)
	connect(UserInputService.GamepadConnected, function()
		self:refreshGlyphs()
	end)
	local player = Players.LocalPlayer
	if player then
		connect(player:GetAttributeChangedSignal("CasesUnopened"), function()
			self:refreshDots()
		end)
		connect(player:GetAttributeChangedSignal("RewardReady"), function()
			self:refreshDots()
		end)
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
	self:refreshUlts()
	self:refreshFree()
	self:layout()
	self:refreshDots()
	self:refreshTimer()
	self:refreshGlyphs()
	self:refreshVisible()
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
	local live = UltSpinState.isLive()
	if t.button.Visible ~= live then
		t.button.Visible = live
		self:queueLayout()
		self:refreshDots()
	end
end

--- Show the Free Reward tile only while the group or the favorite reward is left to claim
--- (RewardState); it bobs in front of its turning rays while up.
function MenuColumn.refreshFree(self: any)
	local t: Tile? = self.tiles[FREE]
	if not t then
		return
	end
	local state = ItemState.rewards()
	local left = false
	if type(state) == "table" then
		local group = state.group
		local favorite = state.favorite
		left = (type(group) == "table" and group.claimed ~= true)
			or (type(favorite) == "table" and favorite.claimed ~= true)
	end
	if t.button.Visible ~= left then
		t.button.Visible = left
		self:queueLayout()
	end
	if left and not self.freeLoop then
		local icon, rays = t.icon, t.rays
		self.freeLoop = UIAnim.loop(icon, function(clock: number)
			local base = t.iconPos
			if base then
				local y = math.sin(2 * math.pi * clock / K.Motion.Bob.Seconds) * C.FreeBobPx
				icon.Position = base + UDim2.fromOffset(0, round(y))
			end
			if rays then
				rays.Rotation = (clock * K.Motion.RaysDegreesPerSecond) % 360
			end
		end)
	elseif not left and self.freeLoop then
		self.freeLoop.stop()
		self.freeLoop = nil
	end
end

--- Whether the Free Reward tile is up.
function MenuColumn.freeShown(self: any): boolean
	local t: Tile? = self.tiles[FREE]
	return t ~= nil and t.button.Visible
end

--- A tile's icon shakes hard for a moment and a glow bursts behind it (hover, press).
function MenuColumn.jiggle(self: any, name: string)
	local t: Tile? = self.tiles[name]
	if not t then
		return
	end
	local shake = UIAnim.shake(t.icon, "Hard")
	task.delay(C.HoverShakeSeconds, shake.stop)
	UIAnim.glowBurst(t.icon, nil, C.HoverGlowReach)
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
	-- Hover: a bigger shake and a glow burst behind the icon.
	button.MouseEnter:Connect(function()
		if self.showing then
			self:jiggle(name)
		end
	end)
	local word = HudParts.text(body, "Word", C.LabelTextPx, WORDS[name] or name)
	word.TextWrapped = false
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

-- The money HUD's top edge in the screen's pixels: measured, or from its Config size.
function MenuColumn.moneyTop(self: any, origin: Vector2, size: Vector2, short: boolean): number
	local root = self:moneyRoot()
	if root and root.AbsoluteSize.Y > 0 then
		return root.AbsolutePosition.Y - origin.Y
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
		widest =
			math.max(widest, TextService:GetTextSize(words, textPx, FONT, Vector2.new(2000, 200)).X)
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
		t.iconPos = t.icon.Position
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

--- Read the red dots again: unopened cases on Inventory, "!" on Rewards, "!" on Ults while
--- today's free ult spin is unused.
function MenuColumn.refreshDots(self: any)
	local player = Players.LocalPlayer
	local cases = if player then player:GetAttribute("CasesUnopened") else nil
	local count = if type(cases) == "number" then cases else ItemState.casesTotal()
	count = math.max(0, math.floor(count))
	local casesText = if count <= 0
		then nil
		elseif count > C.DotMax then COPY.DotMore:format(C.DotMax)
		else tostring(count)
	setDot(self, self.tiles.Inventory, casesText)
	local rewardsTile: Tile? = self.tiles.Rewards
	if rewardsTile then
		local ready = if player then player:GetAttribute("RewardReady") == true else false
		setDot(self, rewardsTile, if ready then COPY.DotReady else nil)
	end
	-- The Shop: how many of its jump groups hold something new (a restock, an offer), while
	-- its offer timer pill is not up in the same corner.
	local shopNew = if self.opts.shopNew then self.opts.shopNew() else 0
	local shopTile: Tile = self.tiles.Shop
	local timerUp = shopTile.timer ~= nil and shopTile.timer.Visible
	setDot(
		self,
		shopTile,
		if shopNew > 0 and not timerUp then tostring(math.min(shopNew, C.DotMax)) else nil
	)
	local ults: Tile? = self.tiles[ULTS]
	if ults then
		local free = UltSpinState.freeSpinReady() and UltSpinState.isLive()
		setDot(self, ults, if free then COPY.DotReady else nil)
	end
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
		timer.Visible = false
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
	self:jiggle(name)
	self.onPress(name)
end

--- A tile's button (for a flying chip or a tutorial pointer).
function MenuColumn.tile(self: any, name: string): TextButton?
	local t: Tile? = self.tiles[name]
	return if t then t.button else nil
end

--- A tile's centre in absolute pixels: where a case or cue earned elsewhere flies to (the
--- Inventory tile), nil for an unknown name.
function MenuColumn.tileCenter(self: any, name: string): Vector2?
	local t: Tile? = self.tiles[name]
	if not t then
		return nil
	end
	return t.button.AbsolutePosition + t.button.AbsoluteSize / 2
end

--- Something landed on a tile (a case flew into Inventory): it bounces.
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
