--!strict
-- NewRankPopup: NEW RANK!, one at a time (a second one waits its turn). XP is never lost
-- (ECONOMY 4.1), so there is no rank-down card.
-- - A big popup with no dim: "NEW RANK!" in big gold kit text, the new badge large (about 40%
--   of the screen's short side) with gold rays turning behind it, its shine and a burst,
--   confetti, the rank's name ("Gold IV"), then every reward as a chip (brief section 9;
--   RewardChips): the money ("+$300" with the cash), which then flies into the money HUD; each
--   case (its own chest and "x2") and the tier's cue (its thumbnail and name), whose pictures
--   fly into the left column's Inventory tile; and the tier's chat tag, drawn as chat draws it.
--   Chips wider than the popup reach past its sides like the title, or wrap onto a second
--   row. Then Continue. It closes itself after a few seconds.
-- - A new tier (Gold V to Platinum I; Unranked to Bronze I counts): the bigger version. The old
--   badge shows first, then spins away into the new one, the tier's name goes huge
--   ("PLATINUM!"), more confetti and the bigger fanfare.
-- Tuning in Config.UI.Progress.NewRank; laid out at a natural size and scaled to the screen.
--
-- Money: a rank-up's reward is already in the save when this shows (the server paid it). For a
-- /xp rank-up the chip flies into the HUD here (the HUD is told the moment the popup is asked
-- for); after the result screen (`paid`, it flew with the total chip) and for a /newrank preview
-- (`preview`, nothing was paid) the chip only shows. The cases and the cue are in the inventory
-- already too; their pictures always fly (purely a picture: the column's red dot comes from the
-- save), even in a preview, whose rewards are worked out here when the event does not list them.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local ProgressionRules = Shared:WaitForChild("Progression")
local Format = require(ProgressionRules:WaitForChild("Format"))
local Ranks = require(ProgressionRules:WaitForChild("Ranks"))
local ChatTags = require(script.Parent.ChatTags)
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local RankBadge = require(script.Parent.RankBadge)
local RewardChips = require(script.Parent.RewardChips)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local C = Config.UI.Progress.NewRank
local K = Config.UI.Kit
local P = Strings.Progress
local CASE_ORDER: { string } = Config.Cases.Order
local NewRankPopup = {}
NewRankPopup.__index = NewRankPopup

export type NewRankPopup = {
	show: (self: NewRankPopup, event: any, onDone: (() -> ())?) -> (),
	setDeps: (self: NewRankPopup, deps: any) -> (),
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

-- A rank's division index (0: Unranked), from its index or its tier and division.
local function indexOf(rank: any): number
	local r: any = if type(rank) == "table" then rank else {}
	if type(r.index) == "number" then
		return r.index
	end
	local tier, division = rankOf(rank)
	return Ranks.indexOf(tier, division) or 0
end

local function nameOf(rank: any): string
	local tier, division = rankOf(rank)
	return Ranks.name({ tier = tier, division = division, index = 0, xpInDivision = 0 })
end

-- A preview's cases and cues, worked out from the divisions it passed (the server lists them
-- for a real rank-up: Net RankEvent).
local function previewItems(event: any): ({ [string]: number }, { string })
	local cases: { [string]: number } = {}
	local cues: { string } = {}
	for _, row in Ranks.rewardsBetween(indexOf(event.before), indexOf(event.after)) do
		for id, count in row.cases do
			cases[id] = (cases[id] or 0) + count
		end
		if row.cue then
			table.insert(cues, row.cue)
		end
	end
	return cases, cues
end

-- The chips for an event: the money, each case in the shop's order, every cue, and the new
-- tier's chat tag.
local function specsOf(event: any, reward: number): { RewardChips.Spec }
	local specs: { RewardChips.Spec } = {}
	if reward > 0 then
		table.insert(
			specs,
			{ kind = "Money", text = Format.moneyDelta(reward), tint = tone("Green") }
		)
	end
	local cases: any, cues: any = event.rewardCases, event.rewardCues
	if type(cases) ~= "table" and type(cues) ~= "table" and event.preview == true then
		cases, cues = previewItems(event)
	end
	if type(cases) == "table" then
		for _, id in CASE_ORDER do
			local count = clean(cases[id])
			if count > 0 then
				table.insert(specs, { kind = "Case", id = id, text = P.RewardCount:format(count) })
			end
		end
	end
	if type(cues) == "table" then
		for _, id in cues do
			if type(id) == "string" then
				table.insert(specs, { kind = "Cue", id = id, text = CueThumb.cueName(id) })
			end
		end
	end
	if event.newTier == true then
		local tier = rankOf(event.after)
		local tag = ChatTags.tagFor(tier)
		if tag then
			table.insert(specs, {
				kind = "Tag",
				text = tag,
				rich = true,
				plain = Strings.Ranks.ChatTag:format(string.upper(Ranks.tierName(tier))),
			})
		end
	end
	return specs
end

--- The popups, built into `screen` (UI.screen()). Reward chips fly with `flyer` into `money`;
--- cases and cues fly into the column (setDeps).
function NewRankPopup.new(screen: ScreenGui, flyer: any, money: any): NewRankPopup
	local self: any = setmetatable({}, NewRankPopup)
	self.alive = true
	self.screen = screen
	self.flyer = flyer
	self.money = money
	self.deps = nil
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

