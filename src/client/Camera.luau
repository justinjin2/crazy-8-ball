--!strict
-- Camera: the single aim view. The camera orbits a focus point inside the table, on the
-- side opposite the aim, so it always looks across the table along the aim. Every frame it
-- solves for the closest distance (and shallowest pitch) that keeps the whole table on
-- screen for the current viewport, so the table is always fully visible at the tightest
-- framing the screen allows. Zooming in closes on the cue ball. While a shot plays it holds
-- its position and lets its gaze drift toward the cue ball.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Placement = require(Shared:WaitForChild("Placement"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))

local Camera = {}

-- There is one camera per client and the player is only ever at one table, so the table
-- being played lives here as module state rather than being threaded through the eight
-- private framing functions below (six of which would only pass it on).
local placement: Placement.Placement = assert(
	Placement.forTable(Config.Lounge.ActiveTableId),
	"Config.Lounge.ActiveTableId names no table"
)

-- Outer corners of the table (rails included) at cloth height, in world space. Cached
-- because the framing solver asks for them many times a frame; setTable clears it, which
-- is what stops a stale cache once the table being framed changes.
local tableCorners: { Vector3 }? = nil

local locked = false
local connections: { RBXScriptConnection } = {}
-- Position along the scroll axis: 0 is closest on the ball, 1 is straight down, and the
-- resting view sits where the low range ends. Counted in notches rather than in a distance,
-- because the two halves of the range deserve very different numbers of them.
--
-- This is REMEMBERED: it survives shots and re-seating, so a player who picks a framing
-- keeps it instead of being put back to the resting view every time the balls stop.
local zoomU = (function(): number
	local V = Config.Camera.View
	return V.ZoomNotchesLow / math.max(V.ZoomNotchesLow + V.ZoomNotchesTop, 1)
end)()
local anchor: Vector3? = nil -- cue ball position the view is built around (frozen during a shot)
local anchorDir: Vector3? = nil
local returnTimer = 0 -- seconds of slower easing left after a shot ends
local wasPlaying = false

--- World-space aim direction for a physics angle on the current table. The angle is in
--- table space, so the table's yaw turns it: at yaw 0 this is (cos, 0, -sin) as before.
function Camera.aimDirection(angle: number): Vector3
	return TableBuilder.aimDirection(placement, angle)
end

--- The table the camera frames. Call on joining a table, before lock/snap.
function Camera.setTable(p: Placement.Placement)
	placement = p
	tableCorners = nil
end

--- The placement the camera is currently framing.
function Camera.placement(): Placement.Placement
	return placement
end

local function takeOver()
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = Config.Camera.View.FieldOfView
end

--- Take control of the camera (and keep it even when Roblox's default scripts reset it
--- on spawn).
function Camera.lock()
	if locked then
		return
	end
	locked = true
	takeOver()
	local function watch(cam: Camera)
		table.insert(
			connections,
			cam:GetPropertyChangedSignal("CameraType"):Connect(function()
				if locked and cam.CameraType ~= Enum.CameraType.Scriptable then
					takeOver()
				end
			end)
		)
	end
	watch(Workspace.CurrentCamera)
	table.insert(
		connections,
		Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			local cam = Workspace.CurrentCamera
			if cam and locked then
				watch(cam)
				takeOver()
			end
		end)
	)
end

--- Hand the camera back to Roblox's default character camera.
function Camera.unlock()
	if not locked then
		return
	end
	locked = false
	for _, c in connections do
		c:Disconnect()
	end
	connections = {}
	anchor = nil
	anchorDir = nil
	returnTimer = 0
	wasPlaying = false
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = 70
end

function Camera.isLocked(): boolean
	return locked
end

-- Total notches across the whole range, and where the resting view sits along it.
local function notches(): (number, number)
	local V = Config.Camera.View
	local total = math.max(V.ZoomNotchesLow + V.ZoomNotchesTop, 1)
	return total, V.ZoomNotchesLow / total
end

--- Zoom by a factor (> 1 = closer). A factor of Config.Input.ZoomStep is exactly one notch,
--- which is what lets a continuous pinch or gamepad stick share the axis with a mouse wheel.
function Camera.zoomBy(factor: number)
	local total = notches()
	local step = math.max(Config.Input.ZoomStep, 1.0001)
	zoomU = math.clamp(zoomU - math.log(factor) / math.log(step) / total, 0, 1)
end

--- Back to the resting view: the top of the useful range, just before it tips overhead.
--- Used when leaving the table and after every shot.
function Camera.resetZoom()
	local _, rest = notches()
	zoomU = rest
end

--- Where the camera is along the scroll axis: 0 closest, 1 straight down.
function Camera.getZoom(): number
	return zoomU
