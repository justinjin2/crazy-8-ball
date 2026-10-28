--!strict
-- BoostPill: the summed money boost over the money pill, bottom left (Halloween 2026, PLAN §2
-- "Boost display", R5.3-R5.6; hw-gui lane; mock H1_boost_hud). It takes the VIP tag's place
-- (Progression builds it instead of VipTag when Config.UI.BoostPill.Enabled) and has the tag's
-- shape (`tag`, `on`, `top`, `setInMatch`, `showPerks`, `layout`), so Purchased and LuckClover
-- work with it unchanged.
--
-- The pill: a white pill with the ink outline, as the money pill; a crown (rocking, as the VIP
-- tag's) for VIP, else a green up-arrow; then "+N%", N = Money.boost of the player's flags
-- (BoostFlags.of, the reader the server pays from, so the pill shows what is paid). "+0%" shows
-- dimmed (ShowAtZero). A higher total counts up, then pops; a lower one just changes.
-- Hovering shows "YOUR BOOSTS" over it (a row per Money.boostParts part, the total, the friend
-- rule, the Candy line while the event is live, then grey the boosts still to get); a click,
-- tap or A pins it open for PinSeconds, a second press or B closes it. In a match it still
-- shows (money does) but takes no input and its card shuts. Hidden while the tutorial runs.
--
-- The Rush chip (R1.10): its shell and place are this module's, its words core's. Once a second
-- it asks src/client/Halloween/RushChip.luau `RushChip.content(now) -> { text, endsAt }?`
-- (guarded: missing, an error or nil hides it); its icon is Config.Halloween.CandyIcon (guarded;
-- missing or "" collapses the slot). It pops in the first time, then its colour breathes gently
-- (never its scale: text never pulses). HudLayout places the pill and the chip from the live
-- rects of the pieces around them. Studio only: GuiQA `boosts`, `boostCard`, `boostPerks`,
-- `rushChip`, `hudRects`, `hudOverlap`. Sizes in Config.UI.BoostPill, words in Strings.BoostPill.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudLayout = require(Shared:WaitForChild("HudLayout"))
local ProgressionShared = Shared:WaitForChild("Progression")
local BoostFlags = require(ProgressionShared:WaitForChild("BoostFlags"))
local Money = require(ProgressionShared:WaitForChild("Money"))
local Steps = require(Shared:WaitForChild("Tutorial"):WaitForChild("Steps"))
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local P = Config.UI.BoostPill
local K = P.Card
local CHIP = P.Chip
local E = Config.Economy
local COPY = Strings.BoostPill
local PARTS: { [string]: string } = COPY.Parts :: any

-- Each part's icon (Config.UI.Kit.Icons), as H1 draws them.
local ICONS: { [string]: string } = {
	Vip = "Crown",
	Group = "Group",
	Plus = "RobloxPlus",
	Friends = "People",
	Starter = "StarterPack",
	Party = "MoneyParty",
}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function percent(add: number): string
	return COPY.Percent:format(math.floor(add * 100 + 0.5))
end

-- Core's pieces, each read guarded (a missing one hides a line, never errors).
local function optional(get: () -> any): any
	local ok, value = pcall(get)
	return if ok then value else nil
end

local EventModule: any = optional(function()
	local folder = Shared:FindFirstChild("Halloween")
	local module = folder and folder:FindFirstChild("Event")
	return if module then (require :: any)(module) else nil
end)
local ClockModule: any = optional(function()
	local folder = Shared:FindFirstChild("Halloween")
	local module = folder and folder:FindFirstChild("Clock")
	return if module then (require :: any)(module) else nil
end)

local function now(): number
	if ClockModule and type(ClockModule.now) == "function" then
		local ok, value = pcall(ClockModule.now)
		if ok and type(value) == "number" then
			return value
		end
	end
	return workspace:GetServerTimeNow()
end

local function candyIcon(): string?
	local hw = (Config :: any).Halloween
	local icon = if type(hw) == "table" then hw.CandyIcon else nil
	return if type(icon) == "string" and icon ~= "" then icon else nil
end

-- The GuiObject `object` and every GuiObject over it are visible (and its ScreenGui enabled).
local function shown(object: Instance?): boolean
	local at = object
	while at do
		if at:IsA("GuiObject") then
			if not at.Visible then
				return false
			end
		elseif at:IsA("ScreenGui") then
			return at.Enabled
		end
		at = at.Parent
	end
	return false
end

local BoostPill = {}
BoostPill.__index = BoostPill

--- Build the pill (hidden until the save loads and the tutorial ends) in `money`'s root.
function BoostPill.new(money: any): any
	local self: any = setmetatable({}, BoostPill)
	self.money = money
	self.screen = money.screen
	self.on = false -- shown (LuckClover reads it, as VipTag's)
	self.inMatch = false
	self.hovered = false
	self.pinned = false
	self.pinToken = 0
	self.total = nil :: number?
	self.fake = nil :: any -- GuiQA `boosts`
	self.chipFake = nil :: string? -- GuiQA `rushChip`
	self.chipOn = false
	self.chipWords = ""
	self.loops = {} :: { UIAnim.Handle }
	self.count = nil :: UIAnim.Handle?
	self.chipBreath = nil :: Tween?
	self.reportedCard = false
	self.rushWarned = false

	local tag = Instance.new("TextButton")
	tag.Name = "BoostPill"
	tag.Text = ""
	tag.Selectable = false -- HubCorners makes it a pad stop while the pad is in the corners
	tag.AutoButtonColor = false
	tag.BackgroundTransparency = 1
	tag.BorderSizePixel = 0
	tag.Visible = false
	tag.ZIndex = P.ZIndex
	tag.Parent = money.root
	self.tag = tag
	local face = HudParts.pill(tag, "Face")
	face.Size = UDim2.fromScale(1, 1)
	face.ZIndex = P.ZIndex
	self.face = face
	local crown = HudParts.icon(face, "Crown", "Crown")
	crown.AnchorPoint = Vector2.new(0.5, 0.5)
	crown.ZIndex = P.ZIndex + 1
	self.crown = crown
	local arrow = HudParts.icon(face, "ArrowWhite", "Arrow")
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Rotation = -90 -- the kit's arrow points right
	arrow.ImageColor3 = rgb(P.Green)
	arrow.ZIndex = P.ZIndex + 1
	self.arrow = arrow
	local word = HudParts.text(face, "Word", P.TextPx, percent(0))
	word.AutoLocalize = false
	word.TextWrapped = false
	word.TextXAlignment = Enum.TextXAlignment.Left
	word.AnchorPoint = Vector2.new(0, 0.5)
	word.ZIndex = P.ZIndex + 1
	self.word = word

	-- The card over the pill.
	local card = HudParts.popupCard(tag, "Boosts", K.CornerPx)
	card.AnchorPoint = Vector2.new(0, 1)
	card.Visible = false
	card.ZIndex = P.ZIndex + 2
	self.card = card
	local title = HudParts.note(card, "Title", K.TitlePx, COPY.Title)
	title.TextWrapped = false
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = P.ZIndex + 3
	self.title = title
	self.rows = {} :: { any } -- built per show (cardRows)
	local rule = HudParts.frame(card, "Rule")
	rule.BackgroundTransparency = 0
	rule.BackgroundColor3 = rgb(K.Grey)
	rule.ZIndex = P.ZIndex + 3
	self.rule = rule
	local totalWord = HudParts.note(card, "Total", K.TotalPx, COPY.Total)
	totalWord.TextWrapped = false
	totalWord.TextXAlignment = Enum.TextXAlignment.Left
	totalWord.ZIndex = P.ZIndex + 3
	self.totalWord = totalWord
	local totalValue = HudParts.note(card, "TotalValue", K.TotalPx, percent(0))
	totalValue.AutoLocalize = false
	totalValue.TextWrapped = false
	totalValue.TextXAlignment = Enum.TextXAlignment.Right
	totalValue.TextColor3 = rgb(K.ValueGreen)
	totalValue.ZIndex = P.ZIndex + 3
	self.totalValue = totalValue

	-- The Rush chip, right over the pill (HudLayout); core fills its words.
	local chip = HudParts.pill(money.root, "RushChip", rgb(CHIP.Color))
	chip.Visible = false
	chip.ZIndex = CHIP.ZIndex
	self.chip = chip
	local chipIcon = Instance.new("ImageLabel")
	chipIcon.Name = "Icon"
	chipIcon.BackgroundTransparency = 1
	chipIcon.ScaleType = Enum.ScaleType.Fit
	chipIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	chipIcon.ZIndex = CHIP.ZIndex + 1
	chipIcon.Parent = chip
	self.chipIcon = chipIcon
	local chipText = HudParts.text(chip, "Words", CHIP.TextPx, "")
	chipText.AutoLocalize = false
	chipText.TextWrapped = false
	chipText.AnchorPoint = Vector2.new(0, 0.5)
	chipText.ZIndex = CHIP.ZIndex + 1
	self.chipText = chipText

	tag.MouseEnter:Connect(function()
		self.hovered = true
		if not self.inMatch then
			self:showCard(false)
		end
	end)
	tag.MouseLeave:Connect(function()
		self.hovered = false
		if not self.pinned then
			self:hideCard()
		end
	end)
	tag.Activated:Connect(function()
		self:press()
	end)

	local player = Players.LocalPlayer
	if player then
		for _, name in { "Vip", "InGroup", "FriendsHere", "MoneyBoostEnds", "TutorialStep" } do
			player:GetAttributeChangedSignal(name):Connect(function()
				self:refresh()
			end)
		end
		player:GetPropertyChangedSignal("MembershipType"):Connect(function()
			self:refresh()
		end)
	end
	workspace:GetAttributeChangedSignal("MoneyPartyEndsAt"):Connect(function()
		self:refresh()
	end)
	money.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layout()
	end)
	money.root:GetPropertyChangedSignal("Visible"):Connect(function()
		self:refresh()
	end)
	if self.screen then
		self.screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:layout()
		end)
	end
	-- One 1 s loop: the chip's words (core's clock), the timed parts' ends and countdowns, and
	-- the pieces around it (a hotbar or WinTrack that moved). Never per frame.
	task.spawn(function()
		while true do
			task.wait(CHIP.PollSeconds)
			self:tick()
		end
	end)
	self:addQA()
	self:refresh()
	return self
