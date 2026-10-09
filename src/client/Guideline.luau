--!strict
-- Guideline: the aim trace on the table, in the style of the classic phone pool games.
--   * a corridor one ball wide from the cue ball to the first contact: two thin solid edge
--     lines a ball radius either side of the aim, with a faint dashed centre line whose
--     dashes scroll towards the target so the direction is obvious
--   * a white ring outline where the cue ball will be at first contact (the "ghost" ball)
--   * thin solid lines for where the object ball goes and where the cue ball deflects
--   * on a jump shot, a small ring where the cue ball comes down each time, and a red cross
--     where it would fly off the table
--   * on a jump shot at a level that draws Arc: the flight itself, dots along the cue ball's
--     path through the air (every hop) drifting toward the target, a faint shadow line on the
--     cloth under each hop, and the corridor starting where the ball settles
-- How much of it a table draws is its difficulty (Config.Difficulty); the red cross is
-- always drawn. With Fire Shot armed (Aim.fullLines) everything is drawn, and the object
-- ball's and the cue ball's lines run on to the next cushion, ball or pocket.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Placement = require(Shared:WaitForChild("Placement"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))
local Aim = require(Shared:WaitForChild("Physics"):WaitForChild("Aim"))
local TutorialAnchors = require(script.Parent.TutorialAnchors)

type Trace = Aim.Trace
type Hop = Aim.Hop
type FullLines = Aim.FullLines

local Guideline = {}
Guideline.__index = Guideline

type Strip = { part: Part, texture: Texture? }

export type Guideline = typeof(setmetatable(
	{} :: {
		folder: Folder,
		placement: Placement.Placement,
		ring: Part,
		path: Strip,
		leftEdge: Strip,
		rightEdge: Strip,
		objectStub: Strip,
		cueStub: Strip,
		crosses: { Strip },
		landings: { Part },
		dots: { Part }, -- the jump's flight (Config.Guideline.Arc)
		dotsShown: number, -- dots 1..dotsShown are drawn
		shadows: { Strip }, -- a line on the cloth under each hop
		hops: { Hop }?, -- the hops the dots follow, while an arc is drawn
		arcPhase: number, -- inches the dots have drifted along, 0..DotSpacingInches
		scroll: number,
		-- The ghost ball's centre (inches) while a ball or cushion contact is shown, for the
		-- abilities' reach preview (AbilityFx); nil while hidden.
		aimContact: { x: number, y: number }?,
		tint: Color3, -- the lines' colour now (orange while Fire Shot is armed)
	},
	Guideline
))