end

local function corners(): { Vector3 }
	if tableCorners then
		return tableCorners
	end
	local T = Config.Table
	local hx = T.LengthInches / 2 + T.RailWidthInches
	local hy = T.WidthInches / 2 + T.RailWidthInches
	local list = {
		TableBuilder.toWorld(placement, -hx, -hy, T.RailHeightInches),
		TableBuilder.toWorld(placement, hx, -hy, T.RailHeightInches),
		TableBuilder.toWorld(placement, hx, hy, T.RailHeightInches),
		TableBuilder.toWorld(placement, -hx, hy, T.RailHeightInches),
	}
	tableCorners = list
	return list
end

-- True if every corner lies inside the camera's view with the configured margin.
local function fitsView(cf: CFrame, vp: Vector2): boolean
	local V = Config.Camera.View
	local tanV = math.tan(math.rad(V.FieldOfView) / 2) * (1 - V.FitMargin)
	local tanH = tanV * math.max(vp.X, 1) / math.max(vp.Y, 1)
	for _, corner in corners() do
		local p = cf:PointToObjectSpace(corner)
		local depth = -p.Z
		if depth <= 0.1 then
			return false
		end
		if math.abs(p.X) > depth * tanH or math.abs(p.Y) > depth * tanV then
			return false
		end
	end
	return true
end

-- Half-angle tangents of the view for a viewport: horizontal, vertical.
local function tangents(vp: Vector2): (number, number)
	local tanV = math.tan(math.rad(Config.Camera.View.FieldOfView) / 2)
	return tanV * math.max(vp.X, 1) / math.max(vp.Y, 1), tanV
end

-- Normalised screen position (-1..1 on both axes) of a world point, or nil if it is behind
-- the camera.
local function project(cf: CFrame, point: Vector3, tanH: number, tanV: number): Vector2?
	local p = cf:PointToObjectSpace(point)
	local depth = -p.Z
	if depth <= 0.1 then
		return nil
	end
	return Vector2.new(p.X / (depth * tanH), p.Y / (depth * tanV))
end

