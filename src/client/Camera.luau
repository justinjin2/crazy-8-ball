--!strict
-- Camera: the single aim view. The camera orbits a focus point inside the table, on the
-- side opposite the aim, so it always looks across the table along the aim. Every frame it
-- solves for the closest distance (and shallowest pitch) that keeps the whole table on
-- screen for the current viewport, so the table is always fully visible at the tightest
-- framing the screen allows. Zooming in closes on the cue ball. While a shot plays it holds
-- its position and lets its gaze drift toward the cue ball.
--
-- Every turn starts in the HOME VIEW (Config.Camera.View.ZoomDefault, the pre-multiplayer
-- framing, untouched by the match HUD), and the camera always comes back to it: after every
-- shot and after the pocket call. The one exception is calling a pocket for the 8, which
-- looks straight down on the whole table (setMode) so every pocket can be picked.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Cue = require(Shared:WaitForChild("Physics"):WaitForChild("Cue"))
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
local topDown = false
local hudTop = 0
local hudBottom = Config.Multiplayer.CameraBottomFraction
local transitionFrom: CFrame? = nil
local transitionTime = 0
local savedCamera: any = nil

local zoom = Config.Camera.View.ZoomDefault
local homeZoom = Config.Camera.View.ZoomDefault -- this turn's starting zoom (setBallInHand)
-- The pose the smoothing chases, kept apart from what the camera actually shows. The shake
-- is added on top of this, never folded into it: lerping from an already-shaken pose would
-- smear the shake into the smoothing and let it drift.
local smoothed: CFrame? = nil
-- A pocket nudge in flight: which way, how hard, and how far through it is.
local shakeDir = Vector3.zero
local shakeScale = 0
local shakeTime = 0
local anchor: Vector3? = nil -- cue ball the view is built around (frozen: a shot, a hold)
local anchorDir: Vector3? = nil
local returnTimer = 0 -- seconds of slower easing left after a shot ends
local wasPlaying = false
-- Seconds since the balls started moving, which is what the camera's hold and pull-out are
-- timed off. Reset the moment a shot is not playing, so every shot gets the full hold.
local shotTime = 0
-- When the pull-out began, in shotTime seconds, or nil while the camera is still holding.
-- Recorded rather than recomputed because the hold can END EARLY when a ball leaves the
-- screen: starting the move from the moment it was triggered is what keeps it continuous.
-- Deriving it from HoldSeconds instead would jump the target part-way through the curve.
local pullOutStart: number? = nil
-- Whether this shot is big enough to be worth leaving the close view for at all. Decided once
-- at the strike from the cue ball's speed; a ball reaching the screen edge overrides it.
local pullOutWanted = true

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

-- The hand-back to the player's own camera (see Camera.unlock). Roblox's camera script runs
-- at RenderPriority.Camera and builds each frame from the camera's current CFrame, so the
-- blend restores ITS last pose just before it runs and blends just after: the default camera
-- keeps its own continuity, and what is shown slides from the table view into it.
local RELEASE_BEFORE = "PoolCameraReleaseRestore"
local RELEASE_AFTER = "PoolCameraReleaseBlend"
local releasing = false

local function stopRelease()
	if releasing then
		releasing = false
		RunService:UnbindFromRenderStep(RELEASE_BEFORE)
		RunService:UnbindFromRenderStep(RELEASE_AFTER)
	end
end

local function startRelease(from: CFrame)
	stopRelease()
	releasing = true
	local elapsed = 0
	local own: CFrame? = nil -- the default camera's own pose, before the blend is applied
	RunService:BindToRenderStep(RELEASE_BEFORE, Enum.RenderPriority.Camera.Value - 1, function()
		if own then
			Workspace.CurrentCamera.CFrame = own
		end
	end)
	RunService:BindToRenderStep(RELEASE_AFTER, Enum.RenderPriority.Camera.Value + 1, function(dt)
		local cam = Workspace.CurrentCamera
		own = cam.CFrame
		elapsed += dt
		local t = math.clamp(elapsed / Config.Multiplayer.CameraReleaseSeconds, 0, 1)
		cam.CFrame = from:Lerp(own :: CFrame, t * t * (3 - 2 * t))
		if t >= 1 then
			stopRelease()
		end
	end)
end

