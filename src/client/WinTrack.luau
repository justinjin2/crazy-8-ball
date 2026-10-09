--!strict
-- WinTrack: the day's win track over the lucky block hotbar (the designer's pick A on the mock
-- page, 2026-10-08; economy v4 plan section 5). A white bar of ten tiles, one per counted win
-- of the day, each the step's block (Config.BlockOdds.Drop.WinTrack: Rare, Mystery, Mystery,
-- Uncommon, Mystery, Mystery, Rare, Mystery, Mystery, Epic) with its number on a navy dot. A
-- step given today is greyed under a green tick; the next one has a thick gold edge and a gold
-- NEXT tag that hops gently. Across the bar's top edge: "Wins 3/10" at the left and the time
-- to the 08:00 UTC reset at the right; after the tenth, "10/10 · wins pay money and XP today".
-- A step given pops its tick where the player sees it: at once while the bar shows, else as the
-- bar comes back (after the result screen), one tick after another. "Resets in" sits over the
-- clock pill.
--
-- Folded by default (the designer, 2026-10-08: "by default its collapsed but after a match
-- itll appear briefly to show then collapse back down again on its own"): a small navy pill
-- with "Next ->" and the next step's block, "Wins 3/10" and an up arrow; a press opens the
-- whole bar, and its fold button (a navy circle with a down arrow on the bar's top edge, between
-- the pills: the designer, 2026-10-09, "wins needs a collapse dropdown") folds it. After a match the bar opens by itself as it comes back, for PeekSeconds,
-- then folds again (unless the player pressed it meanwhile).
--
-- It shows in the lobby with nothing over it (Progression: no menu, match, result screen,
-- reel or teleport, not during the tutorial) and takes the matchmaking bar's place: it hides
-- while that bar or an opponent's ask is up. Centred over the hotbar (BottomLift), the same
-- bar at PhoneScale on a phone. What it shows is RewardState's `wins` and `resetsAt`
-- (Progression/RewardView), sent again after every counted win. Sizes in Config.UI.WinTrack,
-- words in Strings.WinTrack.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local StageMath = require(Shared:WaitForChild("StageMath"))
local BottomLift = require(script.Parent.BottomLift)
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local T = Config.UI.WinTrack
local KINDS: { [string]: any } = Config.LuckyBlocks.Kinds :: any
local STEPS: { string } = Config.BlockOdds.Drop.WinTrack :: any
local PHONE_PX: number = Config.LuckyBlocks.UI.PhoneWidthPx
local COPY = Strings.WinTrack
local CLOCK_COPY: { [string]: any } = (Strings.Menus.Shop :: any).Featured -- "6d 23h", "23h 59m"

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

type Tile = {
	frame: Frame,
	edge: UIStroke,
	icon: ImageLabel,
	dot: Frame,
	check: ImageLabel,
}

local WinTrack = {}
WinTrack.__index = WinTrack

-- A navy pill with a gold rim (the Shop's title pills) holding kit words.
local function pill(parent: Instance, name: string): (Frame, TextLabel)
	local made = HudParts.frame(parent, name)
	made.BackgroundTransparency = 0
	made.BackgroundColor3 = rgb(T.PillColor)
	made.AnchorPoint = Vector2.new(0, 0.5)
	made.ZIndex = 6
	HudParts.corner(made, 99)
	local rim = Instance.new("UIStroke")
	rim.Name = "Rim"
	rim.Color = rgb(T.PillRim)
	rim.Thickness = T.PillRimPx
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = made
	local words = HudParts.text(made, "Words", T.PillTextPx, "")
	words.TextWrapped = false
	words.AnchorPoint = Vector2.new(0, 0.5)
	words.ZIndex = 7
	return made, words
end

-- How wide `text` is at `px`, with a little room.
local function measure(text: string, px: number): number
	return math.ceil(ShopParts.textWidth(text, px)) + 4
end

--- Build the bar (hidden) in `screen`, the HUD's ScreenGui.
function WinTrack.new(screen: ScreenGui): any
	local self: any = setmetatable({}, WinTrack)
	self.screen = screen
	self.want = false -- what Progression asks for
	self.shown = false
	self.given = -1 -- the steps drawn (-1: no RewardState yet)
	self.seen = -1 -- the steps the player has seen on screen (their ticks have popped)
	self.resetsAt = 0
	self.fake = nil :: number? -- GuiQA: a made-up count of steps given
	self.loops = {} :: { UIAnim.Handle }
	self.clockText = ""
	self.open = false -- the whole bar (true) or the folded pill
	self.peekPending = false -- a match ended: open by itself as the bar comes back
	self.peekToken = 0 -- the latest peek (a newer one, or a press, cancels the fold)

	local root = HudParts.frame(screen, "WinTrack")
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.ZIndex = T.ZIndex
	root.Visible = false
	self.root = root
	self.scale = Instance.new("UIScale")
	self.scale.Parent = root
	-- What pops in and out; everything else sits inside it.
	local holder = HudParts.frame(root, "Holder")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(1, 1)
	self.holder = holder
	local bar = HudParts.card(holder, "Bar", T.CornerPx)
	self.bar = bar

	local tiles: { Tile } = {}
	for index, kind in STEPS do
		local frame = HudParts.frame(bar, "Step" .. index)
		frame.BackgroundTransparency = 0
		frame.BackgroundColor3 = rgb(T.TileColor)
		frame.ZIndex = 2
		HudParts.corner(frame, T.TileCornerPx)
		local edge = Instance.new("UIStroke")
		edge.Name = "Edge"
		edge.Color = rgb(T.TileEdge)
		edge.Thickness = T.TileEdgePx
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Parent = frame
		local icon = Instance.new("ImageLabel")
		icon.Name = "Block"
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Image = if KINDS[kind] then KINDS[kind].Icon or "" else ""
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromScale(T.IconShare, T.IconShare)
		icon.ZIndex = 3
		icon.Parent = frame
		local dot = HudParts.frame(frame, "Number")
		dot.BackgroundTransparency = 0
		dot.BackgroundColor3 = rgb(T.NumberColor)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromOffset(T.NumberInsetPx, T.NumberInsetPx)
		dot.Size = UDim2.fromOffset(T.NumberPx, T.NumberPx)
		dot.ZIndex = 5
		HudParts.corner(dot, 99)
		local number = HudParts.text(dot, "Words", T.NumberTextPx, tostring(index))
		number.TextWrapped = false
		number.Size = UDim2.fromScale(1, 1)
		number.ZIndex = 6
		local check = HudParts.icon(frame, "Check", "Check")
		check.AnchorPoint = Vector2.new(0.5, 0.5)
		check.Position = UDim2.fromScale(0.5, 0.5)
		check.Size = UDim2.fromScale(T.CheckShare, T.CheckShare)
		check.ZIndex = 4
		check.Visible = false
		table.insert(tiles, { frame = frame, edge = edge, icon = icon, dot = dot, check = check })
	end
	self.tiles = tiles

	-- The NEXT tag (moved to the next step's tile).
	local tag = HudParts.pill(bar, "Next", rgb(T.NextColor))
	tag.AnchorPoint = Vector2.new(0.5, 0.5)
	tag.Size = UDim2.fromOffset(T.NextTagPx[1], T.NextTagPx[2])
	tag.ZIndex = 8
	tag.Visible = false
	local tagWords = HudParts.text(tag, "Words", T.NextTextPx, COPY.NextTag)
	tagWords.TextWrapped = false
	tagWords.Size = UDim2.fromScale(1, 1)
	tagWords.ZIndex = 9
	self.tag = tag

	-- The pills across the top edge.
	self.count, self.countWords = pill(holder, "Count")
	self.countWords.TextColor3 = rgb(T.CountColor)
	self.clock, self.clockWords = pill(holder, "Clock")
	self.clock.AnchorPoint = Vector2.new(1, 0.5)
	local clockIcon = HudParts.icon(self.clock, "Stopwatch", "Stopwatch")
	clockIcon.AnchorPoint = Vector2.new(0, 0.5)
	clockIcon.ZIndex = 7
	self.clockIcon = clockIcon

	-- "Resets in" over the clock pill.
	local resets = HudParts.text(holder, "ResetsIn", T.ResetsTextPx, COPY.ResetsAbove)
	resets.TextWrapped = false
	resets.AnchorPoint = Vector2.new(0.5, 1)
	resets.ZIndex = 7
	self.resets = resets

	-- The fold button on the open bar's top edge: a navy circle, a gold rim, a down arrow.
	local fold = Instance.new("TextButton")
	fold.Name = "Fold"
	fold.Text = ""
	fold.AutoButtonColor = false
	fold.BorderSizePixel = 0
	fold.BackgroundColor3 = rgb(T.PillColor)
	fold.AnchorPoint = Vector2.new(0.5, 0.5)
	fold.ZIndex = 10
	fold.Parent = holder
	HudParts.corner(fold, 99)
	local foldRim = Instance.new("UIStroke")
	foldRim.Name = "Rim"
	foldRim.Color = rgb(T.PillRim)
	foldRim.Thickness = T.PillRimPx
	foldRim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	foldRim.Parent = fold
	local foldArrow = HudParts.icon(fold, "ChevronDown", "Arrow")
	foldArrow.AnchorPoint = Vector2.new(0.5, 0.5)
	foldArrow.Position = UDim2.fromScale(0.5, 0.55)
	foldArrow.Size = UDim2.fromScale(T.FoldArrowShare, T.FoldArrowShare)
	foldArrow.ZIndex = 11
	fold.Activated:Connect(function()
		self:setOpen(false, true)
	end)
	self.fold = fold

	-- The folded pill: the next step's block, "Wins 3/10" and an up arrow; a press opens it.
	local mini = Instance.new("TextButton")
	mini.Name = "Folded"
	mini.Text = ""
	mini.AutoButtonColor = false
	mini.BorderSizePixel = 0
	mini.BackgroundColor3 = rgb(T.PillColor)
	mini.AnchorPoint = Vector2.new(0.5, 1)
	mini.ZIndex = 6
	mini.Visible = false
	mini.Parent = root
	HudParts.corner(mini, 99)
	local miniRim = Instance.new("UIStroke")
	miniRim.Name = "Rim"
	miniRim.Color = rgb(T.PillRim)
	miniRim.Thickness = T.PillRimPx
	miniRim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	miniRim.Parent = mini
	-- "Next" and an arrow before the block (the designer, 2026-10-09).
	local miniNext = HudParts.text(mini, "Next", T.PillTextPx, COPY.NextFolded)
	miniNext.TextWrapped = false
	miniNext.AnchorPoint = Vector2.new(0, 0.5)
	miniNext.ZIndex = 7
	local miniNextArrow = HudParts.icon(mini, "Arrow", "NextArrow")
	miniNextArrow.AnchorPoint = Vector2.new(0, 0.5)
	miniNextArrow.ZIndex = 7
	self.miniNext, self.miniNextArrow = miniNext, miniNextArrow
	local miniBlock = Instance.new("ImageLabel")
	miniBlock.Name = "Block"
	miniBlock.BackgroundTransparency = 1
	miniBlock.ScaleType = Enum.ScaleType.Fit
	miniBlock.AnchorPoint = Vector2.new(0, 0.5)
	miniBlock.ZIndex = 7
	miniBlock.Parent = mini
	local miniWords = HudParts.text(mini, "Words", T.PillTextPx, "")
	miniWords.TextWrapped = false
	miniWords.AnchorPoint = Vector2.new(0, 0.5)
	miniWords.TextColor3 = rgb(T.CountColor)
	miniWords.ZIndex = 7
	local miniArrow = HudParts.icon(mini, "ChevronUp", "Arrow")
	miniArrow.AnchorPoint = Vector2.new(1, 0.5)
	miniArrow.ZIndex = 7
	mini.Activated:Connect(function()
		self:setOpen(true, true)
	end)
	self.mini, self.miniBlock, self.miniWords, self.miniArrow =
		mini, miniBlock, miniWords, miniArrow

	self:layout()
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layout()
	end)
	ItemState.Changed.Rewards:Connect(function()
		self:refresh()
	end)
	self:addTestHooks()
	self:refresh()
	return self
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

function WinTrack.layout(self: any)
	local n = #self.tiles
	local width = 2 * T.PadPx + n * T.TilePx + (n - 1) * T.TileGapPx
	local barH = T.TopPadPx + T.TilePx + T.PadPx
	-- The pills reach this far over the bar, and "Resets in" sits over the clock pill.
	local over = T.PillHeightPx / 2 + T.ResetsTextPx + T.ResetsGapPx
	self.root.Size = UDim2.fromOffset(width, barH + over)
	self.bar.Position = UDim2.fromOffset(0, over)
	self.bar.Size = UDim2.fromOffset(width, barH)
	for index, tile in self.tiles :: { Tile } do
		tile.frame.Position =
			UDim2.fromOffset(T.PadPx + (index - 1) * (T.TilePx + T.TileGapPx), T.TopPadPx)
		tile.frame.Size = UDim2.fromOffset(T.TilePx, T.TilePx)
	end
	-- The count pill fits its words; the clock pill fits its widest time.
	local countW = measure(self.countWords.Text, T.PillTextPx)
	self.count.Position = UDim2.fromOffset(T.PillInsetPx, over)
	self.count.Size = UDim2.fromOffset(countW + 2 * T.PillPadPx, T.PillHeightPx)
	self.countWords.Position = UDim2.new(0, T.PillPadPx, 0.5, 0)
	self.countWords.Size = UDim2.fromOffset(countW, T.PillHeightPx)
	local timeW = measure(T.ClockSample, T.PillTextPx)
	local clockW = T.PillPadPx + T.ClockIconPx + 4 + timeW + T.PillPadPx
	self.clock.Position = UDim2.fromOffset(width - T.PillInsetPx, over)
	self.clock.Size = UDim2.fromOffset(clockW, T.PillHeightPx)
	self.clockIcon.Position = UDim2.new(0, T.PillPadPx, 0.5, 0)
	self.clockIcon.Size = UDim2.fromOffset(T.ClockIconPx, T.ClockIconPx)
	self.clockWords.Position = UDim2.new(0, T.PillPadPx + T.ClockIconPx + 4, 0.5, 0)
	self.clockWords.Size = UDim2.fromOffset(timeW, T.PillHeightPx)
	local resetsW = measure(self.resets.Text, T.ResetsTextPx)
	self.resets.Position = UDim2.fromOffset(
		width - T.PillInsetPx - clockW / 2,
		over - T.PillHeightPx / 2 - T.ResetsGapPx
	)
	self.resets.Size = UDim2.fromOffset(resetsW, T.ResetsTextPx + 4)
	-- The fold button, centred on the bar's top edge between the pills.
	self.fold.Position = UDim2.fromOffset(width / 2, over)
	self.fold.Size = UDim2.fromOffset(T.FoldPx, T.FoldPx)
	HudParts.setMinHit(self.fold, Config.UI.Menu.Frame.TouchMinPx)
	-- The folded pill, centred at the bar's foot: "Next ->" and the block (none after the
	-- tenth), the words, the arrow.
	local hasNext = self.miniBlock.Image ~= ""
	self.miniNext.Visible, self.miniNextArrow.Visible, self.miniBlock.Visible =
		hasNext, hasNext, hasNext
	local nextW = measure(COPY.NextFolded, T.PillTextPx)
	local lead = if hasNext
		then nextW
			+ T.FoldedNextGapPx
			+ T.FoldedNextArrowPx
			+ T.FoldedNextGapPx
			+ T.FoldedBlockPx
			+ T.FoldedGapPx
		else 0
	local miniWordsW = measure(self.miniWords.Text, T.PillTextPx)
	local miniW = T.PillPadPx + lead + miniWordsW + T.FoldedGapPx + T.FoldedArrowPx + T.PillPadPx
	self.mini.Position = UDim2.fromScale(0.5, 1)
	self.mini.Size = UDim2.fromOffset(miniW, T.FoldedHeightPx)
	local x = T.PillPadPx
	self.miniNext.Position = UDim2.new(0, x, 0.5, 0)
	self.miniNext.Size = UDim2.fromOffset(nextW, T.FoldedHeightPx)
	x += nextW + T.FoldedNextGapPx
	self.miniNextArrow.Position = UDim2.new(0, x, 0.5, 0)
	self.miniNextArrow.Size = UDim2.fromOffset(T.FoldedNextArrowPx, T.FoldedNextArrowPx)
	x += T.FoldedNextArrowPx + T.FoldedNextGapPx
	self.miniBlock.Position = UDim2.new(0, x, 0.5, 0)
	self.miniBlock.Size = UDim2.fromOffset(T.FoldedBlockPx, T.FoldedBlockPx)
	self.miniWords.Position = UDim2.new(0, T.PillPadPx + lead, 0.5, 0)
	self.miniWords.Size = UDim2.fromOffset(miniWordsW, T.FoldedHeightPx)
	self.miniArrow.Position = UDim2.new(1, -T.PillPadPx, 0.5, 0)
	self.miniArrow.Size = UDim2.fromOffset(T.FoldedArrowPx, T.FoldedArrowPx)
	HudParts.setMinHit(self.mini, Config.UI.Menu.Frame.TouchMinPx)
	local phone = self.screen.AbsoluteSize.X < PHONE_PX
	self.scale.Scale = if phone then T.PhoneScale else 1
	self:place()
end

-- Over the hotbar (its lift changes as it shows and hides).
function WinTrack.place(self: any)
	local position = UDim2.new(0.5, 0, 1, -(T.BottomPx + BottomLift.get()))
	if self.root.Position ~= position then
		self.root.Position = position
	end
end

--------------------------------------------------------------------------------------------
-- What the server says
--------------------------------------------------------------------------------------------

-- The steps given today and when the day resets (a GuiQA count stands in when set).
function WinTrack.read(self: any): (number?, number)
	local state = ItemState.rewards()
	local resetsAt = if type(state) == "table" and type(state.resetsAt) == "number"
		then state.resetsAt
		else 0
	if self.fake then
		return self.fake, resetsAt
	end
	local wins = if type(state) == "table" then state.wins else nil
	if type(wins) ~= "table" or type(wins.given) ~= "number" then
		return nil, resetsAt
	end
	return math.clamp(math.floor(wins.given), 0, #STEPS), resetsAt
end

--- Draw the steps given today; a step given while the bar shows pops its tick.
function WinTrack.refresh(self: any)
	local given, resetsAt = self:read()
	self.resetsAt = resetsAt
	if given == nil then
		self.given = -1
		self:apply()
		return
	end
	if given == self.given then
		self:tick()
		return
	end
	self.given = given
	local n = #STEPS
	for index, tile in self.tiles :: { Tile } do
		local done = index <= given
		local next = index == given + 1
		tile.frame.BackgroundColor3 = rgb(if done then T.DoneColor else T.TileColor)
		tile.icon.ImageTransparency = if done then T.DoneTransparency else 0
		tile.check.Visible = done
		tile.edge.Color = rgb(if next then T.NextEdge else T.TileEdge)
		tile.edge.Thickness = if next then T.NextEdgePx else T.TileEdgePx
	end
	self.countWords.Text = if given >= n
		then string.format(COPY.Done, n, n)
		else string.format(COPY.Wins, given, n)
	self.miniWords.Text = string.format(COPY.Wins, given, n)
	local nextKind = STEPS[given + 1]
	self.miniBlock.Image = if nextKind and KINDS[nextKind] then KINDS[nextKind].Icon or "" else ""
	-- The tag under the next step's tile.
	if given < n then
		local tile = self.tiles[given + 1]
		self.tagBase = UDim2.fromOffset(
			tile.frame.Position.X.Offset + T.TilePx / 2,
			tile.frame.Position.Y.Offset + T.TilePx
		)
		self.tag.Position = self.tagBase
	end
	self.tag.Visible = given < n
	self:layout()
	self:tick()
	self:apply()
	if self.shown then
		self:popNew()
	end
end

-- Pop the ticks of the steps given since the player last saw the bar (none the first time,
-- or after the day's reset).
function WinTrack.popNew(self: any)
	local from, to = self.seen, self.given
	self.seen = to
	if from < 0 or to <= from then
		return
	end
	for index = from + 1, to do
		local check = self.tiles[index].check
		check.Visible = false
		task.delay((index - from - 1) * T.TickStaggerSeconds + T.TickDelaySeconds, function()
			if self.given >= index and self.shown then
				UIAnim.popIn(check)
			else
				check.Visible = self.given >= index
			end
		end)
	end
end

-- The time to the reset, once a second while the bar shows.
function WinTrack.tick(self: any)
	local left = math.max(0, self.resetsAt - workspace:GetServerTimeNow())
	local text = StageMath.timeLeft(left, CLOCK_COPY)
	if text ~= self.clockText then
		self.clockText = text
		self.clockWords.Text = text
	end
end

--------------------------------------------------------------------------------------------
-- Showing
--------------------------------------------------------------------------------------------

-- Whether the tutorial is running (a step not published yet counts as the tutorial).
local function tutorial(): boolean
	local player = Players.LocalPlayer
	local step = if player then player:GetAttribute("TutorialStep") else nil
	return type(step) ~= "string" or step ~= ""
end

--- Progression's call, every frame: whether the lobby has room for the bar now.
function WinTrack.setVisible(self: any, want: boolean)
	self.want = want
	self:apply()
	if self.shown then
		self:place()
	end
end

-- Show or hide as wanted (and only with a RewardState), popping in and out.
function WinTrack.apply(self: any)
	local show = self.want and self.given >= 0 and not tutorial()
	if show == self.shown then
		return
	end
	self.shown = show
	if show then
		self:tick()
		self.root.Visible = true
		if self.peekPending then
			self.peekPending = false
			self:peekNow()
		end
		local piece = if self.open then self.holder else self.mini
		local other = if self.open then self.mini else self.holder
		other.Visible = false
		piece.Visible = false
		UIAnim.popIn(piece)
		self:startLoops()
		if self.open then
			self:popNew()
		end
	else
		self:stopLoops()
		local piece = if self.open then self.holder else self.mini
		UIAnim.popOut(piece, function()
			if not self.shown then
				self.root.Visible = false
			end
		end)
	end
end

-- Open or fold the bar (`byPlayer`: a press, which cancels a peek's fold).
function WinTrack.setOpen(self: any, open: boolean, byPlayer: boolean?)
	if byPlayer then
		self.peekToken += 1
	end
	if self.open == open then
		return
	end
	self.open = open
	if not self.shown then
		return
	end
	UISound.play("Click")
	local piece = if open then self.holder else self.mini
	local other = if open then self.mini else self.holder
	other.Visible = false
	piece.Visible = false
	UIAnim.popIn(piece)
	if open then
		self:popNew()
	end
end

-- Open now and fold again after PeekSeconds (unless pressed meanwhile).
function WinTrack.peekNow(self: any)
	self.peekToken += 1
	local token = self.peekToken
	self.open = true
	task.delay(T.PeekSeconds, function()
		if self.peekToken == token and self.open then
			if self.shown then
				self:setOpen(false)
			else
				self.open = false
			end
		end
	end)
end

--- A match just ended: the bar opens by itself as it comes back, then folds.
function WinTrack.peek(self: any)
	self.peekPending = true
end

-- The NEXT tag hops, and the clock counts down.
function WinTrack.startLoops(self: any)
	self:stopLoops()
	local tag = self.tag
	table.insert(
		self.loops,
		UIAnim.loop(tag, function(clock: number)
			local base: UDim2? = self.tagBase
			if base == nil then
				return
			end
			local hop = if UIAnim.reduced()
				then 0
				else T.HopPx * math.abs(math.sin(math.pi * clock / T.HopSeconds))
			tag.Position = base - UDim2.fromOffset(0, math.floor(hop + 0.5))
		end)
	)
	local last = -1
	table.insert(
		self.loops,
		UIAnim.loop(self.root, function(clock: number)
			if clock - last >= 1 then
				last = clock
				self:tick()
			end
		end)
	)
end

function WinTrack.stopLoops(self: any)
	for _, handle in self.loops :: { UIAnim.Handle } do
		handle.stop()
	end
	table.clear(self.loops)
end

--------------------------------------------------------------------------------------------
-- Test hooks (Studio only)
--------------------------------------------------------------------------------------------

--- GuiQA "wintrack": draw `given` steps (0..10), or "real" for the server's count again;
--- "peek" opens it as after a match, "open" and "fold" as a press does.
function WinTrack.addTestHooks(self: any)
	GuiQA.add("wintrack", function(given: any): string
		if given == "peek" then
			-- As after a match: open now, fold after PeekSeconds.
			self:peekNow()
			if self.shown then
				self.mini.Visible = false
				self.holder.Visible = true
				self:popNew()
			end
		elseif given == "open" or given == "fold" then
			self:setOpen(given == "open", true)
		else
			self.fake = if type(given) == "number"
				then math.clamp(math.floor(given), 0, #STEPS)
				else nil
			self:refresh()
		end
		return string.format(
			"given %d, shown %s, want %s",
			self.given,
			tostring(self.shown),
			tostring(self.want)
		)
	end)
end

return WinTrack
