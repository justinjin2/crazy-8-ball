--!strict
-- CueStickBuilder: the drawn cue, one cylinder per piece of CueShape.pieces (the same shape
-- CueClearance keeps clear of the rails and the balls). It is always its own length: the
-- shooter's body reaches it, never an extension (ShooterStance).
--
-- The model's pivot is the tip, and the stick runs along the pivot's local +Z toward the butt:
-- frame() gives that tip CFrame for a shot, and the poser is handed the same CFrame, which is
-- what keeps the hands on the cue. The pitch is VISUAL ONLY (CueClearance): the shot is always
-- fired at Config.Cue.CueElevationDegrees.
--
-- Attributes on the model: Visible (the last setVisible).

local Config = require(script.Parent.Config)
local CueShape = require(script.Parent.CueShape)

local CueStickBuilder = {}

--- The cue's radius (studs) at a distance from the tip: the clearance envelope (CueShape).
CueStickBuilder.radiusAt = CueShape.radiusAt

export type Spin = { x: number, y: number }

-- Config.Look's colour for each piece's Look, and the material it is drawn in.
local LOOKS: { [string]: { color: { number }, material: Enum.Material } } = {
	Tip = { color = Config.Look.CueTipColor, material = Enum.Material.SmoothPlastic },
	Shaft = { color = Config.Look.CueShaftColor, material = Enum.Material.Wood },
	Butt = { color = Config.Look.CueButtColor, material = Enum.Material.Wood },
}

local function color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

-- Cylinders lie along X; turned to lie along +Z, centred on their stretch of the stick.
local function along(zStart: number, length: number): CFrame
	return CFrame.new(0, 0, zStart + length / 2) * CFrame.Angles(0, math.rad(90), 0)
end

local function cylinder(
	name: string,
	length: number,
	diameter: number,
	zStart: number,
	rgb: { number },
	mat: Enum.Material,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	part.Material = mat
	part.Color = color(rgb)
	part.Size = Vector3.new(math.max(length, 1e-3), diameter, diameter)
	part.CFrame = along(zStart, length)
	part.Parent = parent
	return part
end

-- Show or hide every part for the model's Visible attribute.
local function applyVisibility(model: Model)
	local visible = model:GetAttribute("Visible") == true
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.Transparency = if visible then 0 else 1
		end
	end
end

function CueStickBuilder.build(parent: Instance): Model
	local C = Config.Cue
	local model = Instance.new("Model")
	model.Name = "CueStick"

	for _, piece in CueShape.pieces(C.CueLengthStuds) do
		local look = LOOKS[piece.look] or LOOKS.Butt
		cylinder(
			piece.name,
			piece.to - piece.from,
			piece.diameter,
			piece.from,
			look.color,
			look.material,
			model
		)
	end

	model.WorldPivot = CFrame.new(0, 0, 0)
	model:SetAttribute("Visible", true)
	model.Parent = parent
	return model
end

--- The tip's CFrame for a shot: `ballPos` is the ball centre (world), `dir` the aim direction
--- (world, flat), `gapStuds` the distance from the strike point to the tip along the cue,
--- `spin` the strike offset (ball radii) and `pitchDegrees` the drawn pitch (default the
--- physics elevation). The tip sits `gapStuds` back from where it meets the RENDERED ball, and
--- local +Z runs up the tilted cue toward the butt with no roll. A degenerate `dir` aims
--- along world -Z.
function CueStickBuilder.frame(
	ballPos: Vector3,
	dir: Vector3,
	gapStuds: number,
	spin: Spin?,
	pitchDegrees: number?
): CFrame
	local flat = Vector3.new(dir.X, 0, dir.Z)
	flat = if flat.Magnitude < 1e-6 then Vector3.new(0, 0, -1) else flat.Unit
	local s = Config.Table.StudsPerInch
	local back, right, up =
		CueShape.strikeOffset(if spin then spin.x else 0, if spin then spin.y else 0)
	local strike = ballPos
		- flat * (back * s)
		+ flat:Cross(Vector3.yAxis) * (right * s)
		+ Vector3.yAxis * (up * s)
	local theta = math.rad(pitchDegrees or Config.Cue.CueElevationDegrees)
	local axis = -flat * math.cos(theta) + Vector3.yAxis * math.sin(theta) -- tip toward butt
	local tip = strike + axis * gapStuds
	-- lookAt points local -Z at the target, so aiming it back down the axis puts +Z up it.
	return CFrame.lookAt(tip, tip - axis)
end

--- Draw the cue at a tip CFrame from frame().
function CueStickBuilder.placeAt(model: Model, tipCF: CFrame)
	model:PivotTo(tipCF)
end

--- Show or hide the stick.
function CueStickBuilder.setVisible(model: Model, visible: boolean)
	if model:GetAttribute("Visible") == visible then
		return
	end
	model:SetAttribute("Visible", visible)
	applyVisibility(model)
end

return CueStickBuilder
