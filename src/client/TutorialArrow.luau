--!strict
-- TutorialArrow: the arrow to the tutorial's pad, tutorial v2 look A (the designer's pick,
-- 2026-10-09: "WAY more noticeable": white with a thick black outline, bigger, not on the
-- ground, from the player's body to the table).
--
-- - The band: white chevrons at chest height, flowing toward the pad, from just in front of
--   the body to the pad. It is a chain of camera-facing Beams through points on the route,
--   laid from the pad backward: every beam but the one at the body spans a whole number of
--   chevrons, so the pattern runs on without a seam, and the chevrons flow by moving the
--   chain's start (the beam under the arrowhead fades). The texture's top points at a beam's
--   Attachment0, so the pad side is Attachment0.
-- - The route: PathfindingService round the tables (planned again every few seconds or once
--   the player has moved), its corners cut into curves, falling back to a straight line. A new
--   route eases in over its old one (no popping), and the band's end stays on the body.
-- - Over the pad: a big white arrowhead bobbing down at it, and the pad glows (a thin gold
--   neon slab with a white outline: the pad part itself is invisible, its look a SurfaceGui).
-- - Off screen: a small arrow at the screen's edge points the way.
--
-- Everything is built once and reused (no new Instances per frame: phones).
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local TutorialOverlay = require(script.Parent.TutorialOverlay)

local A = Config.Tutorial.Arrow

local TutorialArrow = {}
TutorialArrow.__index = TutorialArrow

export type Arrow = typeof(setmetatable(
	{} :: {
		holder: BasePart,
		points: { Attachment }, -- the band's beam ends (MaxSegments + 1)
		beams: { Beam },
		head: Beam,
		headA: Attachment,
		headB: Attachment,
		glow: BasePart,
		edge: ImageLabel,
		goal: Vector3?,
		pad: BasePart?,
		route: { Vector3 }, -- the planned route on the floor, player end first
		samples: { Vector3 }, -- the band's points from the pad back, Spacing apart (eased)
		target: { Vector3 }, -- what samples ease toward (the route resampled)
		planning: boolean,
		plannedFrom: Vector3?,
		plannedAt: number,
		clock: number,
		urgent: boolean, -- the re-prompt: a stronger pulse, the edge arrow bounces
	},
	TutorialArrow
))

-- The distance between the band's points: whole chevrons, so beams meet without a seam.
local SPACING = A.ChevronStuds * A.SegmentChevrons

