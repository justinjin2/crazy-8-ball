--!strict
-- CaseOpeningReel: the case opening's spinning reel (CaseOpening; docs/prompts/ECONOMY_UI_PROMPT.md
-- section 11), Rivals / CS style: a white kit card holding a strip of about 40 cue cards (each the
-- tinted thumbnail on its rarity's dressing, CueThumb) that slides behind a gold marker and slows
-- onto the prize the server already chose.
--
-- - The strip is drawn from the case's pool by the odds (Cases.cueOdds, each weight raised to
--   Reel.WeightPower; 1 = the true odds). It is purely visual (a client Random): the prize is
--   put at a fixed late slot (Reel.PrizeSlot) once the server's answer is known.
-- - The spin eases out over Reel.Seconds (Mythic and Secret: BigSeconds, a longer crawl, the
--   ReelBuild sound and a glow round the window that builds in the prize's colour) and lands at
--   a random offset within the prize card, then glides it to the marker's middle. A soft tick
--   (ReelTick, rate-limited) sounds for each card passing the marker.
-- - As it settles: ReelSettle, the marker and a glow round the window turn the prize's colour
--   (Mythic's drifts through its pastels, Secret's breathes red), the prize card bounces with a
--   thick edge in that colour; after a short hold the reel reports it is done.
-- - skip() jumps straight to the prize (a tap, A or B).
-- Built in natural pixels inside a CaseOpeningFx stage; layout(width) sizes it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ProgressionRules = Shared:WaitForChild("Progression")
local Cases = require(ProgressionRules:WaitForChild("Cases"))
local Catalog = require(ProgressionRules:WaitForChild("Catalog"))
local CaseOpeningFx = require(script.Parent.CaseOpeningFx)
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local C = Config.UI.CaseOpening
local R = C.Reel
local K = Config.UI.Kit
local INK = HudParts.tone("Ink")
local GOLD = HudParts.tone("Gold")
local WHITE = Color3.new(1, 1, 1)

type Slot = {
	id: string,
	rarity: string,
	frame: Frame,
	edge: UIStroke,
	thumb: Frame,
	dressing: CueThumb.Dressing,
}

local Reel = {}
Reel.__index = Reel

local function pitch(): number
	return R.CardWidthPx + R.GapPx
end

-- A slot's middle along the strip, in the strip's pixels.
local function centreOf(slot: number): number
	return (slot - 1) * pitch() + R.CardWidthPx / 2
end

-- The case's cues with their draw weights (the odds, flattened by WeightPower).
local function pool(caseId: string): ({ { id: string, rarity: string } }, { number }, number)
	local odds = Cases.cueOdds(caseId)
	if #odds == 0 then
		odds = Cases.cueOdds(Config.Cases.FreeCase)
	end
	local cues, weights, total = {}, {}, 0
	for _, entry in odds do
		local weight = math.max(0, entry.percent) ^ R.WeightPower
		if weight > 0 then
			table.insert(cues, { id = entry.id, rarity = entry.rarity })
			table.insert(weights, weight)
			total += weight
		end
	end
	if #cues == 0 then
		table.insert(cues, { id = Catalog.Default, rarity = "Common" })
		table.insert(weights, 1)
		total = 1
	end
	return cues, weights, total
end

-- One card of the strip: a white rounded face dressed in the rarity, the cue's thumbnail on it.
local function makeCard(parent: Instance, index: number, id: string, rarity: string): Slot
	local frame = HudParts.frame(parent, "Card" .. index)
	frame.Size = UDim2.fromOffset(R.CardWidthPx, R.CardHeightPx)
	frame.Position = UDim2.fromOffset((index - 1) * pitch(), 0)
	local fill = HudParts.frame(frame, "Fill")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = WHITE
	fill.ZIndex = 0
	HudParts.corner(fill, R.CardCornerPx)
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = INK
	edge.Thickness = R.CardStrokePx
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = fill
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Color = ColorSequence.new(WHITE, HudParts.color(K.PanelFade))
	fade.Parent = fill
	local dressing = CueThumb.dress(fill, rarity)
	local side = math.floor(R.CardWidthPx * R.ThumbShare)
	local thumb = CueThumb.new(frame, id)
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.Position = UDim2.fromScale(0.5, R.ThumbCentreShare)
	thumb.Size = UDim2.fromOffset(side, side)
	thumb.ZIndex = 2
	return {
		id = id,
		rarity = rarity,
		frame = frame,
		edge = edge,
		thumb = thumb,
		dressing = dressing,
	}
end

--- Build the reel for `caseId` in `parent` (a stage), its strip drawn at random from the case's
--- pool. Size it with layout(width); put the prize in with setPrize, then start().
function Reel.new(parent: Instance, caseId: string): any
	local self: any = setmetatable({}, Reel)
	self.caseId = caseId
	self.random = Random.new()
	self.phase = "Idle" -- Idle, Spinning, Centring, Holding, Done
	self.alive = true
	self.prizeId = nil :: string?
	self.prizeRarity = "Common"
	self.big = false
	self.width = 0
	self.clipWidth = 0
	self.pos = 0 -- where the marker is along the strip, in the strip's pixels
	self.loop = nil :: RBXScriptConnection?
	self.onSettled = nil :: (() -> ())?
	self.lastTick = -math.huge
	self.lastIndex = 0
	self.glowFrom = 0 -- os.clock() when the glow round the window began
	self.glowOn = false
	self.landed = false

	local root = HudParts.frame(parent, "Reel")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	self.root = root

	-- The glow round the window, under it.
	local halo = CaseOpeningFx.halo(root, "Halo")
	halo.ZIndex = 0
	self.halo = halo

	local window = HudParts.card(root, "Window", R.CornerPx)
	window.Size = UDim2.fromScale(1, 1)
	window.ZIndex = 1
	self.window = window

	-- The strip, clipped inside the window's straight part (a clip ignores round corners).
	local clip = HudParts.frame(window, "Clip")
	clip.ClipsDescendants = true
	clip.ZIndex = 1
	self.clip = clip
	local strip = HudParts.frame(clip, "Strip")
	strip.ZIndex = 1
	self.strip = strip

	local cues, weights, total = pool(caseId)
	self.slots = {} :: { Slot }
	for index = 1, math.max(R.Cards, R.PrizeSlot + 1) do
		local pick = self.random:NextNumber(0, total)
		local chosen = cues[#cues]
		for i, weight in weights do
			pick -= weight
			if pick <= 0 then
				chosen = cues[i]
				break
			end
		end
		self.slots[index] = makeCard(strip, index, chosen.id, chosen.rarity)
	end
	strip.Size = UDim2.fromOffset(#self.slots * pitch(), R.CardHeightPx)

	-- Soft white ends, so cards slide in and out of view.
	self.fades = {} :: { Frame }
	for i, side in { 0, 1 } do
		local fade = HudParts.frame(clip, if side == 0 then "FadeLeft" else "FadeRight")
		fade.BackgroundTransparency = 0
		fade.BackgroundColor3 = WHITE
		fade.AnchorPoint = Vector2.new(side, 0)
		fade.Position = UDim2.fromScale(side, 0)
		fade.ZIndex = 3
		local gradient = Instance.new("UIGradient")
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, if side == 0 then R.FadeEdgeTransparency else 1),
			NumberSequenceKeypoint.new(1, if side == 0 then 1 else R.FadeEdgeTransparency),
		})
		gradient.Parent = fade
		self.fades[i] = fade
	end

	-- The gold marker: a bar down the middle with a tip poking in at the top and the bottom.
	local marker = HudParts.frame(root, "Marker")
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.ZIndex = 3
	self.marker = marker
	local bar = HudParts.frame(marker, "Bar")
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.fromScale(0.5, 0)
	bar.Size = UDim2.new(0, R.MarkerWidthPx, 1, 0)
	bar.BackgroundTransparency = 0
	bar.BackgroundColor3 = GOLD
	bar.ZIndex = 1
	HudParts.corner(bar, math.ceil(R.MarkerWidthPx / 2))
	local barEdge = Instance.new("UIStroke")
	barEdge.Color = INK
	barEdge.Thickness = R.MarkerStrokePx
	barEdge.Parent = bar
	self.bar = bar
	self.tips = {} :: { Frame }
	for i, y in { 0, 1 } do
		local tip = HudParts.frame(marker, if y == 0 then "TipTop" else "TipBottom")
		tip.AnchorPoint = Vector2.new(0.5, 0.5)
		tip.Position = UDim2.fromScale(0.5, y)
		tip.Size = UDim2.fromOffset(R.MarkerTipPx, R.MarkerTipPx)
		tip.Rotation = 45
		tip.BackgroundTransparency = 0
		tip.BackgroundColor3 = GOLD
		tip.ZIndex = 2
		HudParts.corner(tip, R.MarkerTipCornerPx)
		local edge = Instance.new("UIStroke")
		edge.Color = INK
		edge.Thickness = R.MarkerStrokePx
		edge.Parent = tip
		self.tips[i] = tip
	end
	return self