local function takeOver()
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = Config.Camera.View.FieldOfView
end

--- Take control of the camera (and keep it even when Roblox's default scripts reset it
--- on spawn). It eases from wherever the player's own camera was into the home view, or
--- into the top-down view when the turn opens with a pocket call owed for the 8 (setMode).
function Camera.lock()
	if locked then
		return
	end
	locked = true
	stopRelease()
	local cam = Workspace.CurrentCamera
	savedCamera = { kind = cam.CameraType, fov = cam.FieldOfView, subject = cam.CameraSubject }
	transitionFrom = cam.CFrame
	transitionTime = 0
	Camera.resetZoom()
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

--- Hand the camera back to Roblox's default character camera, easing from the table view
--- into it over Multiplayer.CameraReleaseSeconds rather than cutting.
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
	smoothed = nil
	shakeScale = 0
	returnTimer = 0
	wasPlaying = false
	shotTime = 0
	pullOutStart = nil
	pullOutWanted = true
	local cam = Workspace.CurrentCamera
	local from = cam.CFrame
	cam.CameraType = if savedCamera then savedCamera.kind else Enum.CameraType.Custom
	if savedCamera then
		cam.FieldOfView = savedCamera.fov
		if savedCamera.subject and savedCamera.subject.Parent then
			cam.CameraSubject = savedCamera.subject
		end
	end
	savedCamera = nil
	transitionFrom = nil
	topDown = false
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		startRelease(from)
	end
end

function Camera.isLocked(): boolean
	return locked
end

--- Nudge the camera toward a point: a ball has just dropped there.
---
--- `speed` is how hard it went in, which decides how much of the (already tiny) nudge is
--- used. Horizontal only - a camera that bobs vertically is far more nauseating than one
--- that slides - and it simply restarts if a second ball drops mid-nudge, so a two-ball
--- pocket is one nudge rather than two fighting each other.
function Camera.kick(towards: Vector3, speed: number)
	local K = Config.Camera.Shake
	if not K.Enabled or not locked then
		return
	end
	local flat = Vector3.new(
		towards.X - Workspace.CurrentCamera.CFrame.Position.X,
		0,
		towards.Z - Workspace.CurrentCamera.CFrame.Position.Z
	)
	if flat.Magnitude < 1e-3 then
		return
	end
	local k = math.clamp((speed - K.QuietSpeed) / math.max(K.LoudSpeed - K.QuietSpeed, 1e-3), 0, 1)
	shakeDir = flat.Unit
	shakeScale = K.MinScale + (1 - K.MinScale) * k
	shakeTime = 0
end

-- Where the shake has got to. Decays to nothing and stays there.
local function shakeOffset(dt: number): Vector3
	local K = Config.Camera.Shake
	if shakeScale <= 0 then
		return Vector3.zero
	end
	shakeTime += dt
	local phase = shakeTime / math.max(K.Seconds, 1e-3)
	if phase >= 1 then
		shakeScale = 0
		return Vector3.zero
	end
	-- Starts at full offset and swings back while fading out, so the jolt is at the moment
	-- the ball drops rather than a quarter of a second later.
	local decay = (1 - phase) * (1 - phase)
	local swing = math.cos(phase * K.Oscillations * 2 * math.pi)
	return shakeDir * (K.AmplitudeStuds * shakeScale * decay * swing)
end

--- Zoom by a factor (> 1 = closer). 1 = the whole table fitted, ZoomMin = close on the ball.
function Camera.zoomBy(factor: number)
	local V = Config.Camera.View
	zoom = math.clamp(zoom / factor, V.ZoomMin, V.ZoomMax)
end

--- Back to the home view - at every turn start, after every shot, after the 8-ball pocket
--- call, and whenever the camera is taken - so a pinch made for one shot does not quietly
--- become the setting for the match.
function Camera.resetZoom()
	zoom = homeZoom
end

--- Where resetZoom goes for the turn now starting: the home view, or - when the turn opens
--- with the cue ball in hand (the break, a foul) - View.BallInHandZoomNotches wheel notches
--- further out, so there is room to see where to put the ball.
function Camera.setBallInHand(inHand: boolean)
	local V = Config.Camera.View
	homeZoom = if inHand
		then math.min(V.ZoomDefault * Config.Input.ZoomStep ^ V.BallInHandZoomNotches, V.ZoomMax)
		else V.ZoomDefault
