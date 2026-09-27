--!strict
-- NewRankPopup: the rank-change popups, one at a time (a second one waits its turn).
-- - "Up": NEW RANK! A big popup over a dim: "NEW RANK!" in big gold kit text, the new badge
--   large (about 40% of the screen's short side) with gold rays turning behind it, its shine and
--   a burst, confetti, the rank's name ("Gold IV"), the reward chip ("+$200" with the cash)
--   that then flies into the money HUD, and Continue. It closes itself after a few seconds.
-- - A new tier (Gold V to Platinum I; Unranked to Bronze I counts): the bigger version. The old
--   badge shows first, then spins away into the new one, the tier's name goes huge
--   ("PLATINUM!"), more confetti and the bigger fanfare.
-- - "Down": a small quiet card at the top, "Rank down: Expert II" with the new badge small; no
--   dim, no fanfare, no input, gone after a moment.
-- Tuning in Config.UI.Progress.NewRank; laid out at a natural size and scaled to the screen.
--
-- Money: a rank-up's reward is already in the save when this shows (the server paid it). For a
-- /xp rank-up the chip flies into the HUD here (the HUD is told the moment the popup is asked
-- for); after the result screen (`paid`, it flew with the total chip) and for a /newrank preview
-- (`preview`, nothing was paid) the chip only shows.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local ProgressionRules = Shared:WaitForChild("Progression")
local Format = require(ProgressionRules:WaitForChild("Format"))
local Ranks = require(ProgressionRules:WaitForChild("Ranks"))
local HudParts = require(script.Parent.HudParts)
local RankBadge = require(script.Parent.RankBadge)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local C = Config.UI.Progress.NewRank
local K = Config.UI.Kit
local P = Strings.Progress
local NewRankPopup = {}
NewRankPopup.__index = NewRankPopup

export type NewRankPopup = {
	show: (self: NewRankPopup, event: any, onDone: (() -> ())?) -> (),
	isOpen: (self: NewRankPopup) -> boolean,
	destroy: (self: NewRankPopup) -> (),
}

local tone = HudParts.tone
local frame = HudParts.frame

-- A and B close NEW RANK! (above the game's own gamepad binding, Input.luau).
local ACTION = "8ballNewRankPopup"

-- A whole, finite, non-negative amount (anything else counts as nothing).
local function clean(amount: any): number
	if type(amount) ~= "number" or amount ~= amount or amount == math.huge or amount <= 0 then
		return 0
	end
	return math.floor(amount)
end

-- A rank from an event (tier and division), safe to show whatever arrived.
local function rankOf(rank: any): (string, number)
	local r: any = if type(rank) == "table" then rank else {}
	return if type(r.tier) == "string" then r.tier else "Unranked",
		if type(r.division) == "number" then r.division else 0
end

local function nameOf(rank: any): string
	local tier, division = rankOf(rank)
	return Ranks.name({ tier = tier, division = division, index = 0, xpInDivision = 0 })
end

--- The popups, built into `screen` (UI.screen()). Reward chips fly with `flyer` into `money`.
function NewRankPopup.new(screen: ScreenGui, flyer: any, money: any): NewRankPopup
	local self: any = setmetatable({}, NewRankPopup)
	self.alive = true
	self.flyer = flyer
	self.money = money
	self.queue = {}
	self.view = nil
	self.root = frame(screen, "NewRankPopup")
	self.root.Size = UDim2.fromScale(1, 1)
	self.root.ZIndex = C.ZIndex
	self.root.Visible = false
	self.sizeChanged = self.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layout()
	end)
	return self
end

--- Show a rank change: `event` = {kind = "Up" | "Down", before, after (ranks: tier and
--- division), reward, newTier, preview?, paid?} (the server's RankEvent, or the result screen
--- after a match). `onDone` runs once it has closed. One at a time: a second one waits.
function NewRankPopup.show(self: any, event: any, onDone: (() -> ())?)
	if not self.alive or type(event) ~= "table" or type(event.after) ~= "table" then
		if onDone then
			task.spawn(onDone)
		end
		return
	end
	local up = event.kind ~= "Down"
	local reward = if up then clean(event.reward) else 0
	-- A real rank-up's reward flies in: the HUD waits for it from now.
	local owed = reward > 0 and event.paid ~= true and event.preview ~= true
	if owed then
		self.money:expect(reward)
	end
	table.insert(self.queue, { event = event, onDone = onDone, reward = reward, owed = owed })
	if not self.view then
		self:nextOne()
	end
end

function NewRankPopup.nextOne(self: any)
	local item = table.remove(self.queue, 1)
	if not item or not self.alive then
		return
	end
	local ok, problem = pcall(function()
		if item.event.kind == "Down" then
			self:openDown(item)
		else
			self:openUp(item)
		end
	end)
	if not ok then
		-- Never left half-open (it would hold every later popup back): skip this one.
		warn("[8ball] NewRankPopup: " .. tostring(problem))
		ContextActionService:UnbindAction(ACTION)
		local view = self.view
		if view and not view.finished then
			view.closing = true
			if item.owed then
				item.owed = false
				self.money:land(item.reward)
			end
			self:finish(view)
		else
			if item.owed then
				item.owed = false
				self.money:land(item.reward)
			end
			if item.onDone then
				task.spawn(item.onDone)
			end
			self:nextOne()
		end
	end
end

--------------------------------------------------------------------------------------------
-- NEW RANK!
--------------------------------------------------------------------------------------------

function NewRankPopup.openUp(self: any, item: any)
	local event = item.event
	local newTier = event.newTier == true
	local tier, division = rankOf(event.after)
	local view: any = {
		item = item,
		kind = "Up",
		newTier = newTier,
		started = os.clock(),
		closing = false,
		burst = false,
		chipSent = false,
		continueShown = false,
		badges = {},
	}
	-- A new tier's old badge spins away first; the burst comes when the new one arrives.
	view.burstAt = if newTier then C.TierHoldSeconds + C.TierSpinSeconds else C.BurstAt
	view.rewardAt = view.burstAt + (C.RewardAt - C.BurstAt)
	view.continueAt = view.burstAt + C.ContinueAfterSeconds
	view.closeAt = C.AutoCloseSeconds + (view.burstAt - C.BurstAt)
	self.view = view

	local root = frame(self.root, "NewRank")
	root.Size = UDim2.fromScale(1, 1)
	view.root = root
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BorderSizePixel = 0
	backdrop.BackgroundColor3 = tone("Ink")
	backdrop.BackgroundTransparency = 1
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Selectable = false
	backdrop.Active = true
	backdrop.Modal = true -- frees a locked mouse
	backdrop.ZIndex = 0
	backdrop.Parent = root
	backdrop.Activated:Connect(function()
		if os.clock() - view.started >= C.MinShowSeconds then
			self:close()
		end
	end)
	view.backdrop = backdrop
	-- The holder is the natural size, scaled to fit; the stage inside it pops in and out.
	local holder = frame(root, "Holder")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(C.Width, C.Height)
	holder.ZIndex = 1
	view.holder = holder
	view.fit = Instance.new("UIScale")
	view.fit.Name = "Fit"
	view.fit.Parent = holder
	local stage = frame(holder, "Stage")
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromScale(1, 1)
	stage.Visible = false
	view.stage = stage

	local badgeTop = C.TitleHeight + C.Gap
	local badgeMiddle = badgeTop + C.BadgePx / 2
	view.rays = Instance.new("ImageLabel")
	view.rays.Name = "Rays"
	view.rays.BackgroundTransparency = 1
	view.rays.Image = K.Art.Rays
	view.rays.ImageColor3 = tone("Gold")
	view.rays.ImageTransparency = 1
	view.rays.AnchorPoint = Vector2.new(0.5, 0.5)
	view.rays.Position = UDim2.fromOffset(C.Width / 2, badgeMiddle)
	view.rays.Size = UDim2.fromOffset(C.BadgePx * C.RaysShare, C.BadgePx * C.RaysShare)
	view.rays.ZIndex = 1
	view.rays.Parent = stage

	view.title = HudParts.text(stage, "Title", C.TitleTextPx, P.NewRank, tone("Gold"))
	view.title.TextWrapped = false
	view.title.Size = UDim2.fromOffset(C.TitleWidth, C.TitleHeight)
	view.title.AnchorPoint = Vector2.new(0.5, 0)
	view.title.Position = UDim2.fromOffset(C.Width / 2, 0)
	view.title.ZIndex = 4

	local function badgeAt(): any
		local badge = RankBadge.new(stage, {
			size = C.BadgePx,
			interactive = false,
			shine = true,
			name = "Badge",
			zIndex = 3,
		})
		badge.root.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.root.Position = UDim2.fromOffset(C.Width / 2, badgeMiddle)
		table.insert(view.badges, badge)
		return badge
	end
	view.badge = badgeAt()
	view.badge:set(tier, division)
	if newTier then
		local oldTier, oldDivision = rankOf(event.before)
		view.oldBadge = badgeAt()
		view.oldBadge:set(oldTier, oldDivision)
		view.badge.root.Visible = false
	end

	view.name = HudParts.text(stage, "RankName", C.NameTextPx, nameOf(event.after))
	view.name.TextWrapped = false
	view.name.Position = UDim2.fromOffset(0, badgeTop + C.BadgePx + 4)
	view.name.Size = UDim2.fromOffset(C.Width, C.NameHeight)
	view.name.ZIndex = 4
	view.name.Visible = not newTier -- a new tier's name arrives with its badge

	-- The reward chip: the cash and "+$200", centred under the name.
	view.reward = nil
	if item.reward > 0 then
		local words = Format.moneyDelta(item.reward)
		local height = C.RewardHeight
		local iconWidth = math.floor(height * 1.3)
		local textWidth = TextService:GetTextSize(
			words,
			C.RewardTextPx,
			(Enum.Font :: any)[K.Font],
			Vector2.new(10000, 1000)
		).X + 8
		local pill = HudParts.pill(stage, "Reward")
		pill.AnchorPoint = Vector2.new(0.5, 0)
		pill.Position = UDim2.fromOffset(C.Width / 2, badgeTop + C.BadgePx + 4 + C.NameHeight + 4)
		pill.Size = UDim2.fromOffset(iconWidth + textWidth + 16, height)
		pill.ZIndex = 4
		pill.Visible = false
		local icon = HudParts.icon(pill, "CashSingle", "Cash")
		icon.Position = UDim2.fromOffset(6, 2)
		icon.Size = UDim2.fromOffset(iconWidth, height - 4)
		local amount = HudParts.text(pill, "Amount", C.RewardTextPx, words, tone("Green"))
		amount.AutoLocalize = false -- only a number
		amount.TextWrapped = false
		amount.Position = UDim2.fromOffset(iconWidth + 8, 1)
		amount.Size = UDim2.fromOffset(textWidth, height - 2)
		view.reward = pill
	end

	view.continue = HudParts.candy(stage, P.Continue, function()
		UISound.play("Click")
		self:close()
	end, "Green")
	view.continue.Name = "Continue"
	view.continue.AnchorPoint = Vector2.new(0.5, 1)
	view.continue.Position = UDim2.fromOffset(C.Width / 2, C.Height)
	view.continue.Size = UDim2.fromOffset(C.ButtonWidth, C.ButtonHeight)
	view.continue.ZIndex = 4
	view.continue.Visible = false

	self.root.Visible = true
	self:layout()
	TweenService:Create(
		backdrop,
		TweenInfo.new(K.Motion.PopSeconds, Enum.EasingStyle.Quad),
		{ BackgroundTransparency = C.BackdropTransparency }
	):Play()
	UIAnim.popIn(stage)
	ContextActionService:BindActionAtPriority(
		ACTION,
		function(_name: string, state: Enum.UserInputState, _input: InputObject)
			if
				state == Enum.UserInputState.Begin
				and os.clock() - view.started >= C.MinShowSeconds
			then
				self:close()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value + 10,
		Enum.KeyCode.ButtonA,
		Enum.KeyCode.ButtonB
	)
	view.loop = RunService.RenderStepped:Connect(function()
		local ok, err = pcall(self.stepUp, self, view)
		if not ok then
			warn("[8ball] NewRankPopup: " .. tostring(err))
			self:close()
		end
	end)
	if not newTier then
		UISound.play("RankUp")
	end
end

-- Fit the natural layout to the screen, the badge about 40% of its short side.
function NewRankPopup.layout(self: any)
	local view = self.view
	local size = self.root.AbsoluteSize
	if not view or not view.fit or size.X <= 0 or size.Y <= 0 then
		return
	end
	local scale = math.min(
		(size.X - C.MarginPx * 2) / C.Width,
		(size.Y - C.MarginPx * 2) / C.Height,
		C.MaxScale
	)
	view.fit.Scale = math.max(0.1, scale)
end

-- Colours for the confetti: the new tier's own, then the kit's bright ones.
local function confettiColors(tier: string): { Color3 }
	local colors: { Color3 } = {}
	local own = (Config.Ranks.Colors :: any)[tier]
	if type(own) == "table" then
		table.insert(colors, HudParts.color(own))
	end
	for _, name in { "Gold", "Green", "Blue", "Red" } do
		table.insert(colors, tone(name))
	end
	return colors
end

function NewRankPopup.stepUp(self: any, view: any)
	if view.closing then
		return
	end
	local t = os.clock() - view.started
	local item = view.item
	-- A new tier: the old badge holds, then spins away, shrinking, into the new one.
	if view.oldBadge and view.oldBadge.root.Visible then
		local spin = (t - C.TierHoldSeconds) / C.TierSpinSeconds
		if spin >= 1 then
			view.oldBadge.root.Visible = false
		elseif spin > 0 then
			local k = spin * spin
			view.oldBadge.root.Rotation = C.TierSpinDegrees * k
			view.oldBadge:setSize(C.BadgePx * (1 - (1 - C.TierSpinEndScale) * k))
		end
	end
	if not view.burst and t >= view.burstAt then
		view.burst = true
		local tier = rankOf(item.event.after)
		if view.newTier then
			view.badge.root.Visible = false
			UIAnim.popIn(view.badge.root)
			view.title.Text = P.NewTier:format(string.upper(Ranks.tierName(tier)))
			HudParts.setTextSize(view.title, C.TierTextPx)
			UIAnim.bounce(view.title)
			UIAnim.popIn(view.name)
			UISound.play("NewTier")
		end
		view.badge:burst()
		local centre = view.badge.root.AbsolutePosition
			+ view.badge.root.AbsoluteSize / 2
			- view.root.AbsolutePosition
		UIAnim.confetti(
			view.root,
			centre,
			confettiColors(tier),
			if view.newTier then C.TierConfettiScale else C.ConfettiScale
		)
		if view.reward then
			UIAnim.popIn(view.reward)
		end
	end
	-- The rays fade in with the burst and keep turning.
	local shown = math.clamp((t - view.burstAt) / K.Motion.PopSeconds, 0, 1)
	view.rays.ImageTransparency = 1 - (1 - C.RaysTransparency) * shown
	view.rays.Rotation = (t * K.Motion.RaysDegreesPerSecond) % 360
	if t >= view.rewardAt and not view.chipSent then
		view.chipSent = true
		self:sendChip(view)
	end
	if t >= view.continueAt and not view.continueShown then
		view.continueShown = true
		UIAnim.popIn(view.continue)
		if UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1 then
			GuiService.SelectedObject = view.continue
		end
	end
	if t >= view.closeAt then
		self:close()
	end
end

-- A real rank-up's reward chip flies into the money HUD; a paid or preview one only shows.
function NewRankPopup.sendChip(self: any, view: any)
	local item = view.item
	if not item.owed then
		return
	end
	item.owed = false
	local pill = view.reward
	if pill and pill.Visible then
		local from = pill.AbsolutePosition + pill.AbsoluteSize / 2
		self.flyer:fly(item.reward, from, "Reward", 0)
		UIAnim.popOut(pill)
	else
		self.money:land(item.reward)
	end
end

--------------------------------------------------------------------------------------------
-- Rank down
--------------------------------------------------------------------------------------------

function NewRankPopup.openDown(self: any, item: any)
	local tier, division = rankOf(item.event.after)
	local view: any = {
		item = item,
		kind = "Down",
		started = os.clock(),
		closing = false,
		badges = {},
	}
	self.view = view
	local root = frame(self.root, "RankDown")
	root.Size = UDim2.fromScale(1, 1)
	view.root = root
	local words = P.RankDown:format(nameOf(item.event.after))
	local height = C.DownHeight
	local textWidth = TextService:GetTextSize(
		words,
		C.DownTextPx,
		(Enum.Font :: any)[K.Font],
		Vector2.new(10000, 1000)
	).X + 8
	local card = HudParts.card(root, "Card")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.fromScale(0.5, C.DownTopShare)
	card.Size = UDim2.fromOffset(C.DownBadgePx + textWidth + 28, height)
	card.Visible = false
	view.stage = card
	local badge = RankBadge.new(card, {
		size = C.DownBadgePx,
		interactive = false,
		name = "Badge",
		zIndex = 2,
	})
	badge.root.Position = UDim2.fromOffset(8, (height - C.DownBadgePx) / 2)
	badge:set(tier, division)
	table.insert(view.badges, badge)
	local text = HudParts.note(card, "Text", C.DownTextPx, words)
	text.TextWrapped = false
	text.Position = UDim2.fromOffset(C.DownBadgePx + 14, 0)
	text.Size = UDim2.fromOffset(textWidth, height)
	self.root.Visible = true
	UIAnim.popIn(card)
	UISound.play("RankDown")
	task.delay(C.DownSeconds, function()
		if self.view == view then
			self:close()
		end
	end)
end

--------------------------------------------------------------------------------------------
-- Closing
--------------------------------------------------------------------------------------------

function NewRankPopup.close(self: any)
	local view = self.view
	if not view or view.closing then
		return
	end
	view.closing = true
	if view.kind == "Up" then
		ContextActionService:UnbindAction(ACTION)
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(view.root) then
			GuiService.SelectedObject = nil
		end
		TweenService:Create(
			view.backdrop,
			TweenInfo.new(K.Motion.OutSeconds, Enum.EasingStyle.Quad),
			{ BackgroundTransparency = 1 }
		):Play()
	end
	-- A reward that did not get to fly lands now, so the HUD is not left waiting.
	local item = view.item
	if item.owed then
		item.owed = false
		self.money:land(item.reward)
	end
	UIAnim.popOut(view.stage)
	task.delay(K.Motion.OutSeconds + 0.05, function()
		self:finish(view)
	end)
end

function NewRankPopup.finish(self: any, view: any)
	if view.finished then
		return
	end
	view.finished = true
	if view.loop then
		view.loop:Disconnect()
	end
	for _, badge in view.badges do
		badge:destroy()
	end
	if view.root then
		view.root:Destroy()
	end
	if self.view == view then
		self.view = nil
	end
	self.root.Visible = false
	if not self.alive then
		return
	end
	local onDone = view.item.onDone
	if onDone then
		task.spawn(onDone)
	end
	self:nextOne()
end

--- Whether a popup is up (or waiting to show).
function NewRankPopup.isOpen(self: any): boolean
	return self.view ~= nil or #self.queue > 0
end

function NewRankPopup.destroy(self: any)
	if not self.alive then
		return
	end
	self.alive = false
	-- Rewards still owed land at once, so the HUD is not left waiting for them.
	for _, item in self.queue do
		if item.owed then
			item.owed = false
			self.money:land(item.reward)
		end
	end
	self.queue = {}
	local view = self.view
	if view then
		self:close()
		self:finish(view)
	end
	self.sizeChanged:Disconnect()
	self.root:Destroy()
end

return NewRankPopup