end

--- The reel's height (natural pixels); its width is whatever layout gives it.
function Reel.height(): number
	return R.CardHeightPx + 2 * R.PadYPx
end

-- The slot the spin starts on: far enough in that cards fill the window's left side.
function Reel.startSlot(self: any): number
	local half = self.clipWidth / 2
	return math.max(1, math.ceil(half / pitch()) + 1)
end

--- Size the reel `width` wide (natural pixels). Safe mid-spin: the spin is kept along the strip.
function Reel.layout(self: any, width: number)
	local h = Reel.height()
	local stroke = K.PanelStrokePx
	self.width = width
	self.root.Size = UDim2.fromOffset(width, h)
	local inset = R.CornerPx
	self.clipWidth = math.max(1, width - 2 * inset)
	self.clip.Position = UDim2.fromOffset(inset, stroke)
	self.clip.Size = UDim2.fromOffset(self.clipWidth, h - 2 * stroke)
	self.strip.Position = UDim2.fromOffset(0, R.PadYPx - stroke)
	for _, fade in self.fades do
		fade.Size = UDim2.new(0, math.min(R.FadePx, self.clipWidth / 4), 1, 0)
	end
	self.marker.Position = UDim2.fromOffset(width / 2, h / 2)
	self.marker.Size = UDim2.fromOffset(R.MarkerTipPx, h + 2 * R.MarkerOverPx)
	CaseOpeningFx.placeHalo(self.halo, Vector2.zero, Vector2.new(width, h), R.HaloSpreadPx)
	if self.phase == "Idle" then
		self.pos = centreOf(self:startSlot())
	end
	self:place()