end

-- The flags shown: the real ones, or GuiQA's stand-ins.
function BoostPill.flags(self: any): Money.Boosts
	if self.fake then
		return self.fake
	end
	local player = Players.LocalPlayer
	if not player then
		return {}
	end
	return BoostFlags.of(player, workspace:GetServerTimeNow())
end

-- Whether the pill may show: the save is in, the money HUD shows, the tutorial is over.
function BoostPill.allowed(self: any): boolean
	local player = Players.LocalPlayer
	if not player then
		return true
	end
	if Steps.active(player:GetAttribute("TutorialStep")) then
		return false
	end
	return self.money.root.Visible
end

--- Recompute the total and the pill's look; show or hide it.
function BoostPill.refresh(self: any)
	local flags = self:flags()
	local total = math.floor(Money.boost(flags) * 100 + 0.5)
	local vip = flags.vip == true
	self.crown.Visible = vip
	self.arrow.Visible = not vip
	local show = self:allowed() and (total > 0 or P.ShowAtZero)
	if vip ~= self.vipShown then
		self.vipShown = vip
		self:stopLoops()
		if vip then
			local R = P.CrownRock
			table.insert(self.loops, UIAnim.turn(self.crown, 0, R[1], R[2]))
		end
	end
	local old = self.total
	self.total = total
	if old == nil or total <= old or not self.on then
		if self.count then
			self.count.stop()
			self.count = nil
		end
		self.word.Text = COPY.Percent:format(total)
	elseif total > old then
		-- A higher total counts up, then pops.
		if self.count then
			self.count.stop()
		end
		self.count = UIAnim.countUp(old, total, function(value: number)
			self.word.Text = COPY.Percent:format(math.floor(value + 0.5))
		end, P.CountSeconds)
		task.delay(P.CountSeconds, function()
			if self.total == total and self.on then
				local scale = UIAnim.scaleOf(self.tag)
				scale.Scale = P.PopScale
				TweenService:Create(
					scale,
					TweenInfo.new(
						Config.UI.Motion.PopSeconds,
						Enum.EasingStyle.Back,
						Enum.EasingDirection.Out
					),
					{ Scale = 1 }
				):Play()
			end
		end)
	end
	local dim = total == 0
	self.word.TextTransparency = if dim then P.ZeroTransparency else 0
	self.arrow.ImageTransparency = if dim then P.ZeroTransparency else 0
	if show ~= self.on then
		self.on = show
		if show then
			self:layout()
			UIAnim.popIn(self.tag)
			if self.chipOn then
				task.delay(Config.UI.Motion.Stagger, function()
					if self.on and self.chipOn then
						UIAnim.popIn(self.chip)
					end
				end)
			end
		else
			self.pinned = false
			self.card.Visible = false
			UIAnim.popOut(self.tag)
			self.chip.Visible = false
		end
	end
	if self.card.Visible then
		self:fillCard()
	end
	self:layout()