end

function Camera.getZoom(): number
	return zoom
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

-- True when a world point has left the view, with a margin so the answer comes a moment
-- before it truly goes. A point behind the camera counts as gone. The top edge is the
-- bottom of the match header (setMode), not the screen's: on a phone the header covers a
-- deep band of the top, which is exactly where the aimed-along home view sends the object
-- ball. The bottom controls are not full-width, so the bottom edge stays the screen's.
local function offScreen(cf: CFrame, point: Vector3, vp: Vector2): boolean
	local tanH, tanV = tangents(vp)
	local q = project(cf, point, tanH, tanV)
	if q == nil then
		return true
	end
	local edge = 1 - Config.Camera.Shot.OffScreenMargin
	return math.abs(q.X) > edge or q.Y > edge - 2 * hudTop or q.Y < -edge
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

--- Target pose: the fitted whole-table framing at zoom 1, down to the low close view
--- behind the cue ball at ZoomMin. `focusOverride` (a moving cue ball) pulls the gaze.
--- Also returns the whole-table pose (zoom 1, no gaze) from the same solve, so the HUD fit
--- does not have to solve the framing a second time every frame.
local function viewFor(
	cueWorld: Vector3,
	dir: Vector3,
	focusOverride: Vector3?,
	viewport: Vector2?,
	zoomOverride: number?
): (CFrame, CFrame)
	local V = Config.Camera.View
	local vp = viewport or Workspace.CurrentCamera.ViewportSize
	local z = zoomOverride or zoom
	local zoomT = 1 - math.clamp((z - V.ZoomMin) / math.max(V.ZoomMax - V.ZoomMin, 1e-3), 0, 1)
	local pitch, distance = solveFraming(cueWorld, dir, V.FocusBallWeight, vp)
	-- The whole-table framing is solved once at the fitted distance; zooming then keeps its
	-- look point, shifts the centre to the cue ball and moves the camera in geometrically
	-- toward the close view along a steadily lower pitch, so the zoom is continuous.
	local _, lookPoint = poseFor(cueWorld, dir, pitch, distance, V.FocusBallWeight, vp)
	-- What the lines below give at zoomT = 0 (fully zoomed out) without a gaze: the pitch,
	-- ball weight and distance are left exactly as solved and there is no look-ahead.
	local wholeDir = (dir * math.cos(pitch) - Vector3.new(0, math.sin(pitch), 0)).Unit
	local wholeAim = lookPoint:Lerp(cueWorld, V.FocusBallWeight)
	local whole = CFrame.lookAt(wholeAim - wholeDir * distance, wholeAim)
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
	return cf, whole
end

--- `overhead` is the top-down view, used only while a pocket is being called for the 8.
--- `headerPixels` and `bottomPixels` are how much of the screen the match HUD covers above
--- and below; the top-down view and the whole-table end of the zoom keep the table clear of
--- them, and a ball rolling under the header counts as off screen for the shot's pull-out.
function Camera.setMode(overhead: boolean, headerPixels: number, bottomPixels: number?)
	local vp = Workspace.CurrentCamera.ViewportSize
	local reserved =
		math.clamp(headerPixels / math.max(vp.Y, 1), 0, Config.Multiplayer.CameraMaxHudFraction)
	if topDown ~= overhead then
		transitionFrom = Workspace.CurrentCamera.CFrame
		transitionTime = 0
		smoothed = nil
		if not overhead then
			Camera.resetZoom() -- pocket called or timed out: back to the home view
		end
	end
	topDown, hudTop = overhead, reserved
	hudBottom =
		math.max(Config.Multiplayer.CameraBottomFraction, (bottomPixels or 0) / math.max(vp.Y, 1))
end

local function overheadView(): CFrame
	local vp = Workspace.CurrentCamera.ViewportSize
	local tanV = math.tan(math.rad(Config.Camera.View.FieldOfView) / 2)
	local tanH = tanV * math.max(vp.X, 1) / math.max(vp.Y, 1)
	local M = Config.Multiplayer
	local halfX = TableBuilder.studs(Config.Table.LengthInches / 2 + Config.Table.RailWidthInches)
	local halfY = TableBuilder.studs(Config.Table.WidthInches / 2 + Config.Table.RailWidthInches)
	local distance = math.max(
		halfX / (tanH * (1 - 2 * M.CameraSideFraction)),
		halfY / (tanV * math.max(0.2, 1 - hudTop - hudBottom))
	)
	local up = TableBuilder.aimDirection(placement, math.pi / 2)
	local target = tableCentre() + up * distance * tanV * (hudTop - hudBottom)
	return CFrame.lookAt(target + Vector3.new(0, distance, 0), target, up)