end

-- Move the strip so `pos` sits under the marker.
function Reel.place(self: any)
	self.strip.Position = UDim2.fromOffset(
		math.floor(self.clipWidth / 2 - self.pos + 0.5),
		R.PadYPx - K.PanelStrokePx
	)
end

--- Put the server's prize at the prize slot (hidden far along the strip until the spin nears it).
function Reel.setPrize(self: any, cueId: string, rarity: string)
	self.prizeId = cueId
	self.prizeRarity = rarity
	self.big = CaseOpeningFx.isBig(rarity)
	local slot: Slot = self.slots[R.PrizeSlot]
	slot.id = cueId
	slot.rarity = rarity
	CueThumb.set(slot.thumb, cueId)
	slot.dressing.set(rarity)
end

--- Spin onto the prize (setPrize first); `onSettled` runs once, after it has settled and held.
function Reel.start(self: any, onSettled: () -> ())
	if not self.alive or self.phase ~= "Idle" then
		return
	end
	self.onSettled = onSettled
	self.phase = "Spinning"
	self.duration = if self.big then R.BigSeconds else R.Seconds
	self.power = if self.big then R.BigEasePower else R.EasePower
	self.from = self.pos
	local spread = R.LandSpread * R.CardWidthPx / 2
	self.offset = self.random:NextNumber(-spread, spread)
	self.to = centreOf(R.PrizeSlot) + self.offset
	self.began = os.clock()
	self.built = false
	self.lastIndex = math.floor(self.pos / pitch())
	self.loop = RunService.RenderStepped:Connect(function()
		local ok, err = pcall(self.step, self)
		if not ok then
			warn("[8ball] CaseOpeningReel: " .. tostring(err))
			self:finish()
		end
	end)
end

-- A card edge passed the marker: a soft tick, never faster than TickMinGapSeconds.
function Reel.tick(self: any, now: number)
	local index = math.floor(self.pos / pitch())
	if index ~= self.lastIndex then
		self.lastIndex = index
		if now - self.lastTick >= R.TickMinGapSeconds then
			self.lastTick = now
			UISound.play("ReelTick")
		end
	end
end

