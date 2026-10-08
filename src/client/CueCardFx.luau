--!strict
-- CueCardFx: a cue card's moving parts (docs/prompts/CUES_LIVELY_PROMPT.md, concept 1 approved
-- round 4; Config.UI.CueCard.Motion; the maths in shared/CardMath). The rarer the cue, the more
-- moves: every card's faint 8-balls drift up-left; then, by its look, a glow breathing behind
-- the cue, rays turning, a shine sweeping across, sparkles twinkling, embers rising, Mythic's
-- stars and hologram sheen, Secret's red glow, scan lines and glitch, a light running round the
-- edge, a halo breathing past it, and a bar whose colours flow or shine.
--
-- One UIAnim.loop per card drives them all. It steps only while the card's screen shows and
-- the card is inside its scroller's window, so a long grid costs only the cards on screen.
-- Lower effects: fewer sparkles, embers and stars (Quality.rate()), slower shines, sheen and
-- edge. Reduce Motion: everything stands still but the glows, which still breathe.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CardMath = require(Shared:WaitForChild("CardMath"))
local Quality = require(script.Parent.Quality)
local UIAnim = require(script.Parent.UIAnim)

local CC = Config.UI.CueCard
local M = CC.Motion
local UNITS = CC.Units
local ART = Config.UI.Kit.Art
local RAYS = Config.UI.Effects.Rays
local WHITE = Color3.new(1, 1, 1)

local CueCardFx = {}

-- The loops whose phase comes from the cue's id (so two cards never move in step).
local PHASES =
	{ "balls", "glow", "halo", "rays", "shine", "sheen", "edge", "red", "glitch", "flow" }

--- The card's own parts the motion reaches into (InventoryCard builds them).
export type Parts = {
	body: Frame, -- the card under its press scale (the halo goes here, behind the face)
	face: Frame, -- the card's box; it clips its layers
	balls: ImageLabel, -- the faint 8-balls (every card has them)
	edgeStroke: UIStroke, -- the rarity edge
	bar: Frame, -- the rarity bar
	barGradient: UIGradient,
	art: Frame, -- the cue picture's box
	thumb: Frame, -- the cue picture (CueThumb)
	name: TextLabel,
}

type Twinkle = { label: ImageLabel, spot: CardMath.Spot }

export type Fx = {
	parts: Parts,
	look: any,
	still: boolean, -- nothing moves (the lucky block reel's cards)
	made: { Instance }, -- everything built here, destroyed on stop
	loop: UIAnim.Handle?,
	phases: { [string]: number },
	scroller: ScrollingFrame?,
	scrollerKnown: boolean,
	held: boolean, -- still while its card is fading in (InventoryCard.hold)
	ancestry: RBXScriptConnection?,
	-- The parts, each nil when the look has none.
	halo: ImageLabel?,
	glow: ImageLabel?,
	rays: ImageLabel?,
	sheen: Frame?,
	sheenGradient: UIGradient?,
	scan: ImageLabel?,
	redGlow: Frame?,
	stars: { Twinkle },
	sparks: { Twinkle },
	embers: { Twinkle },
	shine: Frame?,
	shineGradient: UIGradient?,
	barShine: Frame?,
	barShineGradient: UIGradient?,
	edgeGradient: UIGradient?,
	copies: { ImageLabel }, -- Secret's red and cyan picture copies
	artRest: UDim2,
	nameRest: UDim2,
	flowStep: number,
	k: number, -- the card's scale (its width / UNITS[1]), from layout
}

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

local function corner(parent: Instance, name: string?): UICorner
	local round = Instance.new("UICorner")
	if name then
		round.Name = name
	end
	round.Parent = parent
	return round
end

local function image(fx: Fx, parent: Instance, name: string, picture: string, z: number): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Image = picture
	label.ZIndex = z
	label.Parent = parent
	table.insert(fx.made, label)
	return label
end

local function sheet(fx: Fx, parent: Instance, name: string, z: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = WHITE
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = z
	corner(frame, "Round")
	frame.Parent = parent
	table.insert(fx.made, frame)
	return frame
end

-- A slanted band of light (a shine): its gradient leaves a band `width` wide of `strength`.
local function band(parent: Frame, rotation: number, width: number, strength: number): UIGradient
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	local half = width / 2
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5 - half, 1),
		NumberSequenceKeypoint.new(0.5, 1 - strength),
		NumberSequenceKeypoint.new(0.5 + half, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Offset = Vector2.new(-2, 0)
	gradient.Parent = parent
	return gradient
end

local function sequence(colors: { string }): ColorSequence
	local keys = {}
	for i, c in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), hex(c)))
	end
	return ColorSequence.new(keys)
