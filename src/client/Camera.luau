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
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))

local Camera = {}

local locked = false
local connections: { RBXScriptConnection } = {}
local zoom = 1
local anchor: Vector3? = nil -- cue ball position the view is built around (frozen during a shot)
local anchorDir: Vector3? = nil
local returnTimer = 0 -- seconds of slower easing left after a shot ends
local wasPlaying = false

--- World-space aim direction for a physics angle.
function Camera.aimDirection(angle: number): Vector3
	-- Physics x -> world X, physics y -> world -Z.
	return Vector3.new(math.cos(angle), 0, -math.sin(angle))
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

--- Zoom by a factor (> 1 = closer). 1 = the whole table fitted, ZoomMin = close on the ball.
function Camera.zoomBy(factor: number)
	local V = Config.Camera.View
	zoom = math.clamp(zoom / factor, V.ZoomMin, V.ZoomMax)
end

--- Back to the whole-table framing (used when leaving the table).
function Camera.resetZoom()
	zoom = 1
end

function Camera.getZoom(): number
	return zoom
end

-- Outer corners of the table (rails included) at cloth height, in world space.
local tableCorners = nil :: { Vector3 }?
local function corners(): { Vector3 }
	if tableCorners then
		return tableCorners
	end
	local T = Config.Table
	local hx = T.LengthInches / 2 + T.RailWidthInches
	local hy = T.WidthInches / 2 + T.RailWidthInches
	local list = {
		TableBuilder.toWorld(-hx, -hy, T.RailHeightInches),
		TableBuilder.toWorld(hx, -hy, T.RailHeightInches),
		TableBuilder.toWorld(hx, hy, T.RailHeightInches),
		TableBuilder.toWorld(-hx, hy, T.RailHeightInches),
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
	return TableBuilder.toWorld(0, 0, 0)
end

--- Camera pose looking along the aim `dir` tilted down by `pitch` radians, `distance` studs
--- from the framing target. The camera then slides (never tilts, so the pitch is exactly
--- what the player sees) until the screen centre sits on a blend of the table's outline
--- centre and the cue ball: `ballWeight` 0 = table centred, 1 = cue ball centred.
local function poseFor(
	cueWorld: Vector3,
	dir: Vector3,
	pitch: number,
	distance: number,
	ballWeight: number,
	vp: Vector2
): CFrame
	local lookDir = (dir * math.cos(pitch) - Vector3.new(0, math.sin(pitch), 0)).Unit
	local target = tableCentre():Lerp(cueWorld, ballWeight)
	local cf = CFrame.lookAt(target - lookDir * distance, target)
	local tanH, tanV = tangents(vp)
	for _ = 1, 3 do
		local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
		for _, corner in corners() do
			local q = project(cf, corner, tanH, tanV)
			if q == nil then
				return cf
			end
			minX, maxX = math.min(minX, q.X), math.max(maxX, q.X)
			minY, maxY = math.min(minY, q.Y), math.max(maxY, q.Y)
		end
		local ball = project(cf, cueWorld, tanH, tanV)
		if ball == nil then
			return cf
		end
		-- The screen point that should be at the centre, and how deep it is.
		local want = Vector2.new((minX + maxX) / 2, (minY + maxY) / 2):Lerp(ball, ballWeight)
		local depth = -cf:PointToObjectSpace(target).Z
		local shift =
			cf:VectorToWorldSpace(Vector3.new(want.X * tanH * depth, want.Y * tanV * depth, 0))
		cf = cf + shift
	end
	return cf
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
	if not fitsView(poseFor(cueWorld, dir, pitch, hi, ballWeight, vp), vp) then
		return hi
	end
	if fitsView(poseFor(cueWorld, dir, pitch, lo, ballWeight, vp), vp) then
		return lo
	end
	for _ = 1, 14 do
		local mid = (lo + hi) / 2
		if fitsView(poseFor(cueWorld, dir, pitch, mid, ballWeight, vp), vp) then
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
		local fill = fillScore(poseFor(cueWorld, dir, pitch, distance, ballWeight, vp), vp)
		if fill > bestFill + V.PitchBias then
			bestPitch, bestDistance, bestFill = pitch, distance, fill
		end
	end
	return bestPitch, bestDistance
end

--- Target pose: the fitted whole-table framing at zoom 1; closing in on the cue ball as the
--- zoom drops toward ZoomMin. `focusOverride` (a moving cue ball) pulls the gaze.
local function viewFor(
	cueWorld: Vector3,
	dir: Vector3,
	focusOverride: Vector3?,
	viewport: Vector2?,
	zoomOverride: number?
): CFrame
	local V = Config.Camera.View
	local vp = viewport or Workspace.CurrentCamera.ViewportSize
	local z = zoomOverride or zoom
	local zoomT = 1 - math.clamp((z - V.ZoomMin) / math.max(V.ZoomMax - V.ZoomMin, 1e-3), 0, 1)
	local pitch, distance = solveFraming(cueWorld, dir, V.FocusBallWeight, vp)
	local closePitch = math.min(math.rad(V.PitchMin), pitch)
	pitch = pitch + (closePitch - pitch) * zoomT
	local ballWeight = V.FocusBallWeight + (1 - V.FocusBallWeight) * zoomT
	local cf = poseFor(cueWorld, dir, pitch, distance * z, ballWeight, vp)
	if focusOverride then
		local depth = -cf:PointToObjectSpace(tableCentre()).Z
		local lookPoint = cf.Position + cf.LookVector * depth
		cf = CFrame.lookAt(
			cf.Position,
			lookPoint:Lerp(focusOverride, Config.Camera.Shot.FocusWeight)
		)
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
	end
	wasPlaying = playing
	returnTimer = math.max(returnTimer - dt, 0)
	local zoomOverride = if playing and S.ZoomOut then Config.Camera.View.ZoomMax else nil
	local gaze = if playing and S.FocusWeight > 0 then focus else nil
	local target = viewFor(anchor :: Vector3, anchorDir :: Vector3, gaze, nil, zoomOverride)
	local smoothing = if playing
		then S.Smoothing
		elseif returnTimer > 0 then S.ReturnSmoothing
		else Config.Camera.View.Smoothing
	local alpha = 1 - math.exp(-dt / math.max(smoothing, 1e-3))
	cam.CFrame = cam.CFrame:Lerp(target, alpha)
end

--- Snap straight to the view (used once at start so there is no swoop from the spawn).
function Camera.snap(cueWorld: Vector3, angle: number)
	anchor = cueWorld
	anchorDir = Camera.aimDirection(angle)
	Workspace.CurrentCamera.CFrame = viewFor(anchor :: Vector3, anchorDir :: Vector3, nil)
end

return Camera
