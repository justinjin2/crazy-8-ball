--!strict
-- TutorialArrow: the line of white arrows on the floor from the player to the tutorial's pad
-- (docs/prompts/TUTORIAL_PROMPT.md step 2, after reference 02's arrow path: one line of solid
-- white up-arrows lying flat, evenly spaced, flowing toward the target).
--
-- The route comes from PathfindingService (round the tables and seats), planned again every
-- few seconds or once the player has moved, falling back to a straight line. The arrows are
-- flat client-only parts with the arrow image on top, sliding along the route and fading in
-- at the player's feet and out at the pad.
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local A = Config.Tutorial.Arrow
local ART = Config.Tutorial.Art

local TutorialArrow = {}
TutorialArrow.__index = TutorialArrow

export type Arrow = typeof(setmetatable(
	{} :: {
		folder: Folder,
		parts: { BasePart },
		goal: Vector3?,
		route: { Vector3 },
		lengths: { number }, -- distance along the route at each point
		total: number,
		planning: boolean,
		plannedFrom: Vector3?,
		plannedAt: number,
		clock: number,
	},
	TutorialArrow
))

local function makeArrow(parent: Instance, i: number): BasePart
	local part = Instance.new("Part")
	part.Name = "Arrow" .. i
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(A.SizeStuds, 0.05, A.SizeStuds)
	local decal = Instance.new("Decal")
	decal.Name = "Image"
	decal.Face = Enum.NormalId.Top
	decal.Texture = ART.FloorArrow
	decal.Parent = part
	part.Parent = parent
	return part
end

function TutorialArrow.new(): Arrow
	local folder = Instance.new("Folder")
	folder.Name = "TutorialArrow"
	folder.Parent = workspace
	local parts = {}
	for i = 1, A.MaxArrows do
		local part = makeArrow(folder, i)
		part.Parent = nil
		table.insert(parts, part)
	end
	local self = setmetatable({
		folder = folder,
		parts = parts,
		goal = nil,
		route = {},
		lengths = {},
		total = 0,
		planning = false,
		plannedFrom = nil,
		plannedAt = -math.huge,
		clock = 0,
	}, TutorialArrow)
	RunService.RenderStepped:Connect(function(dt: number)
		self:update(dt)
	end)
	return self
end

--- Leads the arrows to `goal` (a point on the floor), or nil to clear them.
function TutorialArrow.show(self: Arrow, goal: Vector3?)
	if goal == self.goal then
		return
	end
	self.goal = goal
	self.plannedAt = -math.huge
	if goal == nil then
		self.route = {}
		self.total = 0
	end
end

local function root(): BasePart?
	local character = Players.LocalPlayer.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function setRoute(self: Arrow, points: { Vector3 })
	local lengths = { 0 }
	local total = 0
	for i = 2, #points do
		total += (points[i] - points[i - 1]).Magnitude
		lengths[i] = total
	end
	self.route = points
	self.lengths = lengths
	self.total = total
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
		self.planning = false
		if self.goal == goal then
			setRoute(self, points)
		end
	end)
end

-- The point and direction at `d` along the route.
local function along(self: Arrow, d: number): (Vector3, Vector3)
	local route, lengths = self.route, self.lengths
	for i = 2, #route do
		if d <= lengths[i] or i == #route then
			local a, b = route[i - 1], route[i]
			local span = lengths[i] - lengths[i - 1]
			local t = if span > 0 then math.clamp((d - lengths[i - 1]) / span, 0, 1) else 0
			local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			return a:Lerp(b, t), if dir.Magnitude > 1e-3 then dir.Unit else Vector3.zAxis
		end
	end
	return route[1], Vector3.zAxis
end

function TutorialArrow.update(self: Arrow, dt: number)
	self.clock += dt
	local body = root()
	if self.goal == nil or body == nil then
		for _, part in self.parts do
			part.Parent = nil
		end
		return
	end
	local here = body.Position - Vector3.new(0, A.FeetBelowRoot, 0)
	local moved = if self.plannedFrom then (here - self.plannedFrom).Magnitude else math.huge
	if moved > A.ReplanMovedStuds or self.clock - self.plannedAt > A.ReplanSeconds then
		plan(self, here)
	end
	-- The route starts where the player stood when it was planned; the arrows start at the
	-- route point nearest the player now, so walking along it eats the line up.
	local startAt = 0
	if #self.route >= 2 then
		local best = math.huge
		for i, point in self.route do
			local gap = (Vector3.new(point.X, here.Y, point.Z) - here).Magnitude
			if gap < best then
				best = gap
				startAt = self.lengths[i]
			end
		end
	end
	local offset = (self.clock * A.SpeedStudsPerSecond) % A.SpacingStuds
	local used = 0
	local d = startAt + A.StartGapStuds + offset
	while d < self.total - A.EndGapStuds and used < #self.parts do
		used += 1
		local part = self.parts[used]
		local at, dir = along(self, d)
		local floor = at + Vector3.new(0, A.LiftStuds, 0)
		part.CFrame = CFrame.lookAt(floor, floor + dir)
			* CFrame.Angles(0, math.rad(A.ImageTurnDegrees), 0)
		local fromStart = d - startAt - A.StartGapStuds
		local toEnd = self.total - A.EndGapStuds - d
		local edge = math.min(fromStart, toEnd)
		local decal = part:FindFirstChild("Image") :: Decal
		decal.Transparency = A.Transparency
			+ (1 - A.Transparency) * (1 - math.clamp(edge / A.FadeStuds, 0, 1))
		if part.Parent == nil then
			part.Parent = self.folder
		end
		d += A.SpacingStuds
	end
	for i = used + 1, #self.parts do
		self.parts[i].Parent = nil
	end
end

return TutorialArrow
