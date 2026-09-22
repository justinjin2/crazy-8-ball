--!strict
-- CueStickBuilder: a placeholder cue made of three cylinders (tip, shaft, butt). The model's
-- pivot is at the tip; the stick extends along the model's local +Z, so
-- `model:PivotTo(CFrame.lookAt(tip, tip + aimDirection))` points it at the cue ball.

local Config = require(script.Parent.Config)

local CueStickBuilder = {}

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
	part.CastShadow = true
	part.Material = mat
	part.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	part.Size = Vector3.new(length, diameter, diameter)
	-- Cylinders lie along X; turn them to lie along Z, centred on their segment (studs).
	part.CFrame = CFrame.new(0, 0, zStart + length / 2) * CFrame.Angles(0, math.rad(90), 0)
	part.Parent = parent
	return part
end

function CueStickBuilder.build(parent: Instance): Model
	local C = Config.Cue
	local L = Config.Look
	local model = Instance.new("Model")
	model.Name = "CueStick"

	local tipLen = 0.06
	local shaftLen = C.CueLengthStuds * 0.55
	local buttLen = C.CueLengthStuds - shaftLen - tipLen
	local shaftDia = (C.CueTipDiameterStuds + C.CueButtDiameterStuds) / 2

	cylinder(
		"Tip",
		tipLen,
		C.CueTipDiameterStuds,
		0,
		L.CueTipColor,
		Enum.Material.SmoothPlastic,
		model
	)
	cylinder("Shaft", shaftLen, shaftDia, tipLen, L.CueShaftColor, Enum.Material.Wood, model)
	cylinder(
		"Butt",
		buttLen,
		C.CueButtDiameterStuds,
		tipLen + shaftLen,
		L.CueButtColor,
		Enum.Material.Wood,
		model
	)

	model.WorldPivot = CFrame.new(0, 0, 0)
	model.Parent = parent
	return model
end

--- Point the stick at a cue ball. `ballPos` is the ball centre (world), `dir` the aim
--- direction (world, flat), `gapStuds` the distance from the ball surface to the tip.
function CueStickBuilder.place(
	model: Model,
	ballPos: Vector3,
	dir: Vector3,
	gapStuds: number,
	spin: { x: number, y: number }?
)
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 1e-6 then
		return
	end
	flat = flat.Unit
	local radius = Config.Table.StudsPerInch * Config.Balls.RenderRadiusInches
	local sx, sy = if spin then spin.x else 0, if spin then spin.y else 0
	local depth = math.sqrt(math.max(0, 1 - sx * sx - sy * sy)) * radius
	local tip = ballPos
		- flat * (depth + gapStuds)
		+ flat:Cross(Vector3.yAxis) * (sx * radius)
		+ Vector3.yAxis * (sy * radius)
	-- lookAt points local -Z at the target ahead of the tip, so the stick (built along local
	-- +Z) trails behind the ball. A negative X rotation raises the butt.
	local cf = CFrame.lookAt(tip, tip + flat)
		* CFrame.Angles(-math.rad(Config.Cue.CueElevationDegrees), 0, 0)
	model:PivotTo(cf)
end

function CueStickBuilder.setVisible(model: Model, visible: boolean)
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			part.Transparency = if visible then 0 else 1
		end
	end
end

return CueStickBuilder
