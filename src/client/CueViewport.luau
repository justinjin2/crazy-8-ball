--!strict
-- CueViewport: one cue turning slowly in 3D inside a ViewportFrame (the Index's detail panel;
-- designer, 2026-09-28). The stick is the game's own drawn cue (CueStickBuilder.display), made
-- thicker so it reads at a small size, tilted with its tip up and to the right like the
-- thumbnails, and turned round the upright axis, so it swings from "/" through edge-on to "\"
-- and back. A cue not found yet is its silhouette: every band one near-black colour, still lit,
-- so it reads as a 3D shape and shows nothing of the look.
--
-- The turning runs on RenderStepped only while the viewport is on screen and setSpinning(true)
-- (the Index tab showing); otherwise nothing runs. Keep the frame square (the camera is fitted
-- to a square). Tuning in Config.UI.Inventory.Viewport.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CueStickBuilder = require(Shared:WaitForChild("CueStickBuilder"))
local CueAssets = require(script.Parent:WaitForChild("CueAssets"))

local V = Config.UI.Inventory.Viewport
local LENGTH = Config.Cue.CueLengthStuds

local CueViewport = {}
CueViewport.__index = CueViewport

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- The stick's lean in the picture: its tip-to-butt direction points down and to the left, so
-- the tip is up and to the right (build's stick runs from the tip along local +Z).
local LEAN = CFrame.Angles(0, 0, math.rad(180 + V.TiltDegrees)) * CFrame.Angles(0, math.rad(90), 0)
-- From the middle of the stick back to its tip (the model's pivot).
local TO_TIP = CFrame.new(0, 0, -LENGTH / 2)

--- An empty viewport in `parent` (size and place `frame` yourself, square); show a cue with set.
function CueViewport.new(parent: Instance, name: string?): any
	local self: any = setmetatable({}, CueViewport)
	local frame = Instance.new("ViewportFrame")
	frame.Name = name or "CueViewport"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Ambient = rgb(V.Ambient)
	frame.LightColor = rgb(V.LightColor)
	frame.LightDirection =
		Vector3.new(V.LightDirection[1], V.LightDirection[2], V.LightDirection[3])
	frame.Parent = parent
	local camera = Instance.new("Camera")
	camera.FieldOfView = V.FieldOfView
	-- Far enough back that the stick's longer half-extent fills FillShare of the picture, plus
	-- its depth when it swings toward the camera.
	local tilt = math.rad(V.TiltDegrees)
	local half = LENGTH / 2 * math.max(math.sin(tilt), math.cos(tilt))
	local distance = half / (V.FillShare * math.tan(math.rad(V.FieldOfView / 2))) + half
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 0, distance), Vector3.zero)
	camera.Parent = frame
	frame.CurrentCamera = camera
	self.frame = frame
	self.camera = camera
	self.model = nil :: Model?
	self.cueId = nil :: string?
	self.silhouette = false
	self.angle = math.rad(V.StartDegrees)
	self.spinning = false
	self.connection = nil :: RBXScriptConnection?
	return self
end

-- Place the stick at the current turn.
function CueViewport.pose(self: any)
	local model: Model? = self.model
	if model then
		model:PivotTo(CFrame.Angles(0, self.angle, 0) * LEAN * TO_TIP)
	end
end

--- Show `cueId` in colour, or as its black silhouette (`silhouette`: not found yet). Nothing
--- changes when it already shows that.
function CueViewport.set(self: any, cueId: string, silhouette: boolean)
	if self.cueId == cueId and self.silhouette == silhouette and self.model then
		return
	end
	if self.model then
		self.model:Destroy()
		self.model = nil
	end
	self.cueId, self.silhouette = cueId, silhouette
	-- Built once the renderer has loaded it, so it never appears half-textured (CueAssets).
	if not silhouette and not CueAssets.ready(cueId) then
		CueAssets.whenReady(cueId, function()
			if self.cueId == cueId and self.silhouette == silhouette and self.model == nil then
				self:set(cueId, silhouette)
			end
		end)
		return
	end
	self.model = CueStickBuilder.display(
		self.frame,
		cueId,
		V.Thickness,
		if silhouette then rgb(V.SilhouetteColor) else nil
	)
	self.angle = math.rad(V.StartDegrees)
	self:pose()
end

--- Turn while `on` (and the frame is on screen); stop the loop when not.
function CueViewport.setSpinning(self: any, on: boolean)
	if self.spinning == on then
		return
	end
	self.spinning = on
	if on then
		self.connection = RunService.RenderStepped:Connect(function(dt: number)
			if not self.frame.Visible or not self.frame:IsDescendantOf(game) then
				return
			end
			self.angle = (self.angle + math.rad(V.SpinDegreesPerSecond) * dt) % (2 * math.pi)
			self:pose()
		end)
	elseif self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
end

function CueViewport.destroy(self: any)
	self:setSpinning(false)
	self.frame:Destroy()
end

return CueViewport