end

function BoostPill.stopLoops(self: any)
	for _, handle in self.loops :: { UIAnim.Handle } do
		handle.stop()
	end
	table.clear(self.loops)
	self.crown.Rotation = 0
end

-- The live rect of a GuiObject in the screen's pixels, or nil when it does not show.
function BoostPill.rectOf(self: any, object: Instance?): HudLayout.Rect?
	if not object or not object:IsA("GuiObject") or not shown(object) then
		return nil
	end
	local size = object.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return nil
	end
	local origin = self.screen.AbsolutePosition
	local at = object.AbsolutePosition - origin
	return { x = at.X, y = at.Y, w = size.X, h = size.Y }
end

-- The WinTrack's visible box: the union of its shown pieces (open bar or folded pill).
function BoostPill.winTrackRect(self: any): HudLayout.Rect?
	local root = self.screen:FindFirstChild("WinTrack")
	if not root or not shown(root) then
		return nil
	end
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, child in root:GetDescendants() do
		if child:IsA("GuiObject") and child.BackgroundTransparency < 1 then
			local r = self:rectOf(child)
			if r then
				x0, y0 = math.min(x0, r.x), math.min(y0, r.y)
				x1, y1 = math.max(x1, r.x + r.w), math.max(y1, r.y + r.h)
			end
		end
	end
	if x0 == math.huge then
		return nil
	end
	return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