end

-- The whole-table pose `cf` moved back and up until every corner clears the match HUD and
-- the side margins. Only ever applied to the fully zoomed-out pose; see hudWeight.
local function hudFit(cf: CFrame): CFrame
	if hudTop <= 0 then
		return cf
	end
	local vp = Workspace.CurrentCamera.ViewportSize
	local M = Config.Multiplayer
	local tanV = math.tan(math.rad(Config.Camera.View.FieldOfView) / 2)
	local tanH = tanV * vp.X / math.max(vp.Y, 1)
	local originalDistance = (cf.Position - tableCentre()).Magnitude
	local distance = originalDistance
	local result = cf
	for _ = 1, M.CameraFitIterations do
		result = cf
			- cf.LookVector * (distance - originalDistance)
			+ cf.UpVector * distance * tanV * math.max(0, hudTop - hudBottom)
		local fits = true
		for _, point in corners() do
			local p = result:PointToObjectSpace(point)
			local depth = -p.Z
			local y = if depth > 0 then p.Y / (depth * tanV) else math.huge
			if
				depth <= 0
				or math.abs(p.X) > depth * tanH * (1 - 2 * M.CameraSideFraction)
				or y > 1 - 2 * hudTop
				or y < -1 + 2 * hudBottom
			then
				fits = false
				break
			end
		end
		if fits then
			return result
		end
		distance *= M.CameraFitGrowth
	end
	return result
end

-- How much of the HUD fit applies at zoom `z`: none at the home view or closer (the
-- pre-multiplayer framing, untouched), all of it at ZoomMax, linear between, so the pull-out
-- lands on the HUD-fitted pose without a pop.
local function hudWeight(z: number): number
	local V = Config.Camera.View
	return math.clamp((z - V.ZoomDefault) / math.max(V.ZoomMax - V.ZoomDefault, 1e-3), 0, 1)
end

--- The fitted aim pose for a cue ball position and aim angle at the current zoom (or at
--- `zoomOverride`), for an optional viewport size (defaults to the real one). Without the
--- HUD fit, which is nothing at the home view or closer. Used by the framing checks.
function Camera.viewAt(
	cueWorld: Vector3,
	angle: number,
	viewport: Vector2?,
	zoomOverride: number?
): CFrame
	return (viewFor(cueWorld, Camera.aimDirection(angle), nil, viewport, zoomOverride))
end

--- Where the camera is right now (used to fade the avatar when it gets close).
function Camera.position(): Vector3
	return Workspace.CurrentCamera.CFrame.Position
end