local function lineColor(): Color3
	local c = Config.Guideline.Color
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function flatPart(name: string, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = lineColor()
	part.Transparency = 1
	part.Size = Vector3.new(0.05, 0.01, 1)
	part.Parent = parent
	return part
end

local function makeStrip(name: string, parent: Instance, dashed: boolean): Strip
	local G = Config.Guideline
	local part = flatPart(name, parent)
	local texture: Texture? = nil
	if dashed and G.DashTextureId ~= "" then
		local tex = Instance.new("Texture")
		tex.Name = "Dashes"
		tex.Face = Enum.NormalId.Top
		tex.Texture = G.DashTextureId
		tex.Color3 = lineColor()
		tex.Transparency = 1
		tex.StudsPerTileU = G.LineWidthStuds
		tex.StudsPerTileV = G.DashTileStuds
		tex.Parent = part
		texture = tex
	end
	return { part = part, texture = texture }
end

function Guideline.new(parent: Instance, p: Placement.Placement): Guideline
	local G = Config.Guideline
	local folder = Instance.new("Folder")
	folder.Name = "Guideline"
	folder.Parent = parent

	-- Ring: a flat square carrying the circle-outline image, sized to the ball.
	local function makeRing(name: string, scale: number): Part
		local ring = flatPart(name, folder)
		local d = TableBuilder.studs(Config.Balls.RenderRadiusInches * 2) * scale
		ring.Size = Vector3.new(d, 0.01, d)
		if G.RingTextureId ~= "" then
			local decal = Instance.new("Decal")
			decal.Name = "Outline"
			decal.Face = Enum.NormalId.Top
			decal.Texture = G.RingTextureId
			decal.Color3 = lineColor()
			decal.Transparency = 1
			decal.Parent = ring
		end
		return ring
	end
	local ring = makeRing("Ring", G.RingScale)
	local landings = {}
	for i = 1, G.MaxLandingMarks do
		table.insert(landings, makeRing("Landing" .. i, G.LandingRingScale))
	end

	-- The flight's dots and the shadow line under each hop.
	local A = G.Arc
	local dots = {}
	local dotSize = TableBuilder.studs(A.DotDiameterInches)
	for i = 1, A.MaxDots do
		local dot = flatPart("ArcDot" .. i, folder)
		dot.Shape = Enum.PartType.Ball
		dot.CanTouch = false
		dot.Size = Vector3.new(dotSize, dotSize, dotSize)
		table.insert(dots, dot)
	end
	local shadows = {}
	for i = 1, A.MaxHops do
		table.insert(shadows, makeStrip("ArcShadow" .. i, folder, false))
	end

	local self = setmetatable({
		folder = folder,
		placement = p,
		ring = ring,
		path = makeStrip("Path", folder, true),
		leftEdge = makeStrip("LeftEdge", folder, false),
		rightEdge = makeStrip("RightEdge", folder, false),
		objectStub = makeStrip("ObjectStub", folder, false),
		cueStub = makeStrip("CueStub", folder, false),
		crosses = { makeStrip("InvalidA", folder, false), makeStrip("InvalidB", folder, false) },
		landings = landings,
		dots = dots,
		dotsShown = 0,
		shadows = shadows,
		hops = nil,
		arcPhase = 0,
		scroll = 0,
		aimContact = nil,
		tint = lineColor(),
	}, Guideline)
	return self
end

-- Paint every line, ring and dot `color` (the red cross keeps its own).
local function paint(self: Guideline, color: Color3)
	self.tint = color
	local strips = { self.path, self.leftEdge, self.rightEdge, self.objectStub, self.cueStub }
	for _, shadow in self.shadows do
		table.insert(strips, shadow)
	end
	for _, strip in strips do
		strip.part.Color = color
		if strip.texture then
			strip.texture.Color3 = color
		end
	end
	local rings = table.clone(self.landings)
	table.insert(rings, self.ring)
	for _, ring in rings do
		ring.Color = color
		local outline = ring:FindFirstChild("Outline")
		if outline and outline:IsA("Decal") then
			outline.Color3 = color
		end
	end
	for _, dot in self.dots do
		dot.Color = color
	end
end

local function setRing(ring: Part, transparency: number)
	local outline = ring:FindFirstChild("Outline")
	if outline and outline:IsA("Decal") then
		outline.Transparency = transparency
	else
		ring.Transparency = transparency
	end
end

local function hideStrip(strip: Strip)
	strip.part.Transparency = 1
	if strip.texture then
		strip.texture.Transparency = 1
	end
end

-- Lay a strip flat from (x1, y1) to (x2, y2) in inches on table `p`. Local +Z runs
-- start -> target so the dash texture's V axis follows the line.
local function placeStrip(
	strip: Strip,
	p: Placement.Placement,
	x1: number,
	y1: number,
	x2: number,
	y2: number,
	transparency: number,
	width: number?
)
	local G = Config.Guideline
	local h = G.HeightAboveClothInches
	local a = TableBuilder.toWorld(p, x1, y1, h)
	local b = TableBuilder.toWorld(p, x2, y2, h)
	local len = (b - a).Magnitude
	if len < 1e-4 then
		hideStrip(strip)
		return
	end
	strip.part.Size = Vector3.new(width or G.LineWidthStuds, 0.01, len)
	strip.part.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi, 0)
	if strip.texture then
		strip.part.Transparency = 1
		strip.texture.Transparency = transparency
	else
		strip.part.Transparency = transparency
	end
end

-- What a level draws when the lines are full (Fire Shot armed): everything.
local FULL_DRAWS = { Corridor = true, Stubs = true, Landings = true, Arc = true }