-- The pieces around the pill and chip: measured live, else HudLayout's mirror.
function BoostPill.others(self: any, screenSize: HudLayout.Screen): HudLayout.Others
	local scene: HudLayout.Scene =
		{ moneyText = self.money.amount and self.money.amount.Text or "$0" }
	local mirror = HudLayout.others(screenSize, scene)
	local corners = self.screen:FindFirstChild("HubCorners")
	local playerGui = self.screen.Parent
	local hotbarGui = playerGui and playerGui:FindFirstChild("LuckyHotbar")
	local column = self:rectOf(self.screen:FindFirstChild("MenuColumn"))
	return {
		money = self:rectOf(self.money.root) or mirror.money,
		invite = self:rectOf(corners and corners:FindFirstChild("Invite")) or mirror.invite,
		plus = self:rectOf(corners and corners:FindFirstChild("Plus")),
		hotbar = self:rectOf(hotbarGui and hotbarGui:FindFirstChild("Bar")),
		winTrack = if self.chipOn then self:winTrackRect() else nil,
		column = column,
	}
end

--- Size and place the pill, the chip and the card (HudLayout, from the live rects).
function BoostPill.layout(self: any)
	local screen = self.screen
	if not screen or screen.AbsoluteSize.X <= 0 then
		return
	end
	local size = { w = screen.AbsoluteSize.X, h = screen.AbsoluteSize.Y }
	local short = HudLayout.short(size)
	local scene: HudLayout.Scene = { chipText = if self.chipOn then self.chipWords else nil }
	local others = self:others(size)
	local b = HudLayout.boost(size, scene, others)
	self.lastLayout = { others = others, boost = b, size = size }
	local root: GuiObject = self.money.root
	local origin = root.AbsolutePosition - screen.AbsolutePosition

	-- The pill.
	local pill = b.pill
	self.tag.Position = UDim2.fromOffset(pill.x - origin.X, pill.y - origin.Y)
	self.tag.Size = UDim2.fromOffset(pill.w, pill.h)
	local iconPx = math.floor(pill.h * P.IconShare)
	for _, icon in { self.crown, self.arrow } do
		icon.Position = UDim2.new(0, P.PadPx + iconPx / 2, 0.5, 0)
		icon.Size = UDim2.fromOffset(iconPx, iconPx)
	end
	HudParts.setTextSize(self.word, b.pillTextPx)
	self.word.Position = UDim2.new(0, P.PadPx + iconPx + P.InnerGapPx, 0.5, 0)
	self.word.Size = UDim2.fromOffset(pill.w - 2 * P.PadPx - iconPx - P.InnerGapPx, pill.h)

	-- The chip.
	local chip = b.chip
	if chip then
		self.chip.Position = UDim2.fromOffset(chip.x - origin.X, chip.y - origin.Y)
		self.chip.Size = UDim2.fromOffset(chip.w, chip.h)
		local icon = candyIcon()
		local chipIconPx = if icon then math.floor(chip.h * CHIP.IconShare) else 0
		self.chipIcon.Image = icon or ""
		self.chipIcon.Visible = icon ~= nil
		self.chipIcon.Position = UDim2.new(0, CHIP.PadPx + chipIconPx / 2, 0.5, 0)
		self.chipIcon.Size = UDim2.fromOffset(chipIconPx, chipIconPx)
		local textX = CHIP.PadPx + (if icon then chipIconPx + CHIP.InnerGapPx else 0)
		self.chipText.Text = b.chipText or ""
		HudParts.setTextSize(self.chipText, b.chipTextPx, CHIP.MinTextPx)
		self.chipText.Position = UDim2.new(0, textX, 0.5, 0)
		self.chipText.Size = UDim2.fromOffset(chip.w - textX - CHIP.PadPx, chip.h)
		self.chipText.TextXAlignment = if icon
			then Enum.TextXAlignment.Left
			else Enum.TextXAlignment.Center
	end

	-- The card over the pill, inside the screen (its rows were laid out by fillCard).
	local cardW = self.cardW or (if short then K.ShortWidthPx else K.WidthPx)
	local maxX = math.max(0, size.w - cardW)
	local dx = math.clamp(pill.x, 0, maxX) - pill.x
	self.card.Position = UDim2.fromOffset(dx, -K.AbovePx)
