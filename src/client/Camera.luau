--!strict
-- Camera: the single aim view. Elevated and behind the shooter, looking down the aim line
-- so the table lays out ahead; it turns with the aim and eases to new positions. While a
-- shot plays it holds its position and lets its gaze drift toward the cue ball.

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
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = 70
end

function Camera.isLocked(): boolean
	return locked
end

--- Zoom by a factor (> 1 = closer). Clamped in update() against the whole-table scale.
function Camera.zoomBy(factor: number)
	local V = Config.Camera.View
	zoom = math.clamp(zoom / factor, V.ZoomMin, V.ZoomMax)
end

--- Back to the default framing (used when leaving the table).
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

--- Camera pose for the view built around `cueWorld` looking along `dir`, scaled back
--- by `k` (1 = the configured distances).
local function poseAt(cueWorld: Vector3, dir: Vector3, k: number, focus: Vector3?): CFrame
	local V = Config.Camera.View
	local right = dir:Cross(Vector3.yAxis)
	local pos = cueWorld
		- dir * (TableBuilder.studs(V.BehindInches) * k)
		+ right * TableBuilder.studs(V.SideInches)
		+ Vector3.new(0, TableBuilder.studs(V.HeightInches) * k, 0)
	local look = cueWorld + dir * (TableBuilder.studs(V.LookAheadInches) * k)
	if focus then
		look = look:Lerp(focus, Config.Camera.Shot.FocusWeight)
	end
	return CFrame.lookAt(pos, look)
end

--- Smallest scale at which the whole table is on screen (1 if it already fits).
local function wholeTableScale(cueWorld: Vector3, dir: Vector3): number
	local V = Config.Camera.View
	local vp = Workspace.CurrentCamera.ViewportSize
	if fitsView(poseAt(cueWorld, dir, 1, nil), vp) then
		return 1
	end
	local lo, hi = 1, V.ZoomMaxScale
	for _ = 1, 14 do
		local mid = (lo + hi) / 2
		if fitsView(poseAt(cueWorld, dir, mid, nil), vp) then
			hi = mid
		else
			lo = mid
		end
	end
	return hi
end

--- Target pose for the view: the configured framing at the current zoom, never further
--- out than the scale at which the whole table is on screen.
local function viewFor(cueWorld: Vector3, dir: Vector3, focus: Vector3?): CFrame
	local V = Config.Camera.View
	local maxScale = math.min(wholeTableScale(cueWorld, dir), V.ZoomMax)
	local k = math.clamp(zoom, V.ZoomMin, math.max(maxScale, V.ZoomMin))
	return poseAt(cueWorld, dir, k, focus)
end

--- Move the camera. `playing` freezes the anchor for the duration of the shot; `focus` is
--- the cue ball's current position while it moves.
function Camera.update(
	dt: number,
	cueWorld: Vector3,
	angle: number,
	playing: boolean,
	focus: Vector3?
)
	local cam = Workspace.CurrentCamera
	local dir = Camera.aimDirection(angle)
	if not playing or anchor == nil then
		anchor = cueWorld
		anchorDir = dir
	end
	local target = viewFor(anchor :: Vector3, anchorDir :: Vector3, if playing then focus else nil)
	local smoothing = if playing then Config.Camera.Shot.Smoothing else Config.Camera.View.Smoothing
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
