--!strict
-- MoneyHud: your money, bottom left, always on screen (in matches too): the cash stack over
-- the left end of a white kit pill with the total, "$1,250" (Progression/Format: commas, then
-- "$12.5M" from ten million). Tuning in Config.UI.Progress.MoneyHud.
--
-- The saved total is the local player's `Money` attribute (the server sets it), but the shown
-- number only rises when a flying cash chip lands (CashFlyer, the result screen, NEW RANK!),
-- so you watch it go up as the chips arrive. Whoever launches a chip calls expect() at once and
-- land() on arrival. When the attribute changes the HUD waits: while chips are on their way
-- their landings raise it; once none are, it counts to the true value after SettleDelaySeconds
-- (up or down), so it can never drift. A landing never lifts it past the true value (a preview's
-- made-up money only bumps the icon).
--
-- Small and tight in the corner. The one thing in it that takes input is the gold "+" at the
-- pill's right end (designer, 2026-10-04): it opens the Shop on its Money tab (Menus; nothing
-- happens while menus are blocked, in a match). Hidden until the save is loaded
-- (`DataLoaded`), then it starts at the saved total with no animation.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local Menus = require(script.Parent.Menus)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local C = Config.UI.Progress.MoneyHud
local MoneyHud = {}
MoneyHud.__index = MoneyHud

export type MoneyHud = {
	iconCenter: (self: MoneyHud) -> Vector2,
	expect: (self: MoneyHud, amount: number) -> (),
	release: (self: MoneyHud, amount: number) -> (),
	land: (self: MoneyHud, amount: number) -> (),
	destroy: (self: MoneyHud) -> (),
}

-- A whole, finite, non-negative amount (anything else counts as nothing).
local function clean(amount: any): number
	if type(amount) ~= "number" or amount ~= amount or amount == math.huge or amount <= 0 then
		return 0
	end
	return math.floor(amount)
end

-- The saved total, as the server last set it (0 before it is known).
local function savedMoney(): number
	local player = Players.LocalPlayer
	local value = if player then player:GetAttribute("Money") else nil
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return 0
	end
	return math.floor(value)
end

--- The money HUD, built into `screen` (UI.screen()).
function MoneyHud.new(screen: ScreenGui): MoneyHud
	local self: any = setmetatable({}, MoneyHud)
	self.alive = true
	self.screen = screen
	self.connections = {}
	self.loaded = false
	self.shown = 0 -- the number on screen (may be mid-count)
	self.target = 0 -- what it is counting to
	self.pending = 0 -- money in chips said to be on their way
	self.activity = os.clock() -- the last expect or land, to forget chips that never land
	self.settleToken = 0
	self.lastTick = 0
	self.textLength = -1
	self.count = nil :: RBXScriptConnection?

	local root = HudParts.frame(screen, "MoneyHud")
	root.AnchorPoint = Vector2.new(0, 1)
	root.ZIndex = C.ZIndex
	root.Visible = false
	self.root = root
	self.pill = HudParts.pill(root, "Pill")
	self.pill.ZIndex = 1
	self.amount = HudParts.text(self.pill, "Amount", C.TextPx, "")
	self.amount.AutoLocalize = false -- only a number
	self.amount.TextWrapped = false
	self.amount.TextXAlignment = Enum.TextXAlignment.Left
	self.icon = HudParts.icon(root, "CashStack", "CashIcon")
	self.icon.ZIndex = 2
	-- The "+": a round gold candy with a big plus, over the pill's right end.
	local plus = HudParts.candy(root, "+", function()
		UISound.play("Click")
		Menus.open("Shop", "Money")
	end, "Yellow")
	plus.Name = "Plus"
	plus.ZIndex = 3
	plus.Selectable = false -- a gamepad never lands on it (the menus have their own way in)
	local parts = HudParts.candyParts(plus)
	if parts then
		parts.label.AutoLocalize = false
	end
	self.plus = plus
	self.plusBob = UIAnim.bob(plus)

	table.insert(
		self.connections,
		screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:layout()
		end)
	)
	local player = Players.LocalPlayer
	if player then
		table.insert(
			self.connections,
			player:GetAttributeChangedSignal("Money"):Connect(function()
				self:scheduleSettle()
			end)
		)
		table.insert(
			self.connections,
			player:GetAttributeChangedSignal("DataLoaded"):Connect(function()
				self:checkLoaded()
			end)
		)
		self:checkLoaded()
	else
		-- An Edit-mode preview of the screens: no player, no save.
		self.loaded = true
		self.root.Visible = true
		self:setShown(0)
	end
	self:layout()
	return self