--- Draw `trace` at difficulty `level` (a Config.Difficulty.Levels key; nil is the default).
--- `full` (Aim.fullLines, Fire Shot armed): the lines after the first contact run on to the
--- next cushion, ball or pocket, everything is drawn whatever the difficulty, and the lines are
--- orange (Config.Guideline.FullColor).
function Guideline.show(
	self: Guideline,
	trace: Trace,
	invalid: boolean?,
	level: string?,
	full: FullLines?
)
	if trace.contact == "none" then
		self:hide()
		return
	end
	if trace.contact == "off" then
		self.aimContact = nil
	else
		local contact = self.aimContact
		if contact then
			contact.x, contact.y = trace.ghostX, trace.ghostY
		else
			self.aimContact = { x = trace.ghostX, y = trace.ghostY }
		end
	end
	local D = Config.Difficulty
	local draws = if full then FULL_DRAWS else D.Levels[level or D.Default] or D.Levels[D.Default]
	local G = Config.Guideline
	-- Fire Shot's lines are orange (designer, 2026-10-09), the same lines otherwise.
	local tint = if full
		then Color3.fromRGB(G.FullColor[1], G.FullColor[2], G.FullColor[3])
		else lineColor()
	if tint ~= self.tint then
		paint(self, tint)
	end
	local R = Config.Balls.RadiusInches
	local ringR = Config.Balls.RenderRadiusInches * G.RingScale
	-- The tutorial's game 1 draws the longer line (the tutorial lane).
	local stub = if TutorialAnchors.game1() then G.TutorialStubLengthInches else G.StubLengthInches

	-- A jump at a level that draws its flight: the arc in the air, and the corridor only from
	-- where the ball settles (none when it meets something in the air).
	local arc = draws.Arc == true and #trace.hops > 0
	self:drawArc(if arc then trace.hops else nil)
	local fromX, fromY = trace.startX, trace.startY
	if arc then
		local last = trace.hops[#trace.hops]
		fromX, fromY = last.x + last.vx * last.seconds, last.y + last.vy * last.seconds
	end

	-- Corridor from the cue ball to the ghost ball: edges a ball radius either side of the
	-- aim line, running from under the cue ball to the sides of the ring; the dashed centre
	-- line runs from the cue ball's front edge to the ring's near edge.
	local dx, dy = trace.ghostX - fromX, trace.ghostY - fromY
	local len = math.sqrt(dx * dx + dy * dy)
	if draws.Corridor and not (arc and trace.airborne) and len > R + ringR then
		local ux, uy = dx / len, dy / len
		local px, py = -uy, ux -- perpendicular to the aim
		local function placeEdge(strip: Strip, sgn: number)
			placeStrip(
				strip,
				self.placement,
				fromX + px * R * sgn,
				fromY + py * R * sgn,
				trace.ghostX + px * R * sgn,
				trace.ghostY + py * R * sgn,
				G.EdgeTransparency,
				G.EdgeWidthStuds
			)
		end
		placeEdge(self.leftEdge, 1)
		placeEdge(self.rightEdge, -1)
		if G.ShowCentreLine then
			placeStrip(
				self.path,
				self.placement,
				fromX + ux * R,
				fromY + uy * R,
				trace.ghostX - ux * ringR,
				trace.ghostY - uy * ringR,
				G.CentreLineTransparency
			)
		else
			hideStrip(self.path)
		end
	else
		hideStrip(self.path)
		hideStrip(self.leftEdge)
		hideStrip(self.rightEdge)
	end

	self.ring.CFrame = CFrame.new(
		TableBuilder.toWorld(self.placement, trace.ghostX, trace.ghostY, G.HeightAboveClothInches)
	)
	setRing(self.ring, if draws.Corridor then G.LineTransparency else 1)
	-- Where a jump comes down on the way.
	for index, mark in self.landings do
		local spot = draws.Landings and trace.landings[index]
		if spot then
			mark.CFrame = CFrame.new(
				TableBuilder.toWorld(self.placement, spot.x, spot.y, G.HeightAboveClothInches)
			)
			setRing(mark, G.LandingTransparency)
		else
			setRing(mark, 1)
		end
	end

	-- Flying off the table is marked like an illegal target: a red cross, no stubs.
	local off = trace.contact == "off"
	invalid = invalid or off
	for index, cross in self.crosses do
		if invalid then
			local sign = if index == 1 then 1 else -1
			local color = Config.Multiplayer.Style.Red
			cross.part.Color = Color3.fromRGB(color[1], color[2], color[3])
			placeStrip(
				cross,
				self.placement,
				trace.ghostX - ringR,
				trace.ghostY - ringR * sign,
				trace.ghostX + ringR,
				trace.ghostY + ringR * sign,
				G.LineTransparency,
				G.EdgeWidthStuds
			)
		else
			hideStrip(cross)
		end
	end
	if invalid or not draws.Stubs then
		hideStrip(self.objectStub)
		hideStrip(self.cueStub)
		return
	end
	-- Object ball direction: from the object ball's far edge outward. Both short lines grow
	-- and shrink with how full the hit is (Aim.Trace objectShare/cueShare): a straight-on hit
	-- sends the object ball the full length and barely deflects the cue ball, a thin cut
	-- the reverse.
	-- Full lines (Fire Shot) run from the same starts on until each touches what it meets:
	-- Aim.fullLines says where that ball's centre is then (from the object ball's centre and
	-- from the ghost ball's), and the line goes a radius further, to the cushion or the ball.
	local objectLen = if full and full.object
		then full.object + R - ringR
		else stub * trace.objectShare
	local cueLen = if full and full.cue
		then full.cue + R - ringR
		elseif trace.contact == "ball" then stub * G.CueStubScale * trace.cueShare
		else stub * G.RailStubScale
	if trace.contact == "ball" and objectLen >= G.MinStubInches then
		local ox, oy =
			trace.ghostX + trace.objectDirX * (ringR + 2 * R),
			trace.ghostY + trace.objectDirY * (ringR + 2 * R)
		placeStrip(
			self.objectStub,
			self.placement,
			ox,
			oy,
			ox + trace.objectDirX * objectLen,
			oy + trace.objectDirY * objectLen,
			G.StubTransparency
		)
	else
		hideStrip(self.objectStub)
	end
	-- Cue ball deflection: from the ring's edge outward.
	if cueLen < G.MinStubInches then
		hideStrip(self.cueStub)
		return
	end
	local cx, cy = trace.ghostX + trace.cueDirX * ringR, trace.ghostY + trace.cueDirY * ringR
	placeStrip(
		self.cueStub,
		self.placement,
		cx,
		cy,
		cx + trace.cueDirX * cueLen,
		cy + trace.cueDirY * cueLen,
		G.StubTransparency
	)
end

--- Scroll the dashes towards the target. Call every frame.
function Guideline.update(self: Guideline, dt: number)
	local G = Config.Guideline
	self.scroll = (self.scroll + dt * G.DashSpeed * G.DashTileStuds) % G.DashTileStuds
	local offset = if G.DashFlip then self.scroll else -self.scroll
	if self.path.texture then
		self.path.texture.OffsetStudsV = offset
	end
	local A = G.Arc
	self.arcPhase = (self.arcPhase + dt * A.DriftInchesPerSecond) % A.DotSpacingInches
	if self.hops then
		self:placeDots(self.hops)
	end
end

--- Draw a jump's flight (`hops` from Aim.Trace), or take it away (nil).
function Guideline.drawArc(self: Guideline, hops: { Hop }?)
	self.hops = hops
	local A = Config.Guideline.Arc
	for index, shadow in self.shadows do
		local hop = hops and hops[index]
		if hop then
			local t = hop.seconds
			placeStrip(
				shadow,
				self.placement,
				hop.x,
				hop.y,
				hop.x + hop.vx * t,
				hop.y + hop.vy * t,
				A.ShadowTransparency,
				Config.Guideline.EdgeWidthStuds
			)
		else
			hideStrip(shadow)
		end
	end
	if hops then
		self:placeDots(hops)
	else
		self:showDots(0)
	end
end

-- Show dots 1..count and hide the rest (only those that change).
function Guideline.showDots(self: Guideline, count: number)
	local A = Config.Guideline.Arc
	if count == self.dotsShown then
		return
	end
	for i = math.min(count, self.dotsShown) + 1, math.max(count, self.dotsShown) do
		self.dots[i].Transparency = if i <= count then A.DotTransparency else 1
	end
	self.dotsShown = count
end

-- The dots along the hops: every DotSpacingInches of travel over the cloth, shifted by the
-- drift, at the ball centre's height.
function Guideline.placeDots(self: Guideline, hops: { Hop })
	local A = Config.Guideline.Arc
	local g = Config.Physics.Gravity
	local lift = Config.Balls.RenderRadiusInches
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	local start = 0 -- the distance along the flight where this hop begins
	local nextAt = self.arcPhase -- the distance of the next dot
	for _, hop in hops do
		local speed = math.sqrt(hop.vx * hop.vx + hop.vy * hop.vy)
		local length = speed * hop.seconds
		if speed > 1e-6 then
			while nextAt <= start + length and #parts < #self.dots do
				local t = (nextAt - start) / speed
				local z = hop.z + hop.vz * t - 0.5 * g * t * t
				local at = TableBuilder.toWorld(
					self.placement,
					hop.x + hop.vx * t,
					hop.y + hop.vy * t,
					lift + math.max(z, 0)
				)
				table.insert(parts, self.dots[#parts + 1])
				table.insert(frames, CFrame.new(at))
				nextAt += A.DotSpacingInches
			end
		end
		start += length
	end
	if #parts > 0 then
		workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	self:showDots(#parts)
end

--- Tear the guideline down. The local player only has one at a time, so moving to another
--- table destroys this one rather than leaving a second set of strips behind.
function Guideline.destroy(self: Guideline)
	self.folder:Destroy()
end

--- Where the cue ball's centre is at the first contact shown (inches), or nil while hidden or
--- flying off the table. AbilityFx draws the reach preview there.
function Guideline.contact(self: Guideline): { x: number, y: number }?
	return self.aimContact
end

function Guideline.hide(self: Guideline)
	self.aimContact = nil
	for _, cross in self.crosses do
		hideStrip(cross)
	end
	hideStrip(self.path)
	hideStrip(self.leftEdge)
	hideStrip(self.rightEdge)
	hideStrip(self.objectStub)
	hideStrip(self.cueStub)
	setRing(self.ring, 1)
	for _, mark in self.landings do
		setRing(mark, 1)
	end
	self:drawArc(nil)
end

return Guideline