end

--------------------------------------------------------------------------------------------
-- The card
--------------------------------------------------------------------------------------------

-- Time left in a timed part ("42m"), or nil.
local function timeLeft(kind: string, at: number): string?
	local player = Players.LocalPlayer
	local ends = if kind == "Starter" and player
		then player:GetAttribute("MoneyBoostEnds")
		elseif kind == "Party" then workspace:GetAttribute("MoneyPartyEndsAt")
		else nil
	if type(ends) ~= "number" or ends <= at then
		return nil
	end
	return ShopParts.timeLeft(ends - at)
end

-- One row: an icon, the words, the value on the right.
function BoostPill.row(self: any, index: number): any
	local row = self.rows[index]
	if row then
		return row
	end
	local icon = HudParts.icon(self.card, "Crown", "Icon" .. index)
	icon.ZIndex = P.ZIndex + 3
	local words = HudParts.note(self.card, "Words" .. index, K.TextPx, "")
	words.TextWrapped = false
	words.TextXAlignment = Enum.TextXAlignment.Left
	words.ZIndex = P.ZIndex + 3
	local value = HudParts.note(self.card, "Value" .. index, K.TextPx, "")
	value.AutoLocalize = false
	value.TextWrapped = false
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.ZIndex = P.ZIndex + 3
	row = { icon = icon, words = words, value = value }
	self.rows[index] = row
	return row
end

-- What the card says now: { icon?, words, value?, kind ("Part", "Note", "Get") }.
function BoostPill.cardLines(self: any): { any }
	local flags = self:flags()
	local at = workspace:GetServerTimeNow()
	local lines: { any } = {}
	local parts = Money.boostParts(flags)
	for _, part in parts do
		local words = PARTS[part.kind] or part.kind
		if part.kind == "Friends" then
			local n = if type(flags.friends) == "number" then math.floor(flags.friends) else 0
			words = words:format(n)
		end
		local left = timeLeft(part.kind, at)
		if left then
			words ..= " · " .. COPY.TimeLeft:format(left)
		end
		table.insert(lines, {
			icon = ICONS[part.kind],
			words = words,
			value = percent(part.add),
			kind = part.kind,
			line = "Part",
		})
	end
	if #parts == 0 then
		table.insert(lines, { words = COPY.None, line = "Note" })
	end
	self.partsTotal = Money.boost(flags)
	return lines
end

-- The lines under the total: the friend rule, the Candy line, the boosts still to get.
function BoostPill.footLines(self: any, room: boolean): { string }
	local flags = self:flags()
	local lines = {}
	if E.FriendBoostEnabled == true then
		table.insert(
			lines,
			COPY.FriendRule:format(math.floor(E.FriendBoost * 100 + 0.5), E.FriendBoostMaxFriends)
		)
	end
	if EventModule and type(EventModule.isLive) == "function" then
		local ok, live = pcall(EventModule.isLive, now())
		if ok and live == true then
			table.insert(lines, COPY.CandyToo)
		end
	end
	if room then
		if flags.group ~= true then
			table.insert(lines, COPY.Get.Group:format(math.floor(E.GroupBoost * 100 + 0.5)))
		end
		local friends = if type(flags.friends) == "number" then flags.friends else 0
		if E.FriendBoostEnabled == true and friends < E.FriendBoostMaxFriends then
			table.insert(lines, COPY.Get.Friends:format(math.floor(E.FriendBoost * 100 + 0.5)))
		end
		if flags.vip ~= true then
			table.insert(lines, COPY.Get.Vip:format(math.floor(E.VipBoost * 100 + 0.5)))
		end
	end
	return lines
end