--- Move the camera. `playing` means the shot's replay is running: it freezes the anchor for
--- the duration of the shot, holds the framing the shot was taken from for
--- Shot.HoldSeconds, then pulls out to the whole-table view so every ball's path is visible.
--- When the balls stop it eases back to the home view (View.ZoomDefault) - the framing every
--- turn starts from, not whatever the player had pinched to. `focus` is the cue ball's
--- current position while it moves (only used when Shot.FocusWeight > 0). `moving` is every
--- ball currently in motion, in world space: the hold ends the moment one of them is about
--- to leave the screen. `hold` freezes the anchor too, without the shot's pull-out: while
--- the cue ball is being dragged (so the view does not chase the finger) and while it sits
--- in a pocket (so the view does not drift toward the pocket). When it lets go the view
--- eases to wherever the ball now is.
function Camera.update(
	dt: number,
	cueWorld: Vector3,
	angle: number,
	playing: boolean,
	focus: Vector3?,
	moving: { Vector3 }?,
	hold: boolean?
)
	local cam = Workspace.CurrentCamera
	local S = Config.Camera.Shot
	local dir = Camera.aimDirection(angle)
	if (not playing and not hold) or anchor == nil then
		anchor = cueWorld
		anchorDir = dir
	end
	if wasPlaying and not playing then
		returnTimer = S.ReturnSeconds
		-- Every turn starts from the same framing, whatever the player pinched to for the
		-- shot they just took.
		Camera.resetZoom()
	end
	wasPlaying = playing
	if playing then
		shotTime += dt
	else
		shotTime = 0
		pullOutStart = nil
	end
	returnTimer = math.max(returnTimer - dt, 0)

	-- The pull-out to the whole table. It does NOT begin at the strike: the camera holds the
	-- framing the shot was taken from while the cue ball travels, and only then leaves.
	--
	-- Two things can end that hold, and whichever comes first wins. Normally it is
	-- HoldSeconds. But a ball on its way off the screen ends it at once, because there is no
	-- point holding a framing that no longer contains the shot - a bank across the table can
	-- put the object ball out of view well inside the hold.
	local zoomOverride: number? = nil
	if playing and S.ZoomOut then
		if pullOutStart == nil then
			local gone = false
			if moving then
				local pose = smoothed or cam.CFrame
				local vp = cam.ViewportSize
				for _, ball in moving do
					if offScreen(pose, ball, vp) then
						gone = true
						break
					end
				end
			end
			-- A ball heading off screen always wins: wherever the shot has gone, the camera
			-- has to follow it. The timer only ever applies to a shot big enough to be worth
			-- leaving for in the first place.
			if gone or (pullOutWanted and shotTime >= S.HoldSeconds) then
				pullOutStart = shotTime
			end
		end
		if pullOutStart then
			local t = math.clamp((shotTime - pullOutStart) / math.max(S.PullOutSeconds, 1e-3), 0, 1)
			local eased = t * t * (3 - 2 * t)
			zoomOverride = zoom + (Config.Camera.View.ZoomMax - zoom) * eased
		end
	end
	local gaze = if playing and S.FocusWeight > 0 then focus else nil
	local target: CFrame
	if topDown then
		target = overheadView()
	else
		local view, whole =
			viewFor(anchor :: Vector3, anchorDir :: Vector3, gaze, nil, zoomOverride)
		-- The HUD fit is worked out on the whole-table pose and only its OFFSET is carried
		-- over, scaled by the weight. Fitting the zoomed pose itself would jump by a whole
		-- retreat step each time a corner crossed the HUD edge on the way out.
		local w = hudWeight(zoomOverride or zoom)
		target = if w > 0 then view + (hudFit(whole).Position - whole.Position) * w else view
	end
	local smoothing = if playing
		then S.Smoothing
		elseif returnTimer > 0 then S.ReturnSmoothing
		else Config.Camera.View.Smoothing
	local alpha = 1 - math.exp(-dt / math.max(smoothing, 1e-3))
	if target.Position.X == target.Position.X then -- never chase a NaN pose
		local base = (smoothed or cam.CFrame):Lerp(target, alpha)
		if transitionFrom then
			transitionTime += dt
			local t = math.clamp(transitionTime / Config.Multiplayer.CameraTransitionSeconds, 0, 1)
			base = transitionFrom:Lerp(target, t * t * (3 - 2 * t))
			if t >= 1 then
				transitionFrom = nil
			end
		end
		smoothed = base
		cam.CFrame = base + shakeOffset(dt)
	end
end

--- A shot has just started. `cueSpeed` is how fast the cue ball left, which decides whether
--- the camera bothers leaving the close view at all: a tap that cannot cross half the table
--- has nothing to show at the far end. See Config.Camera.Shot.MinTravelTableLengths.
--- wx/wy are angular velocity in the frame whose +x follows the current ball velocity.
function Camera.beginShot(cueSpeed: number, wx: number?, wy: number?)
	local S = Config.Camera.Shot
	local reach = Cue.rollOutDistance(cueSpeed, wx, wy)
	pullOutWanted = reach >= S.MinTravelTableLengths * Config.Table.LengthInches
end

--- Snap straight to the view (used once at start so there is no swoop from the spawn).
function Camera.snap(cueWorld: Vector3, angle: number)
	anchor = cueWorld
	anchorDir = Camera.aimDirection(angle)
	local pose = (viewFor(anchor :: Vector3, anchorDir :: Vector3, nil))
	smoothed = pose
	shakeScale = 0
	Workspace.CurrentCamera.CFrame = pose
end

return Camera