--- The economy's shared table (Progression): its `column` catches the flying cases and cues.
function NewRankPopup.setDeps(self: any, deps: any)
	self.deps = deps
end

--- Show a rank-up: `event` = {kind = "Up", before, after (ranks: tier and division, index),
--- reward (money), newTier, rewardCases? ({[caseId] = count}), rewardCues? ({cueId}),
--- preview?, paid?} (the server's RankEvent, or the result screen after a match). `onDone`
--- runs once it has closed. One at a time: a second one waits.
function NewRankPopup.show(self: any, event: any, onDone: (() -> ())?)
	if
		not self.alive
		or type(event) ~= "table"
		or type(event.after) ~= "table"
		or (event.kind ~= nil and event.kind ~= "Up")
	then
		if onDone then
			task.spawn(onDone)
		end
		return
	end
	local reward = clean(event.reward)
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
		self:openUp(item)
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
		newTier = newTier,
		started = os.clock(),
		closing = false,
		burst = false,
		chipSent = false,
		continueShown = false,
		badges = {},
		chips = {},
		flights = {}, -- the cases and cue still to fly: { chip, at }
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

	-- The reward chips, in centred rows under the name; the popup grows by the rows.
	local chipsTop = badgeTop + C.BadgePx + 4 + C.NameHeight + 4
	for _, spec in specsOf(event, item.reward) do
		local chip = RewardChips.new(stage, spec, C.RewardHeight, C.RewardTextPx)
		chip.root.ZIndex = 4
		table.insert(view.chips, chip)
		if spec.kind == "Money" then
			view.moneyChip = chip
		end
	end
	local rowsHeight, widest = RewardChips.flow(
		view.chips,
		C.Width / 2,
		chipsTop,
		C.ChipsMaxWidth,
		C.RewardHeight,
		C.ChipGap,
		C.ChipRowGap
	)
	view.height = chipsTop + rowsHeight + C.Gap + C.ButtonHeight
	view.width = math.max(C.Width, widest)
	holder.Size = UDim2.fromOffset(C.Width, view.height)
	-- The cases and the cue fly to Inventory one after another, after the money.
	local at = view.rewardAt + C.ItemFlyAfter
	for _, chip in view.chips do
		if chip.spec.kind == "Case" or chip.spec.kind == "Cue" then
			table.insert(view.flights, { chip = chip, at = at })
			at += C.ItemFlyStagger
		end
	end

	view.continue = HudParts.candy(stage, P.Continue, function()
		UISound.play("Click")
		self:close()
	end, "Green")
	view.continue.Name = "Continue"
	view.continue.AnchorPoint = Vector2.new(0.5, 1)
	view.continue.Position = UDim2.fromOffset(C.Width / 2, view.height)
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

-- Fit the natural layout to the screen, the badge about 40% of its short side (a row of chips
-- wider than the popup counts).
function NewRankPopup.layout(self: any)
	local view = self.view
	local size = self.root.AbsoluteSize
	if not view or not view.fit or size.X <= 0 or size.Y <= 0 then
		return
	end
	local scale = math.min(
		(size.X - C.MarginPx * 2) / (view.width or C.Width),
		(size.Y - C.MarginPx * 2) / (view.height or C.Height),
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
	end
	-- The chips pop in one after another from the burst.
	if view.burst then
		for i, chip in view.chips do
			if not chip.root.Visible and t >= view.burstAt + (i - 1) * C.ChipStagger then
				UIAnim.popIn(chip.root)
			end
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
	while view.flights[1] and t >= view.flights[1].at do
		local flight: any = table.remove(view.flights, 1)
		self:flyItem(view, flight.chip)
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

-- A real rank-up's money flies into the money HUD from its chip, which stays and bounces; a
-- paid or preview one only shows.
function NewRankPopup.sendChip(self: any, view: any)
	local item = view.item
	if not item.owed then
		return
	end
	item.owed = false
	local chip = view.moneyChip
	local pill = if chip then chip.root else nil
	if pill and pill.Visible then
		local from = pill.AbsolutePosition + pill.AbsoluteSize / 2
		self.flyer:fly(item.reward, from, "Reward", 0)
		UIAnim.bounce(pill)
	else
		self.money:land(item.reward)
	end
end

-- A case or the cue: its picture flies into the column's Inventory tile; its chip bounces.
function NewRankPopup.flyItem(self: any, _view: any, chip: RewardChips.Chip)
	chip.root.Visible = true -- a close before its pop still sends it from its place
	UIAnim.bounce(chip.root)
	RewardChips.fly(self.screen, chip, self.deps, "Inventory", 0)
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
	-- A reward that did not get to fly lands now, so the HUD is not left waiting; cases and
	-- the cue still waiting set off at once, from where their chips are as the popup goes.
	local item = view.item
	if item.owed then
		item.owed = false
		self.money:land(item.reward)
	end
	for _, flight in view.flights do
		RewardChips.fly(self.screen, flight.chip, self.deps, "Inventory", 0)
	end
	view.flights = {}
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