end

-- Shown once the save is loaded, starting at the saved total with no animation.
function MoneyHud.checkLoaded(self: any)
	local player = Players.LocalPlayer
	if self.loaded or not player or player:GetAttribute("DataLoaded") ~= true then
		return
	end
	self.loaded = true
	local money = savedMoney()
	self.target = money
	self:setShown(money)
	self.root.Visible = true
end

-- Put a value on screen; the pill grows or shrinks with the number's length.
function MoneyHud.setShown(self: any, value: number)
	self.shown = value
	local words = Format.money(math.floor(value + 0.5))
	if self.amount.Text ~= words then
		self.amount.Text = words
		if #words ~= self.textLength then
			self.textLength = #words
			self:layout()
		end
	end
end

function MoneyHud.layout(self: any)
	local size = self.screen.AbsoluteSize
	if size.Y <= 0 then
		return
	end
	local short = size.Y < Config.Multiplayer.Style.ShortHeight
	local margin = if short then C.ShortMarginPx else C.MarginPx
	local pillHeight = if short then C.ShortPillHeightPx else C.PillHeightPx
	local iconSize = if short then C.ShortIconSizePx else C.IconSizePx
	local textSize = if short then C.ShortTextPx else C.TextPx
	HudParts.setTextSize(self.amount, textSize)
	local over = math.floor(iconSize * C.IconOverPill)
	local pillLeft = iconSize - over
	local words = TextService:GetTextSize(
		self.amount.Text,
		textSize,
		HudParts.measureFont(self.amount),
		Vector2.new(10000, 1000)
	).X
	local plusSize = if short then C.ShortPlusPx else C.PlusPx
	local plusOver = math.floor(plusSize * C.PlusOverPill)
	local pillWidth = over + 4 + words + C.TextPadPx + plusOver
	self.root.Position = UDim2.new(0, margin, 1, -margin)
	self.root.Size = UDim2.fromOffset(pillLeft + pillWidth + (plusSize - plusOver), iconSize)
	self.pill.Position = UDim2.fromOffset(pillLeft, math.floor((iconSize - pillHeight) / 2))
	self.pill.Size = UDim2.fromOffset(pillWidth, pillHeight)
	self.amount.Position = UDim2.fromOffset(over + 4, 1)
	self.amount.Size = UDim2.fromOffset(words + C.TextPadPx / 2, pillHeight - 2)
	self.icon.Position = UDim2.fromOffset(0, 0)
	self.icon.Size = UDim2.fromOffset(iconSize, iconSize)
	local plus: TextButton = self.plus
	plus.Position =
		UDim2.fromOffset(pillLeft + pillWidth - plusOver, math.floor((iconSize - plusSize) / 2))
	plus.Size = UDim2.fromOffset(plusSize, plusSize)
	HudParts.setButtonTextSize(plus, if short then C.ShortPlusTextPx else C.PlusTextPx)
	HudParts.setMinHit(plus, Config.UI.Menu.Frame.TouchMinPx)
end

-- Count the shown number to `to` over `seconds`, easing out, from wherever it is now (a new
-- target mid-count carries on from the current value). Rising counts tick.
function MoneyHud.countTo(self: any, to: number, seconds: number)
	self.target = to
	if self.count then
		self.count:Disconnect()
		self.count = nil
	end
	local from = self.shown
	if from == to or seconds <= 0 then
		self:setShown(to)
		return
	end
	local started = os.clock()
	local last = math.floor(from + 0.5)
	self.count = RunService.RenderStepped:Connect(function()
		local t = math.min(1, (os.clock() - started) / seconds)
		local value = from + (to - from) * UIAnim.quadOut(t)
		self:setShown(if t >= 1 then to else value)
		local whole = math.floor(self.shown + 0.5)
		if whole > last then
			local now = os.clock()
			if now - self.lastTick >= Config.Audio.MoneyTickEvery then
				self.lastTick = now
				UISound.play("MoneyTick")
			end
		end
		last = whole
		if t >= 1 and self.count then
			self.count:Disconnect()
			self.count = nil
		end
	end)
end