-- Fraction of the screen the table's outline covers (shoelace area of the projected corners).
local function fillScore(cf: CFrame, vp: Vector2): number
	local tanH, tanV = tangents(vp)
	local pts = {}
	for _, corner in corners() do
		local q = project(cf, corner, tanH, tanV)
		if q == nil then
			return 0
		end
		table.insert(pts, q)
	end
	local area = 0
	for i, a in pts do
		local b = pts[i % #pts + 1]
		area += a.X * b.Y - b.X * a.Y
	end
	return math.abs(area) / 2 / 4 -- the whole screen is 2 x 2 in normalised units
end

local function tableCentre(): Vector3
	return TableBuilder.toWorld(placement, 0, 0, 0)
end

--- Straight down over the table, table centred and FIXED: the long axis lies across the
--- screen and nothing here depends on the aim, so at the top of the zoom the table stops
--- turning underneath the camera and only the cue swings. That is what makes an overhead
--- pool view readable.
---
--- The height is solved rather than guessed: the table's own corners are measured along the
--- camera's two screen axes and the distance taken from whichever of them fills first, so
--- the framing holds on any aspect ratio.
local function topDownPose(vp: Vector2): CFrame
	local V = Config.Camera.View
	local centre = tableCentre()
	-- Screen up is the table's WIDTH direction, which puts its length across the screen.
	local up = (TableBuilder.toWorld(placement, 0, 1, 0) - centre).Unit
	local down = Vector3.new(0, -1, 0)
	-- An arbitrary height first, only to read off the camera's right and up axes.
	local axes = CFrame.lookAt(centre - down, centre, up)
	local tanH, tanV = tangents(vp)
	local maxRight, maxUp = 0, 0
	for _, corner in corners() do
		local d = corner - centre
		maxRight = math.max(maxRight, math.abs(d:Dot(axes.RightVector)))
		maxUp = math.max(maxUp, math.abs(d:Dot(axes.UpVector)))
	end
	local margin = 1 + V.FitMargin * 2
	local distance = math.max(maxRight / math.max(tanH, 1e-3), maxUp / math.max(tanV, 1e-3))
		* margin
	return CFrame.lookAt(centre + Vector3.new(0, distance, 0), centre, up)
end

--- Camera pose looking along the aim `dir` tilted down by `pitch` radians, `distance` studs
--- from the table centre. The camera then slides (never tilts, so the pitch is exactly what
--- the player sees) until the table's outline is centred on screen, and finally shifts by
--- `ballWeight` of the way from the point it looks at to the cue ball: 0 = table centred,
--- 1 = cue ball centred. Both steps are translations, so the result is always finite. Also
--- returns the point on the table the camera looks through before the ball shift.
local function poseFor(
	cueWorld: Vector3,
	dir: Vector3,
	pitch: number,
	distance: number,
	ballWeight: number,
	vp: Vector2
): (CFrame, Vector3)
	local lookDir = (dir * math.cos(pitch) - Vector3.new(0, math.sin(pitch), 0)).Unit
	local centre = tableCentre()
	local cf = CFrame.lookAt(centre - lookDir * distance, centre)
	local tanH, tanV = tangents(vp)
	local depth = distance -- the table centre stays this deep along the view; slides are sideways
	for _ = 1, 3 do
		local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
		for _, corner in corners() do
			local q = project(cf, corner, tanH, tanV)
			if q == nil then
				break
			end
			minX, maxX = math.min(minX, q.X), math.max(maxX, q.X)
			minY, maxY = math.min(minY, q.Y), math.max(maxY, q.Y)
		end
		if minX == math.huge then
			break -- a corner is beside or behind the camera: leave the pose as it is
		end
		-- Screen point that should be at the centre, kept within a few screens so a close
		-- camera cannot fling itself away.
		local wx = math.clamp((minX + maxX) / 2, -3, 3)
		local wy = math.clamp((minY + maxY) / 2, -3, 3)
		cf = cf + cf:VectorToWorldSpace(Vector3.new(wx * tanH * depth, wy * tanV * depth, 0))
	end
	-- The point on the table's plane the camera looks through, then the shift toward the ball.
	local lookPoint = cf.Position + cf.LookVector * depth
	return cf + (cueWorld - lookPoint) * ballWeight, lookPoint
end

-- Smallest distance at which the whole table is on screen from this pitch.
local function fitDistance(
	cueWorld: Vector3,
	dir: Vector3,
	pitch: number,
	ballWeight: number,
	vp: Vector2
): number
	local V = Config.Camera.View
	local lo = TableBuilder.studs(V.DistanceMinInches)
	local hi = TableBuilder.studs(V.DistanceMaxInches)
	if not fitsView((poseFor(cueWorld, dir, pitch, hi, ballWeight, vp)), vp) then
		return hi
	end
	if fitsView((poseFor(cueWorld, dir, pitch, lo, ballWeight, vp)), vp) then
		return lo
	end
	for _ = 1, 14 do
		local mid = (lo + hi) / 2
		if fitsView((poseFor(cueWorld, dir, pitch, mid, ballWeight, vp)), vp) then
			hi = mid
		else
			lo = mid
		end
	end
	return hi
end

-- Pitch and distance that show the table largest: the preferred pitch unless a steeper one
-- fills clearly more of the screen (a tall screen with the table crosswise).
local function solveFraming(
	cueWorld: Vector3,
	dir: Vector3,
	ballWeight: number,
	vp: Vector2
): (number, number)
	local V = Config.Camera.View
	local bestPitch, bestDistance, bestFill = 0, 0, -1
	local samples = math.max(V.PitchSamples, 1)
	for i = 0, samples - 1 do
		local t = if samples > 1 then i / (samples - 1) else 0
		local pitch = math.rad(V.PitchPreferred + (V.PitchMax - V.PitchPreferred) * t)
		local distance = fitDistance(cueWorld, dir, pitch, ballWeight, vp)
		local fill = fillScore((poseFor(cueWorld, dir, pitch, distance, ballWeight, vp)), vp)
		if fill > bestFill + V.PitchBias then
			bestPitch, bestDistance, bestFill = pitch, distance, fill
		end
	end
	return bestPitch, bestDistance
end

--- Target pose across the whole scroll axis: the low close view behind the cue ball at 0,
--- the angled resting framing where the low notches run out, and straight down at 1.
--- `focusOverride` (a moving cue ball) pulls the gaze.
local function viewFor(
	cueWorld: Vector3,
	dir: Vector3,
	focusOverride: Vector3?,
	viewport: Vector2?,
	zoomOverride: number?
): CFrame
	local V = Config.Camera.View
	local vp = viewport or Workspace.CurrentCamera.ViewportSize
	local u = zoomOverride or zoomU
	local _, rest = notches()
	-- Below the resting point the notches spread across the useful framings; above it they
	-- spend themselves tipping the camera over.
	local topT = math.clamp((u - rest) / math.max(1 - rest, 1e-3), 0, 1)
	-- zoomT is 1 at the closest view and 0 at the resting one. Linear in notches here means
	-- geometric in DISTANCE below, which is what makes each notch feel like the same step.
	local zoomT = 1 - math.clamp(u / math.max(rest, 1e-3), 0, 1)
	local pitch, distance = solveFraming(cueWorld, dir, V.FocusBallWeight, vp)
	-- The whole-table framing is solved once at the fitted distance; zooming then keeps its
	-- look point, shifts the centre to the cue ball and moves the camera in geometrically
	-- toward the close view along a steadily lower pitch, so the zoom is continuous.
	local _, lookPoint = poseFor(cueWorld, dir, pitch, distance, V.FocusBallWeight, vp)
	local closePitch = math.min(math.rad(V.PitchClose), pitch)
	pitch = pitch + (closePitch - pitch) * zoomT
	local ballT = math.clamp(zoomT / math.max(V.CloseBallWeightAt, 1e-3), 0, 1)
	local ballWeight = V.FocusBallWeight + (1 - V.FocusBallWeight) * ballT
	local aimPoint = lookPoint:Lerp(cueWorld, ballWeight)
	local closeDistance = math.min(TableBuilder.studs(V.CloseDistanceInches), distance)
	local zoomedDistance = distance * (closeDistance / distance) ^ zoomT
	local lookDir = (dir * math.cos(pitch) - Vector3.new(0, math.sin(pitch), 0)).Unit
	local camPos = aimPoint - lookDir * zoomedDistance
	aimPoint += dir * (TableBuilder.studs(V.CloseLookAheadInches) * zoomT)
	local cf = CFrame.lookAt(camPos, aimPoint)
	if focusOverride then
		cf =
			CFrame.lookAt(cf.Position, aimPoint:Lerp(focusOverride, Config.Camera.Shot.FocusWeight))
	end
	if topT > 0 then
		-- CFrame:Lerp slerps the rotation, so the camera swings up and over in one motion
		-- rather than tilting and turning separately - and because the overhead pose does
		-- not depend on the aim, the orbit fades out on its own as this reaches 1.
		cf = cf:Lerp(topDownPose(vp), topT)
	end
	return cf
end

--- The fitted aim pose for a cue ball position and aim angle at the current zoom, for an
--- optional viewport size (defaults to the real one). Used by the framing checks.
function Camera.viewAt(cueWorld: Vector3, angle: number, viewport: Vector2?): CFrame
	return viewFor(cueWorld, Camera.aimDirection(angle), nil, viewport)
end

--- Where the camera is right now (used to fade the avatar when it gets close).
function Camera.position(): Vector3
	return Workspace.CurrentCamera.CFrame.Position
end

--- Move the camera. `playing` freezes the anchor for the duration of the shot and, if the
--- player was zoomed in, pulls out to the whole-table view so every ball's path is visible;
--- the player's zoom comes back once the balls stop. `focus` is the cue ball's current
--- position while it moves (only used when Shot.FocusWeight > 0).
function Camera.update(
	dt: number,
	cueWorld: Vector3,
	angle: number,
	playing: boolean,
	focus: Vector3?
)
	local cam = Workspace.CurrentCamera
	local S = Config.Camera.Shot
	local dir = Camera.aimDirection(angle)
	if not playing or anchor == nil then
		anchor = cueWorld
		anchorDir = dir
	end
	if wasPlaying and not playing then
		returnTimer = S.ReturnSeconds
		-- Come back down to the resting view rather than to whatever the player had set, so
		-- every shot ends at the same angle.
		if S.ReturnToDefault then
			Camera.resetZoom()
		end
	end
	wasPlaying = playing
	returnTimer = math.max(returnTimer - dt, 0)
	-- A shot tips the camera all the way over, whatever the player was using.
	local zoomOverride = if playing and S.ZoomOut then 1 else nil
	local gaze = if playing and S.FocusWeight > 0 then focus else nil
	local target = viewFor(anchor :: Vector3, anchorDir :: Vector3, gaze, nil, zoomOverride)
	local smoothing = if playing
		then S.Smoothing
		elseif returnTimer > 0 then S.ReturnSmoothing
		else Config.Camera.View.Smoothing
	local alpha = 1 - math.exp(-dt / math.max(smoothing, 1e-3))
	if target.Position.X == target.Position.X then -- never chase a NaN pose
		cam.CFrame = cam.CFrame:Lerp(target, alpha)
	end
end

--- Snap straight to the view (used once at start so there is no swoop from the spawn).
--- Deliberately does NOT reset the zoom: sitting back down keeps the framing you last used.
function Camera.snap(cueWorld: Vector3, angle: number)
	anchor = cueWorld
	anchorDir = Camera.aimDirection(angle)
	Workspace.CurrentCamera.CFrame = viewFor(anchor :: Vector3, anchorDir :: Vector3, nil)
end

return Camera