local function colour(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function attachment(holder: BasePart, name: string): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = holder
	return a
end

local function beam(holder: BasePart, a0: Attachment, a1: Attachment, texture: string): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Texture = texture
	b.TextureMode = Enum.TextureMode.Wrap
	b.TextureLength = A.ChevronStuds
	b.TextureSpeed = 0 -- the flow moves the points instead (one phase for every beam)
	b.FaceCamera = true
	b.LightInfluence = 0
	b.LightEmission = 0
	b.Segments = 1
	b.Width0 = A.WidthStuds
	b.Width1 = A.WidthStuds
	b.Transparency = NumberSequence.new(0)
	b.Enabled = false
	b.Parent = holder
	return b
end

--- Builds the arrow (hidden). `gui` holds the screen-edge pointer.
function TutorialArrow.new(gui: ScreenGui): Arrow
	local folder = Instance.new("Folder")
	folder.Name = "TutorialArrow"
	folder.Parent = workspace
	local holder = Instance.new("Part")
	holder.Name = "Holder"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one
	holder.CFrame = CFrame.identity -- attachments' positions are world positions
	holder.Parent = folder
	local points = {}
	for i = 1, A.MaxSegments + 1 do
		table.insert(points, attachment(holder, "P" .. i))
	end
	local beams = {}
	for i = 1, A.MaxSegments do
		table.insert(beams, beam(holder, points[i], points[i + 1], A.Chevron))
	end
	local headA = attachment(holder, "HeadTip")
	local headB = attachment(holder, "HeadTail")
	local head = beam(holder, headA, headB, A.Head)
	head.TextureMode = Enum.TextureMode.Stretch
	head.TextureLength = 1
	head.Width0 = A.HeadWidthStuds
	head.Width1 = A.HeadWidthStuds

	local glow = Instance.new("Part")
	glow.Name = "PadGlow"
	glow.Anchored = true
	glow.CanCollide = false
	glow.CanQuery = false
	glow.CanTouch = false
	glow.CastShadow = false
	glow.Material = Enum.Material.Neon
	glow.Color = colour(A.Glow.Fill)
	glow.Transparency = 1
	glow.Parent = folder
	local outline = Instance.new("SelectionBox")
	outline.Name = "Outline"
	outline.Adornee = glow
	outline.Color3 = colour(A.Glow.Outline)
	outline.LineThickness = A.Glow.OutlineStuds
	outline.SurfaceTransparency = 1
	outline.Visible = false
	outline.Parent = glow

	local edge = Instance.new("ImageLabel")
	edge.Name = "ArrowEdge"
	edge.BackgroundTransparency = 1
	edge.Image = A.Head
	edge.ScaleType = Enum.ScaleType.Fit
	edge.AnchorPoint = Vector2.new(0.5, 0.5)
	edge.Visible = false
	edge.ZIndex = 4
	edge.Parent = gui

	local self = setmetatable({
		holder = holder,
		points = points,
		beams = beams,
		head = head,
		headA = headA,
		headB = headB,
		glow = glow,
		edge = edge,
		goal = nil,
		pad = nil,
		route = {},
		samples = {},
		target = {},
		planning = false,
		plannedFrom = nil,
		plannedAt = -math.huge,
		clock = 0,
		urgent = false,
	}, TutorialArrow) :: any
	RunService.RenderStepped:Connect(function(dt: number)
		self:update(dt)
	end)
	return self
end

--- Leads the arrow to `goal` (the pad's top middle) and glows `pad`, or nil to clear it.
function TutorialArrow.show(self: Arrow, goal: Vector3?, pad: BasePart?)
	self.pad = pad
	if goal == self.goal then
		return
	end
	self.goal = goal
	self.plannedAt = -math.huge
	self.route = {}
	self.samples = {}
	self.target = {}
end

--- The re-prompt (the player has not moved on for a while): a stronger pulse, and the edge
--- arrow bounces.
function TutorialArrow.setUrgent(self: Arrow, on: boolean)
	self.urgent = on
end

local function body(): BasePart?
	local character = Players.LocalPlayer.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

-- Cuts each corner of `points` into two (Chaikin), keeping both ends: eased curves.
local function cutCorners(points: { Vector3 }, passes: number): { Vector3 }
	local out = points
	for _ = 1, passes do
		if #out < 3 then
			return out
		end
		local cut: { Vector3 } = { out[1] }
		for i = 1, #out - 1 do
			local a, b = out[i], out[i + 1]
			if i > 1 then
				table.insert(cut, a:Lerp(b, 0.25))
			end
			if i < #out - 1 then
				table.insert(cut, a:Lerp(b, 0.75))
			end
		end
		table.insert(cut, out[#out])
		out = cut
	end
	return out
end

-- The band's height over the floor at `fromPad` studs from the pad: chest height, coming down
-- to over the pad near its end.
local function heightAt(self: Arrow, floorY: number, fromPad: number): number
	local high = floorY + A.HeightStuds
	local goal = self.goal :: Vector3
	local low = goal.Y + A.EndHeightStuds
	local t = math.clamp(fromPad / A.DescendStuds, 0, 1)
	t = t * t * (3 - 2 * t)
	return low + (high - low) * t
end

-- The route resampled from the pad back, SPACING apart, at band height: target[1] is a point
-- one spacing beyond the pad (the flow's start), target[2] the pad end.
local function resample(self: Arrow)
	local route = self.route
	local out: { Vector3 } = {}
	if #route < 2 then
		self.target = out
		return
	end
	-- Walk the route from the pad end.
	local n = #route
	local last = route[n] - route[n - 1]
	local dir = Vector3.new(last.X, 0, last.Z)
	dir = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.zAxis
	local padEnd = route[n]
	local beyond = padEnd + dir * SPACING
	table.insert(out, Vector3.new(beyond.X, heightAt(self, padEnd.Y, 0), beyond.Z))
	table.insert(out, Vector3.new(padEnd.X, heightAt(self, padEnd.Y, 0), padEnd.Z))
	local i = n
	local at = padEnd
	local walked = 0
	local need = SPACING
	while i > 1 and #out < A.MaxSegments + 2 do
		local nextPoint = route[i - 1]
		local gap = (nextPoint - at).Magnitude
		if gap >= need then
			at = at:Lerp(nextPoint, need / gap)
			walked += need
			table.insert(out, Vector3.new(at.X, heightAt(self, at.Y, walked), at.Z))
			need = SPACING
		else
			walked += gap
			need -= gap
			at = nextPoint
			i -= 1
		end
	end
	-- The route's start (where the player stood) closes it.
	if need < SPACING and #out < A.MaxSegments + 2 then
		local start = route[1]
		table.insert(out, Vector3.new(start.X, heightAt(self, start.Y, walked), start.Z))
	end
	self.target = out
end

-- Plans the route in the background (PathfindingService yields).
local function plan(self: Arrow, from: Vector3)
	local goal = self.goal
	if goal == nil or self.planning then
		return
	end
	self.planning = true
	self.plannedFrom = from
	self.plannedAt = self.clock
	task.spawn(function()
		local points: { Vector3 } = {}
		local path = PathfindingService:CreatePath({
			AgentRadius = A.AgentRadius,
			AgentHeight = A.AgentHeight,
			AgentCanJump = false,
		})
		local ok = pcall(function()
			path:ComputeAsync(from, goal)
		end)
		if ok and path.Status == Enum.PathStatus.Success then
			for _, waypoint in path:GetWaypoints() do
				table.insert(points, waypoint.Position)
			end
		end
		if #points < 2 then
			points = { from, goal }
		end
		points[#points] = Vector3.new(goal.X, points[#points].Y, goal.Z)
		self.planning = false
		if self.goal == goal then
			self.route = cutCorners(points, A.CornerPasses)
			resample(self)
		end
	end)
end

-- The point `s` studs from the pad along the eased samples (samples[1] is SPACING beyond it).
local function pointAt(samples: { Vector3 }, s: number): Vector3
	local f = s / SPACING + 2 -- samples[2] is s = 0
	local i = math.clamp(math.floor(f), 1, #samples - 1)
	return samples[i]:Lerp(samples[i + 1], math.clamp(f - i, 0, 1))
end

-- How far from the pad (along the samples) the point nearest `where` lies.
local function nearest(samples: { Vector3 }, where: Vector3): number
	local best, bestS = math.huge, 0
	for i = 2, #samples - 1 do
		local a, b = samples[i], samples[i + 1]
		local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local aw = Vector3.new(where.X - a.X, 0, where.Z - a.Z)
		local len2 = ab:Dot(ab)
		local t = if len2 > 1e-6 then math.clamp(aw:Dot(ab) / len2, 0, 1) else 0
		local gap = (aw - ab * t).Magnitude
		if gap < best then
			best = gap
			bestS = (i - 2 + t) * SPACING
		end
	end
	return bestS
end

local function hide(self: Arrow)
	for _, b in self.beams do
		b.Enabled = false
	end
	self.head.Enabled = false
	self.glow.Transparency = 1
	local outline = self.glow:FindFirstChild("Outline") :: SelectionBox
	outline.Visible = false
	self.edge.Visible = false
end

-- A fade from opaque to clear over `share` of a beam at its Attachment0 (pad) end, or at its
-- Attachment1 (body) end.
local function fade(share: number, atStart: boolean): NumberSequence
	local s = math.clamp(share, 0.01, 0.99)
	if atStart then
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(s, 0),
			NumberSequenceKeypoint.new(1, 0),
		})
	end
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1 - s, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local SOLID = NumberSequence.new(0)

-- The small arrow at the screen's edge while the pad is off screen.
local function placeEdge(self: Arrow, goal: Vector3)
	local camera = workspace.CurrentCamera
	if camera == nil then
		self.edge.Visible = false
		return
	end
	-- In the overlay's pixels, kept inside the play area (in from a phone's notch).
	local v, onScreen = camera:WorldToScreenPoint(goal)
	local view = camera.ViewportSize
	if onScreen and v.Z > 0 then
		self.edge.Visible = false
		return
	end
	local play = TutorialOverlay.areas().play
	local middle = Vector2.new(play.x + play.w / 2, play.y + play.h / 2)
	local d = TutorialOverlay.toLayer(Vector2.new(v.X, v.Y)) - middle
	if v.Z < 0 then
		d = -d -- behind the camera: the projection is mirrored
	end
	if d.Magnitude < 1e-3 then
		d = Vector2.new(0, 1)
	end
	local small = math.min(view.X, view.Y) < Config.Tutorial.Overlay.PhoneBelowPx
	local size = if small then A.Edge.PhoneSizePx else A.Edge.SizePx
	local margin = A.Edge.MarginPx + size / 2
	local half = Vector2.new(play.w / 2 - margin, play.h / 2 - margin)
	local scale =
		math.min(half.X / math.max(math.abs(d.X), 1e-3), half.Y / math.max(math.abs(d.Y), 1e-3))
	local unit = d.Unit
	local bob = (if self.urgent then 2 else 1)
		* A.Edge.BobPx
		* (0.5 + 0.5 * math.sin(self.clock * math.pi * 2 / A.Edge.BobSeconds))
	local at = middle + d * scale - unit * bob
	self.edge.Visible = true
	self.edge.Size = UDim2.fromOffset(size, size)
	self.edge.Position = UDim2.fromOffset(at.X, at.Y)
	-- The image points up; turn it toward the pad.
	self.edge.Rotation = math.deg(math.atan2(unit.X, -unit.Y))
end

function TutorialArrow.update(self: Arrow, dt: number)
	self.clock += dt
	local root = body()
	local goal = self.goal
	if goal == nil or root == nil then
		hide(self)
		return
	end
	local feet = root.Position - Vector3.new(0, A.FeetBelowRoot, 0)
	local moved = if self.plannedFrom then (feet - self.plannedFrom).Magnitude else math.huge
	if moved > A.ReplanMovedStuds or self.clock - self.plannedAt > A.ReplanSeconds then
		plan(self, feet)
	end
	placeEdge(self, goal)
	-- The pad glows and the arrowhead bobs over it.
	local pad = self.pad
	local wave = 0.5 + 0.5 * math.sin(self.clock * math.pi * 2 / A.PulseSeconds)
	local outline = self.glow:FindFirstChild("Outline") :: SelectionBox
	if pad then
		self.glow.Size = Vector3.new(pad.Size.X, A.Glow.SlabStuds, pad.Size.Z)
		self.glow.CFrame = pad.CFrame * CFrame.new(0, pad.Size.Y / 2 + A.Glow.SlabStuds, 0)
		self.glow.Transparency = A.Glow.FillMax - (A.Glow.FillMax - A.Glow.FillMin) * wave
		outline.Visible = true
	else
		self.glow.Transparency = 1
		outline.Visible = false
	end
	local bob = A.HeadBobStuds * (0.5 + 0.5 * math.sin(self.clock * math.pi * 2 / A.HeadBobSeconds))
	local tip = goal + Vector3.new(0, A.HeadLiftStuds + bob, 0)
	self.headA.WorldPosition = tip
	self.headB.WorldPosition = tip + Vector3.new(0, A.HeadStuds, 0)
	self.head.Enabled = true
	-- The band's points ease toward the newest route.
	local target, samples = self.target, self.samples
	if #target < 3 then
		for _, b in self.beams do
			b.Enabled = false
		end
		return
	end
	local k = 1 - math.exp(-dt / A.EaseSeconds)
	for i, point in target do
		local old = samples[i]
		samples[i] = if old then old:Lerp(point, k) else point
	end
	for i = #samples, #target + 1, -1 do
		samples[i] = nil
	end
	-- From the pad to just in front of the body.
	local fromPad = nearest(samples, root.Position)
	local reach = math.min(fromPad - A.StartGapStuds, (#samples - 2) * SPACING)
	local phase = (self.clock * A.SpeedStudsPerSecond) % SPACING
	local pulse = 1 + A.PulseScale * (if self.urgent then 2 else 1) * wave
	local width = A.WidthStuds * pulse
	local used = 0
	local s = -phase
	local points = self.points
	if reach > 0 then
		points[1].WorldPosition = pointAt(samples, s)
		while s < reach and used < #self.beams do
			local e = math.min(s + SPACING, reach)
			used += 1
			points[used + 1].WorldPosition = pointAt(samples, e)
			local b = self.beams[used]
			b.Width0, b.Width1 = width, width
			if used == 1 then
				-- Under the arrowhead: the chevrons fade into the pad.
				b.Transparency = fade((phase + A.FadeStuds) / math.max(e - s, 1e-3), true)
			elseif e >= reach then
				-- At the body: they fade in from it.
				b.Transparency = fade(A.FadeStuds / math.max(e - s, 1e-3), false)
			else
				b.Transparency = SOLID
			end
			b.Enabled = true
			s = e
		end
	end
	for i = used + 1, #self.beams do
		self.beams[i].Enabled = false
	end
end

return TutorialArrow