end

-- The nearest scroller holding the card (its window decides whether the card moves).
local function scrollerOf(object: Instance): ScrollingFrame?
	local node = object.Parent
	while node and not node:IsA("LayerCollector") do
		if node:IsA("ScrollingFrame") then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function inView(face: GuiObject, scroller: ScrollingFrame?): boolean
	if scroller == nil then
		return true
	end
	local p, s = face.AbsolutePosition, face.AbsoluteSize
	local sp, ss = scroller.AbsolutePosition, scroller.AbsoluteWindowSize
	return p.X + s.X > sp.X and p.X < sp.X + ss.X and p.Y + s.Y > sp.Y and p.Y < sp.Y + ss.Y
end

-- How many of `count` show with Lower effects (at least one).
local function shown(count: number): number
	if count <= 0 then
		return 0
	end
	return math.max(1, math.floor(count * Quality.rate() + 0.5))
end

--------------------------------------------------------------------------------------------
-- Building
--------------------------------------------------------------------------------------------

local function twinkles(
	fx: Fx,
	r: CardMath.Random,
	count: number,
	area: { number },
	units: { number },
	seconds: { number },
	picture: string,
	colors: { string },
	z: number,
	name: string
): { Twinkle }
	local list = {}
	for i, spot in CardMath.scatter(r, count, area, units, seconds) do
		local label = image(fx, fx.parts.face, name .. i, picture, z)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(spot.x, spot.y)
		label.SizeConstraint = Enum.SizeConstraint.RelativeXX
		label.ImageColor3 = hex(colors[(i - 1) % #colors + 1])
		label.ImageTransparency = 1
		table.insert(list, { label = label, spot = spot })
	end
	return list
end

--- Build a card's moving parts for `look` (Config.UI.CueCard.Looks or Tiers) and start their
--- loop. `seed` (CardMath.seed of the cue's id) places the sparkles and sets every phase, so a
--- cue's card always moves the same way and two cards never move in step. `still`: build
--- nothing that moves (the reel's cards: a moving prize would give itself away).
function CueCardFx.new(parts: Parts, look: any, seed: number, still: boolean?): Fx
	local fx: Fx = {
		parts = parts,
		look = look,
		still = still == true,
		made = {},
		loop = nil,
		phases = {},
		scroller = nil,
		scrollerKnown = false,
		held = false,
		ancestry = nil,
		halo = nil,
		glow = nil,
		rays = nil,
		sheen = nil,
		sheenGradient = nil,
		scan = nil,
		redGlow = nil,
		stars = {},
		sparks = {},
		embers = {},
		shine = nil,
		shineGradient = nil,
		barShine = nil,
		barShineGradient = nil,
		edgeGradient = nil,
		copies = {},
		artRest = parts.art.Position,
		nameRest = parts.name.Position,
		flowStep = -1,
		k = 1,
	}
	local r = CardMath.random(seed)
	for _, key in PHASES do
		fx.phases[key] = CardMath.next(r)
	end
	local face = parts.face
	parts.edgeStroke.Transparency = 0
	if fx.still then
		return fx
	end

	-- Under the cue: Secret's red glow, Mythic's sheen and Secret's scan lines (z 4), the rays
	-- (5), the glow (6), the stars (7). The picture is z 8.
	if look.RedGlow then
		local R = M.RedGlow
		local red = sheet(fx, face, "RedGlow", 4)
		red.BackgroundColor3 = hex(R.Color)
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1 - R.HeightShare, 1),
			NumberSequenceKeypoint.new(1 - R.HeightShare * 0.45, 0.6),
			NumberSequenceKeypoint.new(1, 0),
		})
		fade.Parent = red
		fx.redGlow = red
	end
	if look.Sheen then
		local S = M.Sheen
		local sheen = sheet(fx, face, "Sheen", 4)
		sheen.BackgroundTransparency = S.Transparency
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = S.Rotation
		local c = S.Colors
		gradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, hex(c[1])),
			ColorSequenceKeypoint.new(0.3, hex(c[1])),
			ColorSequenceKeypoint.new(0.45, hex(c[2])),
			ColorSequenceKeypoint.new(0.6, hex(c[3])),
			ColorSequenceKeypoint.new(0.7, hex(c[4])),
			ColorSequenceKeypoint.new(1, hex(c[4])),
		})
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.1, 1),
			NumberSequenceKeypoint.new(0.3, 0),
			NumberSequenceKeypoint.new(0.7, 0),
			NumberSequenceKeypoint.new(0.88, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		gradient.Parent = sheen
		fx.sheen, fx.sheenGradient = sheen, gradient
	end
	if look.Scan then
		local S = M.Scan
		local scan = image(fx, face, "Scan", CC.Images.ScanLines, 4)
		scan.Size = UDim2.fromScale(1, 1)
		scan.ImageColor3 = hex(S.Color)
		scan.ImageTransparency = S.Transparency
		corner(scan, "Round")
		fx.scan = scan
	end
	if look.Rays then
		local rays = image(fx, face, "Rays", RAYS, 5)
		rays.AnchorPoint = Vector2.new(0.5, 0.5)
		rays.Position = UDim2.fromScale(M.Rays.At[1], M.Rays.At[2])
		rays.SizeConstraint = Enum.SizeConstraint.RelativeXX
		rays.Size = UDim2.fromScale(M.Rays.Units / UNITS[1], M.Rays.Units / UNITS[1])
		rays.ImageColor3 = hex(look.Rays.Color)
		rays.ImageTransparency = 1 - look.Rays.Strength
		fx.rays = rays
	end
	if look.Glow then
		local glow = image(fx, face, "Glow", ART.SoftGlow, 6)
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(M.Glow.At[1], M.Glow.At[2])
		glow.SizeConstraint = Enum.SizeConstraint.RelativeXX
		glow.Size = UDim2.fromScale(M.Glow.Units / UNITS[1], M.Glow.Units / UNITS[1])
		glow.ImageColor3 = hex(look.Glow.Color)
		glow.ImageTransparency = 1 - look.Glow.Strength
		fx.glow = glow
	end
	if look.Stars then
		local S = M.Stars
		fx.stars = twinkles(
			fx,
			r,
			look.Stars,
			S.Area,
			{ S.Units, S.Units },
			S.Seconds,
			ART.SoftGlow,
			{ "#FFFFFF" },
			7,
			"Star"
		)
		for _, star in fx.stars do
			local share = star.spot.units / UNITS[1]
			star.label.Size = UDim2.fromScale(share, share)
		end
	end

	-- Secret's glitch: two copies of the picture (red, cyan) behind it, shown only mid-glitch.
	if look.Glitch then
		local picture = parts.thumb:FindFirstChild("Picture") :: ImageLabel?
		if picture then
			for i, tint in { M.Glitch.Red, M.Glitch.Cyan } do
				local copy = image(
					fx,
					parts.art,
					if i == 1 then "GlitchRed" else "GlitchCyan",
					picture.Image,
					0
				)
				copy.Size = UDim2.fromScale(1, 1)
				copy.ScaleType = Enum.ScaleType.Fit
				copy.ImageColor3 = hex(tint)
				copy.ImageTransparency = 0.25
				copy.Visible = false
				table.insert(fx.copies, copy)
			end
		end
	end

	-- Over the cue: embers (z 9), sparkles (10), the shine (11).
	if look.Embers then
		local E = M.Embers
		fx.embers = twinkles(
			fx,
			r,
			look.Embers.Count,
			{ E.Area[1], E.FromShare, E.Area[2], E.FromShare },
			{ E.Units, E.Units },
			E.Seconds,
			ART.SoftGlow,
			{ look.Embers.Color },
			9,
			"Ember"
		)
		for _, ember in fx.embers do
			local share = E.Units / UNITS[1]
			ember.label.Size = UDim2.fromScale(share, share)
		end
	end
	if look.Sparks then
		local S = M.Sparks
		fx.sparks = twinkles(
			fx,
			r,
			look.Sparks.Count,
			S.Area,
			S.Units,
			S.Seconds,
			ART.Spark,
			look.Sparks.Colors,
			10,
			"Spark"
		)
	end
	if look.Shine then
		local S = M.Shine
		local shine = sheet(fx, face, "Shine", 11)
		fx.shine = shine
		fx.shineGradient = band(shine, S.Rotation, S.Width, look.Shine.Strength or S.Strength)
		shine.Visible = false
	end

	-- The bar: its colours flowing (Mythic, Reyes) or a light across it (Legendary, Reyes).
	if look.BarShine then
		local B = M.BarShine
		local barShine = sheet(fx, parts.bar, "Shine", 1)
		local round = barShine:FindFirstChild("Round") :: UICorner
		round.CornerRadius = UDim.new(1, 0)
		fx.barShine = barShine
		fx.barShineGradient = band(barShine, M.Shine.Rotation, M.Shine.Width, B.Strength)
		barShine.Visible = false
	end

	-- The edge: a light running round it (Legendary and up), or breathing (Secret); a halo past it.
	if look.EdgeSpin then
		parts.edgeStroke.Color = WHITE
		local gradient = Instance.new("UIGradient")
		gradient.Name = "Spin"
		gradient.Color = sequence(look.EdgeSpin.Colors)
		gradient.Parent = parts.edgeStroke
		table.insert(fx.made, gradient)
		fx.edgeGradient = gradient
	end
	if look.EdgeGlow then
		local halo = image(fx, parts.body, "Halo", ART.SoftGlow, 1)
		halo.ScaleType = Enum.ScaleType.Slice
		halo.SliceCenter = Rect.new(127, 127, 129, 129)
		halo.ImageColor3 = hex(look.EdgeGlow.Color)
		halo.ImageTransparency = 1 - look.EdgeGlow.Strength
		fx.halo = halo
	end

	fx.ancestry = face.AncestryChanged:Connect(function()
		fx.scrollerKnown = false
	end)
	fx.loop = UIAnim.loop(face, function(clock)
		CueCardFx.step(fx, clock)
	end)
	return fx
end

--- Place the parts that are sized in pixels, for a card `k` times its units (InventoryCard's
--- layout calls this after placing the card's own parts), and note where the picture and the
--- name rest (the glitch moves them from there).
function CueCardFx.layout(fx: Fx, k: number, cornerPx: number)
	fx.k = k
	fx.artRest = fx.parts.art.Position
	fx.nameRest = fx.parts.name.Position
	for _, frame in { fx.sheen, fx.redGlow, fx.shine, fx.scan } :: { GuiObject? } do
		if frame then
			local round = frame:FindFirstChild("Round") :: UICorner?
			if round then
				round.CornerRadius = UDim.new(0, cornerPx)
			end
		end
	end
	if fx.halo then
		local g = math.max(4, math.floor(M.EdgeGlow.Units * k + 0.5))
		fx.halo.Position = UDim2.fromOffset(-g, -g)
		fx.halo.Size = UDim2.new(1, 2 * g, 1, 2 * g)
		fx.halo.SliceScale = 2 * g / 128
	end
end

--------------------------------------------------------------------------------------------
-- The loop
--------------------------------------------------------------------------------------------

-- The sparkles twinkle: grow, turn and fade (hidden with Reduce Motion).
local function setTwinkles(list: { Twinkle }, clock: number, reduced: boolean)
	local count = shown(#list)
	for i, t in list do
		local on = i <= count and not reduced
		t.label.Visible = on
		if on then
			local spot = t.spot
			local scale, strength, turn = CardMath.twinkle(clock, spot.seconds, spot.phase)
			local share = spot.units / UNITS[1] * scale
			t.label.Size = UDim2.fromScale(share, share)
			t.label.Rotation = turn
			t.label.ImageTransparency = 1 - strength
		end
	end
end

--- One frame of a card's motion at `clock` seconds (UIAnim.loop's clock: it runs only while
--- the card's screen shows).
function CueCardFx.step(fx: Fx, clock: number)
	if fx.held then
		return
	end
	local parts = fx.parts
	local face = parts.face
	if not fx.scrollerKnown then
		fx.scroller = scrollerOf(face)
		fx.scrollerKnown = true
	end
	if not inView(face, fx.scroller) then
		return
	end
	local look = fx.look
	local ph = fx.phases
	local reduced = UIAnim.reduced()
	local slower = if Quality.isLow() then M.LowerSlower else 1
	local size = face.AbsoluteSize

	-- The 8-balls drift (still with Reduce Motion).
	local sx, sy, offset =
		CardMath.ballsWindow(if reduced then 0 else clock, size.X, size.Y, ph.balls)
	parts.balls.ImageRectSize = Vector2.new(sx, sy)
	parts.balls.ImageRectOffset = Vector2.new(offset, offset)

	-- The glows breathe, even with Reduce Motion.
	if fx.glow then
		local breath = CardMath.breath(clock, M.Glow.Seconds, ph.glow, M.Glow.Low)
		fx.glow.ImageTransparency = 1 - look.Glow.Strength * breath
	end
	if fx.halo then
		local breath = CardMath.breath(clock, M.EdgeGlow.Seconds, ph.halo, M.EdgeGlow.Low)
		fx.halo.ImageTransparency = 1 - look.EdgeGlow.Strength * breath
	end
	if fx.redGlow then
		local R = M.RedGlow
		local breath = CardMath.breath(clock, R.Seconds, ph.red, R.Low)
		fx.redGlow.BackgroundTransparency = 1 - (1 - R.Transparency) * breath
	end
	if look.EdgePulse then
		local E = M.Edge
		parts.edgeStroke.Transparency = 1
			- CardMath.breath(clock, E.PulseSeconds, ph.edge, E.PulseLow)
	end

	if fx.rays and not reduced then
		fx.rays.Rotation = CardMath.turn(clock, look.Rays.Seconds or M.Rays.Seconds, ph.rays)
	end
	if fx.sheenGradient and not reduced then
		local slide = CardMath.sheen(clock, M.Sheen.Seconds * slower, ph.sheen)
		fx.sheenGradient.Offset = Vector2.new(slide, 0)
	end
	if fx.scan then
		local scanH, scanAt = CardMath.scanWindow(if reduced then 0 else clock, size.X, size.Y)
		fx.scan.ImageRectSize = Vector2.new(M.Scan.StripTexels[1], scanH)
		fx.scan.ImageRectOffset = Vector2.new(0, scanAt)
	end
	if fx.edgeGradient and not reduced then
		fx.edgeGradient.Rotation = CardMath.turn(clock, look.EdgeSpin.Seconds * slower, ph.edge)
	end

	setTwinkles(fx.sparks, clock, reduced)
	-- The stars blink (with Reduce Motion they stay, softly lit).
	local stars = shown(#fx.stars)
	for i, star in fx.stars do
		star.label.Visible = i <= stars
		local spot = star.spot
		star.label.ImageTransparency = 1
			- (
				if reduced
					then M.Stars.Low
					else CardMath.breath(clock, spot.seconds, spot.phase, M.Stars.Low)
			)
	end
	local embers = shown(#fx.embers)
	for i, ember in fx.embers do
		local on = i <= embers and not reduced
		ember.label.Visible = on
		if on then
			local E = M.Embers
			local spot = ember.spot
			local rise, strength = CardMath.ember(clock, spot.seconds, spot.phase)
			local up = rise * E.RiseUnits / UNITS[1] * size.X / math.max(1, size.Y)
			ember.label.Position = UDim2.fromScale(spot.x, E.FromShare - up)
			ember.label.ImageTransparency = 1 - strength
		end
	end

	if fx.shine and fx.shineGradient then
		local at = if reduced
			then nil
			else CardMath.shine(clock, look.Shine.Seconds * slower, ph.shine)
		fx.shine.Visible = at ~= nil
		if at then
			fx.shineGradient.Offset = Vector2.new(at, 0)
		end
	end
	if fx.barShine and fx.barShineGradient then
		local B = M.BarShine
		local at = if reduced
			then nil
			else CardMath.shine(clock - B.Delay, B.Seconds * slower, ph.shine)
		fx.barShine.Visible = at ~= nil
		if at then
			fx.barShineGradient.Offset = Vector2.new(at, 0)
		end
	end
	if look.Flow and not reduced then
		local F = M.BarFlow
		local stepNow = math.floor(clock * F.StepsPerSecond)
		if stepNow ~= fx.flowStep then
			fx.flowStep = stepNow
			local keys = {}
			for _, key in CardMath.flow(look.Flow, clock, ph.flow, F.Points) do
				table.insert(
					keys,
					ColorSequenceKeypoint.new(key[1], Color3.new(key[2], key[3], key[4]))
				)
			end
			parts.barGradient.Color = ColorSequence.new(keys)
		end
	end

	if look.Glitch then
		local glitchStep = if reduced then nil else CardMath.glitch(clock, ph.glitch)
		local k = fx.k
		if glitchStep then
			local dx = math.floor(glitchStep.Move[1] * k + 0.5)
			local dy = math.floor(glitchStep.Move[2] * k + 0.5)
			parts.art.Position = fx.artRest + UDim2.fromOffset(dx, dy)
			parts.name.Position = fx.nameRest + UDim2.fromOffset(dx, dy)
		else
			parts.art.Position = fx.artRest
			parts.name.Position = fx.nameRest
		end
		for i, copy in fx.copies do
			local side = if glitchStep
				then (if i == 1 then glitchStep.Red else glitchStep.Cyan)
				else 0
			copy.Visible = side ~= 0
			copy.Position = UDim2.fromOffset(math.floor(side * k + 0.5), 0)
		end
	end
end

--- Hold the motion still (`on`), or let it run again.
function CueCardFx.hold(fx: Fx, on: boolean)
	fx.held = on
end

--- Stop the loop and take the moving parts away (the card's own parts go back to plain).
function CueCardFx.stop(fx: Fx)
	if fx.loop then
		fx.loop.stop()
		fx.loop = nil
	end
	if fx.ancestry then
		fx.ancestry:Disconnect()
		fx.ancestry = nil
	end
	for _, made in fx.made do
		made:Destroy()
	end
	table.clear(fx.made)
	local parts = fx.parts
	parts.art.Position = fx.artRest
	parts.name.Position = fx.nameRest
	parts.edgeStroke.Transparency = 0
end

return CueCardFx