-- The glow round the window: building during a big spin's crawl, full once settled.
function Reel.glow(self: any, now: number)
	local rarity = self.prizeRarity
	local share = 0
	if self.landed then
		share = 1
	elseif self.big and self.phase == "Spinning" then
		local left = self.began + self.duration - now
		share = math.clamp(1 - left / R.BuildLeadSeconds, 0, 1) * R.BuildGlowShare
	end
	if share <= 0 then
		self.halo.ImageTransparency = 1
		return
	end
	local t = now - self.glowFrom
	local strength = share
	if rarity == "Secret" then
		strength *= 1 - R.SecretBreathDepth * (1 - CaseOpeningFx.breath(t, R.BreathSeconds))
	end
	self.halo.ImageColor3 = CaseOpeningFx.glowAt(rarity, t)
	self.halo.ImageTransparency = 1 - (1 - R.HaloTransparency) * strength
	if self.landed and rarity == "Mythic" then
		local colour = CaseOpeningFx.shimmerAt(t)
		self.bar.BackgroundColor3 = colour
		for _, tip in self.tips do
			tip.BackgroundColor3 = colour
		end
	end
end

function Reel.step(self: any)
	if not self.alive then
		return
	end
	local now = os.clock()
	if self.phase == "Spinning" then
		local u = math.clamp((now - self.began) / self.duration, 0, 1)
		local eased = 1 - (1 - u) ^ self.power
		self.pos = self.from + (self.to - self.from) * eased
		if
			self.big
			and not self.built
			and now >= self.began + self.duration - R.BuildLeadSeconds
		then
			self.built = true
			self.glowFrom = now
			UISound.play("ReelBuild")
		end
		self:tick(now)
		if u >= 1 then
			self:land(now)
		end
	elseif self.phase == "Centring" then
		local u = math.clamp((now - self.centreFrom) / R.CentreSeconds, 0, 1)
		self.pos = self.to + (centreOf(R.PrizeSlot) - self.to) * UIAnim.quadOut(u)
		if u >= 1 then
			self.phase = "Holding"
		end
	elseif self.phase == "Holding" then
		if now >= self.holdUntil then
			self:finish()
			return
		end
	end
	self:glow(now)
	self:place()
end

-- The spin stopped on the prize: the settle sound, the marker and the glow in its colour, the
-- prize card bounces with a thick coloured edge; then it glides to the middle and holds.
function Reel.land(self: any, now: number)
	if self.landed then
		return
	end
	self.landed = true
	if not self.built then
		self.glowFrom = now
	end
	UISound.play("ReelSettle")
	local colour = CaseOpeningFx.color(self.prizeRarity)
	local slot: Slot = self.slots[R.PrizeSlot]
	slot.edge.Color = colour
	slot.edge.Thickness = R.PrizeStrokePx
	UIAnim.bounce(slot.frame)
	local info = TweenInfo.new(R.MarkerTintSeconds)
	TweenService:Create(self.bar, info, { BackgroundColor3 = colour }):Play()
	for _, tip in self.tips do
		TweenService:Create(tip, info, { BackgroundColor3 = colour }):Play()
	end
	self.phase = "Centring"
	self.centreFrom = now
	local hold = if self.big then R.BigSettleHoldSeconds else R.SettleHoldSeconds
	self.holdUntil = now + R.CentreSeconds + hold
end

--- Jump to the prize: settled at once (the settle effects play if they had not yet), done.
function Reel.skip(self: any)
	if not self.alive or self.phase == "Done" or self.phase == "Idle" then
		return
	end
	local now = os.clock()
	if not self.landed then
		self.to = centreOf(R.PrizeSlot)
		self:land(now)
	end
	self.pos = centreOf(R.PrizeSlot)
	self:place()
	self:finish()
end

-- Settled and held: report once.
function Reel.finish(self: any)
	if self.phase == "Done" then
		return
	end
	self.phase = "Done"
	if self.loop then
		self.loop:Disconnect()
		self.loop = nil
	end
	local done = self.onSettled
	self.onSettled = nil
	if done then
		done()
	end
end

function Reel.isSpinning(self: any): boolean
	return self.phase ~= "Idle" and self.phase ~= "Done"
end

function Reel.destroy(self: any)
	if not self.alive then
		return
	end
	self.alive = false
	self.onSettled = nil
	if self.loop then
		self.loop:Disconnect()
		self.loop = nil
	end
	self.root:Destroy()
end

return Reel