-- After a quiet moment, count to the true total, unless chips are still on their way.
function MoneyHud.scheduleSettle(self: any)
	self.settleToken += 1
	local token = self.settleToken
	task.delay(C.SettleDelaySeconds, function()
		if self.alive and self.settleToken == token then
			self:settle()
		end
	end)
end

function MoneyHud.settle(self: any)
	if not self.loaded then
		return
	end
	if self.pending > 0 then
		if os.clock() - self.activity < C.PendingTimeoutSeconds then
			self:scheduleSettle() -- look again once they have had time to land
			return
		end
		self.pending = 0 -- they never came: stop waiting for them
	end
	local truth = savedMoney()
	if truth ~= self.target then
		self:countTo(truth, C.SettleCountSeconds)
	end
end

-- A few twinkles pop round the icon.
function MoneyHud.sparkle(self: any)
	local image = Config.UI.Ranks.Sparkle
	if type(image) ~= "string" or image == "" then
		return
	end
	local centre = self.icon.Position.X.Offset + self.icon.Size.X.Offset / 2
	local middle = self.icon.Position.Y.Offset + self.icon.Size.Y.Offset / 2
	local random = Random.new()
	for i = 1, C.Sparkles do
		local angle = (i / C.Sparkles) * math.pi * 2 + random:NextNumber(-0.5, 0.5)
		local reach = C.SparkleSpreadPx * random:NextNumber(0.6, 1)
		local star = Instance.new("ImageLabel")
		star.Name = "Sparkle"
		star.BackgroundTransparency = 1
		star.Image = image
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Position =
			UDim2.fromOffset(centre + math.cos(angle) * reach, middle + math.sin(angle) * reach)
		star.Size = UDim2.fromOffset(0, 0)
		star.Rotation = random:NextNumber(0, 90)
		star.ZIndex = 3
		star.Parent = self.root
		local half = C.SparkleSeconds / 2
		local grow = TweenService:Create(
			star,
			TweenInfo.new(
				half,
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out,
				0,
				false,
				(i - 1) * 0.04
			),
			{
				Size = UDim2.fromOffset(C.SparkleSizePx, C.SparkleSizePx),
				Rotation = star.Rotation + 45,
			}
		)
		grow.Completed:Connect(function()
			local shrink = TweenService:Create(
				star,
				TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = UDim2.fromOffset(0, 0), ImageTransparency = 1 }
			)
			shrink.Completed:Connect(function()
				star:Destroy()
			end)
			shrink:Play()
		end)
		grow:Play()
	end
end

--- Where chips land: the absolute screen position of the cash icon's centre.
function MoneyHud.iconCenter(self: any): Vector2
	return self.icon.AbsolutePosition + self.icon.AbsoluteSize / 2
end

--- A chip worth `amount` is on its way: the HUD waits for it before settling.
function MoneyHud.expect(self: any, amount: number)
	local n = clean(amount)
	if not self.alive or n <= 0 then
		return
	end
	self.pending += n
	self.activity = os.clock()
end

--- A chip said to be coming (expect) will not come after all, or comes as another chip (which
--- calls expect itself): stop waiting for `amount`. The HUD then settles as usual.
function MoneyHud.release(self: any, amount: number)
	local n = clean(amount)
	if not self.alive or n <= 0 then
		return
	end
	self.pending = math.max(0, self.pending - n)
	self:scheduleSettle()
end

--- A chip landed: the icon bumps, a few sparkles pop and the number counts up by `amount`
--- (never past the saved total). Call it once for every expect(), with the same amount.
function MoneyHud.land(self: any, amount: number)
	if not self.alive then
		return
	end
	local n = clean(amount)
	self.pending = math.max(0, self.pending - n)
	self.activity = os.clock()
	if n > 0 and self.loaded then
		local truth = if Players.LocalPlayer then savedMoney() else math.huge
		local to = self.target + n
		if to > truth then
			to = math.max(self.target, truth)
		end
		if to ~= self.target then
			self:countTo(to, C.LandCountSeconds)
		end
	end
	UIAnim.bounce(self.icon)
	self:sparkle()
	UISound.play("CashLand")
	self:scheduleSettle()
end

function MoneyHud.destroy(self: any)
	if not self.alive then
		return
	end
	self.alive = false
	if self.count then
		self.count:Disconnect()
		self.count = nil
	end
	if self.plusBob then
		self.plusBob.stop()
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.root:Destroy()
end

return MoneyHud