--- Fill and size the card: the title, a row per part, the rule, the total, the foot lines.
function BoostPill.fillCard(self: any)
	local lines = self:cardLines()
	local screen = self.screen
	local short = screen ~= nil
		and HudLayout.short({ w = screen.AbsoluteSize.X, h = screen.AbsoluteSize.Y })
	-- The room over the pill: the grey "could get" rows go when the card would not fit.
	local room = math.huge
	if self.tag.AbsoluteSize.Y > 0 and screen then
		room = self.tag.AbsolutePosition.Y - screen.AbsolutePosition.Y - K.AbovePx
	end
	local function heightFor(feet: number): number
		return K.PadPx
			+ K.TitlePx
			+ 4
			+ K.GapPx
			+ #lines * K.RowPx
			+ K.GapPx
			+ K.RulePx
			+ K.GapPx
			+ K.TotalPx
			+ 4
			+ feet * (K.NotePx + 4)
			+ K.PadPx
	end
	local feet = self:footLines(true)
	if heightFor(#feet) > room then
		feet = self:footLines(false)
	end
	-- Width: the widest row, at least the card's width for this screen.
	local widest = ShopParts.textWidth(COPY.Title, K.TitlePx)
	for _, line in lines do
		local w = ShopParts.textWidth(line.words, K.TextPx)
			+ (if line.value then K.GapPx * 3 + ShopParts.textWidth(line.value, K.TextPx) else 0)
			+ (if line.icon then K.IconPx + K.GapPx else 0)
		widest = math.max(widest, w)
	end
	for _, text in feet do
		widest = math.max(widest, ShopParts.textWidth(text, K.NotePx))
	end
	local cardW =
		math.max(if short then K.ShortWidthPx else K.WidthPx, math.ceil(widest) + 2 * K.PadPx + 4)
	self.cardW = cardW
	local inner = cardW - 2 * K.PadPx
	local y = K.PadPx
	self.title.Position = UDim2.fromOffset(K.PadPx, y)
	self.title.Size = UDim2.fromOffset(inner, K.TitlePx + 4)
	y += K.TitlePx + 4 + K.GapPx
	local used = 0
	for index, line in lines do
		used = index
		local row = self:row(index)
		row.icon.Visible = line.icon ~= nil
		if line.icon then
			HudParts.setIcon(row.icon, line.icon)
		end
		row.icon.Position = UDim2.fromOffset(K.PadPx, y + (K.RowPx - K.IconPx) / 2)
		row.icon.Size = UDim2.fromOffset(K.IconPx, K.IconPx)
		local textX = K.PadPx + (if line.icon then K.IconPx + K.GapPx else 0)
		row.words.Text = line.words
		row.words.Visible = true
		row.words.TextColor3 = if line.line == "Note"
			then rgb(K.Grey)
			else rgb(Config.UI.Kit.Colors.Ink)
		row.words.Position = UDim2.fromOffset(textX, y)
		row.words.Size = UDim2.fromOffset(cardW - K.PadPx - textX, K.RowPx)
		row.value.Text = line.value or ""
		row.value.Visible = line.value ~= nil
		row.value.TextColor3 = rgb(K.ValueGreen)
		row.value.Position = UDim2.fromOffset(K.PadPx, y)
		row.value.Size = UDim2.fromOffset(inner, K.RowPx)
		row.kind = line.kind
		y += K.RowPx
	end
	for index = used + 1, #self.rows do
		local row = self.rows[index]
		row.icon.Visible = false
		row.words.Visible = false
		row.value.Visible = false
		row.kind = nil
	end
	y += K.GapPx
	self.rule.Position = UDim2.fromOffset(K.PadPx, y)
	self.rule.Size = UDim2.fromOffset(inner, K.RulePx)
	y += K.RulePx + K.GapPx
	self.totalWord.Position = UDim2.fromOffset(K.PadPx, y)
	self.totalWord.Size = UDim2.fromOffset(inner, K.TotalPx + 4)
	self.totalValue.Text = percent(self.partsTotal or 0)
	self.totalValue.Position = UDim2.fromOffset(K.PadPx, y)
	self.totalValue.Size = UDim2.fromOffset(inner, K.TotalPx + 4)
	y += K.TotalPx + 4
	self.feet = self.feet or {}
	for index, text in feet do
		local label = self.feet[index]
		if not label then
			label = HudParts.note(self.card, "Foot" .. index, K.NotePx, "")
			label.TextWrapped = false
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextColor3 = rgb(K.Grey)
			label.ZIndex = P.ZIndex + 3
			self.feet[index] = label
		end
		label.Text = text
		label.Visible = true
		label.Position = UDim2.fromOffset(K.PadPx, y)
		label.Size = UDim2.fromOffset(inner, K.NotePx + 4)
		y += K.NotePx + 4
	end
	for index = #feet + 1, #self.feet do
		self.feet[index].Visible = false
	end
	self.card.Size = UDim2.fromOffset(cardW, y + K.PadPx)
	self:layout()
end

-- The card in: popped for a hover, slammed when `big` (VIP just bought).
function BoostPill.showCard(self: any, big: boolean)
	if not self.on then
		return
	end
	self:fillCard()
	if big then
		UIAnim.slam(self.card, nil, { burst = false, shake = "Nudge" })
	elseif not self.card.Visible then
		UIAnim.popIn(self.card)
	end
	if not self.reportedCard then
		-- The BoostCard custom event (TutorialService's FUNNEL_EVENTS), once a session.
		self.reportedCard = true
		pcall(function()
			Net.get("TutorialEvent"):FireServer("BoostCardOpened")
		end)
	end
end

function BoostPill.hideCard(self: any)
	if self.card.Visible then
		UIAnim.popOut(self.card)
	end
end

-- Open the card for `seconds`, then close it unless the pointer is on the pill.
function BoostPill.pin(self: any, seconds: number, big: boolean?)
	self.pinned = true
	self.pinToken += 1
	local token = self.pinToken
	self:showCard(big == true)
	task.delay(seconds, function()
		if self.pinToken == token and self.pinned then
			self.pinned = false
			if not self.hovered then
				self:hideCard()
			end
		end
	end)
end

--- A click, tap or A on the pill: pin the card open, or close it.
function BoostPill.press(self: any)
	if self.inMatch or not self.on then
		return
	end
	UISound.play("Click")
	if self.pinned then
		self.pinned = false
		self:hideCard()
	else
		self:pin(P.PinSeconds)
	end
end

--- Whether the card is open (HubCorners: B closes it first).
function BoostPill.cardOpen(self: any): boolean
	return self.card.Visible
end

--- Close the card (B on a pad).
function BoostPill.closeCard(self: any)
	self.pinned = false
	self.pinToken += 1
	self:hideCard()
end

--------------------------------------------------------------------------------------------
-- The VIP tag's shape
--------------------------------------------------------------------------------------------

--- The pill's top edge in screen pixels while it shows (MenuColumn keeps above it), else nil.
function BoostPill.top(self: any): number?
	if self.on and self.tag.Visible and self.tag.AbsoluteSize.Y > 0 then
		local top = self.tag.AbsolutePosition.Y
		if self.chip.Visible and self.chip.AbsoluteSize.Y > 0 then
			top = math.min(top, self.chip.AbsolutePosition.Y)
		end
		return top
	end
	return nil
end

--- In a match the pill still shows but takes no input, and an open card shuts.
function BoostPill.setInMatch(self: any, on: boolean)
	if on == self.inMatch then
		return
	end
	self.inMatch = on
	self.tag.Active = not on
	if on then
		self.pinned = false
		self.pinToken += 1
		self:hideCard()
	end
end

--- VIP was just bought: the pill shows its new total and the card slams in, the VIP row
--- flashing gold.
function BoostPill.showPerks(self: any)
	self:refresh()
	if not self.on then
		return
	end
	self:pin(P.PurchaseSeconds, true)
	for _, row in self.rows do
		if row.kind == "Vip" and row.words.Visible then
			local gold = rgb(K.Gold)
			local ink = rgb(Config.UI.Kit.Colors.Ink)
			row.words.TextColor3 = gold
			TweenService:Create(
				row.words,
				TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 5, true),
				{ TextColor3 = ink }
			):Play()
		end
	end
end

--------------------------------------------------------------------------------------------
-- The Rush chip
--------------------------------------------------------------------------------------------

local RushChipModule: any = nil
local rushLooked = false

-- Core's chip words now, or nil (missing module, an error or nil all hide the chip).
function BoostPill.rushContent(self: any): string?
	if self.chipFake ~= nil then
		return if self.chipFake == "" then nil else self.chipFake
	end
	if not rushLooked then
		rushLooked = true
		RushChipModule = optional(function()
			local folder = script.Parent:FindFirstChild("Halloween")
			local module = folder and folder:FindFirstChild("RushChip")
			return if module then (require :: any)(module) else nil
		end)
	end
	local module = RushChipModule
	if not module or type(module.content) ~= "function" then
		return nil
	end
	local ok, content = pcall(module.content, now())
	if not ok then
		if not self.rushWarned then
			self.rushWarned = true
			warn(("[8ball] BoostPill: RushChip.content failed: %s"):format(tostring(content)))
		end
		return nil
	end
	if type(content) == "table" and type(content.text) == "string" and content.text ~= "" then
		return content.text
	end
	return nil
end

--- Once a second: the chip's words, the timed parts, and a relayout if anything moved.
function BoostPill.tick(self: any)
	local words = self:rushContent()
	local on = words ~= nil
	if on then
		self.chipWords = words
	end
	if on ~= self.chipOn then
		self.chipOn = on
		self:layout()
		if on and self.on then
			UIAnim.popIn(self.chip)
			self:breathe(true)
		else
			self:breathe(false)
			self.chip.Visible = false
		end
	elseif on then
		self:layout() -- the words tick (never re-pops)
	end
	-- A timed part (Starter, Party) runs: its end and countdown.
	local flags = self:flags()
	local timed = flags.starter == true or flags.party == true
	if timed or self.timed then
		self.timed = timed
		self:refresh()
	elseif self.on then
		self:layout() -- the pieces around it may have moved (a hotbar, the column)
	end
end

-- The chip's colour breathes gently while it shows (its scale never: text never pulses).
function BoostPill.breathe(self: any, on: boolean)
	if self.chipBreath then
		self.chipBreath:Cancel()
		self.chipBreath = nil
	end
	local base = rgb(CHIP.Color)
	self.chip.BackgroundColor3 = base
	if on and not UIAnim.reduced() then
		local light = base:Lerp(Color3.new(1, 1, 1), CHIP.BreatheLighten)
		local tween = TweenService:Create(
			self.chip,
			TweenInfo.new(
				CHIP.PulseSeconds / 2,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut,
				-1,
				true
			),
			{ BackgroundColor3 = light }
		)
		tween:Play()
		self.chipBreath = tween
	end
end

--------------------------------------------------------------------------------------------
-- Studio checks
--------------------------------------------------------------------------------------------

function BoostPill.addQA(self: any)
	-- ("boosts", { vip, group, plus, friends, starter, party } | nil): fake the shown flags.
	GuiQA.add("boosts", function(flags: any)
		self.fake = if type(flags) == "table" then flags else nil
		self:refresh()
		return self.word.Text
	end)
	-- ("boostCard", open?): pin the card open (false: close).
	GuiQA.add("boostCard", function(open: boolean?)
		if open == false then
			self:closeCard()
		else
			self:pin(P.PinSeconds * 10)
		end
		return self.card.Visible
	end)
	GuiQA.add("boostPerks", function()
		self:showPerks()
		return self.card.Visible
	end)
	-- ("rushChip", text?): the chip's words instead of core's ("" hides it; nil: core's again).
	GuiQA.add("rushChip", function(text: string?)
		self.chipFake = text
		self:tick()
		return self.chip.Visible, self.chipText.Text
	end)
	-- The live rects of the pill, the chip and the pieces around them.
	GuiQA.add("hudRects", function()
		self:layout()
		local last = self.lastLayout
		if not last then
			return nil
		end
		local o = last.others
		return {
			pill = self:rectOf(self.tag),
			chip = self:rectOf(self.chip),
			card = self:rectOf(self.card),
			money = o.money,
			invite = o.invite,
			plus = o.plus,
			hotbar = o.hotbar,
			winTrack = self:winTrackRect(),
			column = o.column,
			screen = last.size,
			chipText = self.chipText.Text,
		}
	end)
	-- The pairs (pill or chip, another piece) that touch or overlap now.
	GuiQA.add("hudOverlap", function()
		self:layout()
		local last = self.lastLayout
		if not last then
			return {}
		end
		local o = last.others
		local found = {}
		local theirs = {}
		for _, pair in
			{
				{ "money", o.money },
				{ "invite", o.invite },
				{ "plus", o.plus },
				{ "hotbar", o.hotbar },
				{ "winTrack", self:winTrackRect() },
				{ "column", o.column },
			} :: { any }
		do
			if pair[2] then
				table.insert(theirs, { name = pair[1], rect = pair[2] })
			end
		end
		for _, mine in
			{ { "pill", self:rectOf(self.tag) }, { "chip", self:rectOf(self.chip) } } :: { any }
		do
			if mine[2] then
				for _, other in theirs do
					for _, hit in
						HudLayout.overlaps({ { name = mine[1], rect = mine[2] }, other }, 0)
					do
						table.insert(found, hit[1] .. " x " .. hit[2])
					end
				end
			end
		end
		return found
	end)
end

return BoostPill
