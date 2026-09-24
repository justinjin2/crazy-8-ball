--!strict
-- BridgeBuilder: the mechanical bridge (rake) the off hand uses when a hand bridge is out of
-- reach (ShooterStance's "bridge" and "extension" modes).
--
-- It is the imported BridgeModel (assets/bridge) when the place has one, straightened from
-- its named parts, and otherwise a stand-in built from parts in the same frame. That frame is
-- Config.Bridge's: the pivot is the cue's axis resting in the High notch, +X the shooter's
-- right, +Y up and +Z from the head down the shaft toward the shooter; the shaft's axis is
-- x = 0, y = ShaftAxisYStuds.
--
-- ShooterStance decides where it goes: the notch the cue rests in, where that notch is, where
-- the off hand holds the shaft, and how much extension the shaft needs to get there. place()
-- turns the model about the notch, with no roll, so the shaft passes through the hand. The
-- extension is drawn in code past the shaft's butt with the cue extension's look
-- (Config.Cue.Extension), and the butt cap moves out to its end.
--
-- Attributes on the model: ExtensionStuds and Visible, as on the cue. Extension parts carry
-- Extension = true, and every Cap part its rest offset from the pivot (RestOffset).

local Config = require(script.Parent.Config)
local CueStickBuilder = require(script.Parent.CueStickBuilder)

local BridgeBuilder = {}

type Look = { Material: string, Color: { number } }

local function color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function material(name: string): Enum.Material
	return (Enum.Material :: any)[name]
end

-- Anchored and out of every physics and raycast query: it is only ever looked at.
local function inert(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

local function dress(part: BasePart, look: Look)
	part.Material = material(look.Material)
	part.Color = color(look.Color)
end

local function newPart(
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cf: CFrame,
	look: Look,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	inert(part)
	part.CastShadow = true
	dress(part, look)
	part.Size = size
	part.CFrame = cf
	part.Parent = parent
	return part
end

-- A cylinder on the shaft's axis from `zStart` for `length` (local frame): cylinders lie along
-- X, so they are turned to lie along +Z.
local function onAxis(zStart: number, length: number): CFrame
	return CFrame.new(0, Config.Bridge.ShaftAxisYStuds, zStart + length / 2)
		* CFrame.Angles(0, math.rad(90), 0)
end

local function shaftCylinder(
	name: string,
	zStart: number,
	length: number,
	diameter: number,
	look: Look,
	parent: Instance
): Part
	return newPart(
		name,
		Enum.PartType.Cylinder,
		Vector3.new(math.max(length, 1e-3), diameter, diameter),
		onAxis(zStart, length),
		look,
		parent
	)
end

-- Where the shaft ends and any extension starts, along +Z.
local function shaftEnd(): number
	return Config.Bridge.ShaftStartStuds + Config.Bridge.ShaftLengthStuds
end

-- The ring and the body of an extension of `E` studs: a short one is all ring.
local function extensionLayout(E: number): (number, number)
	local ring = math.min(Config.Cue.Extension.RingLengthStuds, E)
	return ring, E - ring
end

-- Show or hide every part for the model's attributes: the extension's only when there is one.
local function applyVisibility(model: Model)
	local visible = model:GetAttribute("Visible") == true
	local E = (model:GetAttribute("ExtensionStuds") :: number?) or 0
	local _, body = extensionLayout(E)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local shown = visible
			if part:GetAttribute("Extension") then
				shown = visible and E > 1e-3 and (part.Name ~= "Extension" or body > 1e-3)
			end
			part.Transparency = if shown then 0 else 1
		end
	end
end

-- The parts every bridge gets after it is built or straightened: the shaft's extension
-- (hidden, sized by setExtension), each cap's rest offset, and the attributes.
local function finish(model: Model): Model
	local X = Config.Cue.Extension
	local diameter = Config.Bridge.ShaftButtRadiusStuds * 2
	local pivot = model:GetPivot()
	local ringLook = { Material = X.RingMaterial, Color = X.RingColor }
	local ring = shaftCylinder(
		"ExtensionRing",
		shaftEnd(),
		X.RingLengthStuds,
		diameter * X.RingDiameterScale,
		ringLook,
		model
	)
	local body = shaftCylinder(
		"Extension",
		shaftEnd(),
		0,
		diameter,
		{ Material = X.Material, Color = X.Color },
		model
	)
	for _, part in { ring, body } do
		part.CFrame = pivot * part.CFrame
		part:SetAttribute("Extension", true)
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name == "Cap" then
			part:SetAttribute("RestOffset", pivot:ToObjectSpace(part.CFrame))
		end
	end
	model.Name = "Bridge"
	model:SetAttribute("ExtensionStuds", 0)
	model:SetAttribute("Visible", true)
	applyVisibility(model)
	return model
end

--- The imported model published to ReplicatedStorage.Assets by the server, if the place has
--- one. Yields up to Config.Bridge.AssetWaitSeconds for the Assets folder to arrive.
function BridgeBuilder.template(): Model?
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local assets = ReplicatedStorage:WaitForChild("Assets", Config.Bridge.AssetWaitSeconds)
	local found = assets and assets:FindFirstChild(Config.Bridge.Template)
	if found and found:IsA("Model") then
		return found
	end
	return nil
end

--- Straighten an imported BridgeModel in place and dress it. The importer turns the model half
--- a turn and centres each MeshPart on its own bounding box, so the frame is rebuilt from
--- where the named parts ARE: the shaft lies level along +Z from the head, and the head's box
--- centre is Config.Bridge.HeadCentre from the pivot. False (with a warning) when the model
--- cannot be straightened; build() then falls back to parts.
function BridgeBuilder.normalize(model: Model): boolean
	local head = model:FindFirstChild("Head", true)
	local shaft = model:FindFirstChild("Shaft", true)
	if not (head and head:IsA("BasePart") and shaft and shaft:IsA("BasePart")) then
		warn(
			("[8ball] %s has no Head or Shaft part: the bridge uses the parts fallback"):format(
				model.Name
			)
		)
		return false
	end
	-- Level to within a few degrees (the head's box centre sits 0.03 above the shaft's axis,
	-- 3 studs away, so the true line dips by about half a degree).
	local along = shaft.Position - head.Position
	local flat = Vector3.new(along.X, 0, along.Z)
	if along.Magnitude < 1e-3 or math.abs(along.Unit.Y) > 0.1 then
		warn(
			"[8ball] "
				.. model.Name
				.. "'s shaft does not lie level (it looks stood up or tilted): import it "
				.. "again without rotating it (assets/bridge/Readme.md). The bridge uses the "
				.. "parts fallback"
		)
		return false
	end

	-- The importer's own looks go; Config.Bridge.Meshes dresses the parts instead.
	local meshes = Config.Bridge.Meshes
	for _, item in model:GetDescendants() do
		if item:IsA("SurfaceAppearance") then
			item:Destroy()
		elseif item:IsA("BasePart") then
			inert(item)
			local look = meshes[item.Name]
			if look then
				dress(item, look)
			end
			if item:IsA("MeshPart") then
				item.TextureID = ""
			end
		end
	end

	-- A PrimaryPart would override WorldPivot.
	local c = Config.Bridge.HeadCentre
	model.PrimaryPart = nil
	model.WorldPivot = CFrame.new(head.Position)
		* CFrame.lookAt(Vector3.zero, -flat)
		* CFrame.new(-c[1], -c[2], -c[3])
	return true
end

--- The stand-in bridge, built from parts straight in Config.Bridge's frame (pivot at the
--- origin): a plate of blocks with square notches whose rest points are the Notches, and
--- cylinders for the collar, the shaft, its ring and the cap (Config.Bridge.Fallback).
function BridgeBuilder.buildFromParts(parent: Instance?): Model
	local B, F = Config.Bridge, Config.Bridge.Fallback
	local model = Instance.new("Model")
	local looks = B.Meshes
	local count = 0
	local r, t = F.NotchRadiusStuds, F.HeadThicknessStuds
	local function block(x0: number, x1: number, y0: number, y1: number)
		if x1 - x0 <= 1e-4 or y1 - y0 <= 1e-4 then
			return
		end
		count += 1
		newPart(
			if count == 1 then "Head" else "Head" .. count,
			Enum.PartType.Block,
			Vector3.new(x1 - x0, y1 - y0, t),
			CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, 0),
			looks.Head,
			model
		)
	end
	-- The plate, right to left: the notches in order of X from the shooter's right; each
	-- notch's floor is its rest point less NotchRestAboveBottom, its outer wall NotchDepth
	-- above that; a lobe between two notches stands as tall as the higher one's wall, and the
	-- left lobe LobeCrown taller than the last. Everything stands on a base as high as the
	-- lowest floor.
	local notches = table.clone(B.Notches)
	table.sort(notches, function(a, b)
		return a.X > b.X
	end)
	local half = B.HeadWidthStuds / 2
	local function floorOf(i: number): number
		return notches[i].Y - F.NotchRestAboveBottomStuds
	end
	local baseTop = math.huge
	for i in notches do
		baseTop = math.min(baseTop, floorOf(i))
	end
	block(-half, half, -B.PivotHeightStuds, baseTop)
	local right, lastWall = half, -math.huge
	for i, notch in notches do
		local wall = floorOf(i) + F.NotchDepthStuds
		block(notch.X + r, right, baseTop, math.max(wall, lastWall)) -- the shoulder, or a lobe
		block(notch.X - r, notch.X + r, baseTop, floorOf(i)) -- under the notch
		right, lastWall = notch.X - r, wall
	end
	block(-half, right, baseTop, lastWall + F.LobeCrownStuds)

	-- The collar holding the plate, the shaft in two tapering halves, its ring and the cap.
	local head, butt = F.ShaftHeadDiameterStuds, B.ShaftButtRadiusStuds * 2
	local function across(fraction: number): number -- the shaft's diameter along it
		return head + (butt - head) * fraction
	end
	local halfLength = B.ShaftLengthStuds / 2
	shaftCylinder(
		"Ferrule",
		F.CollarFromStuds,
		F.CollarToStuds - F.CollarFromStuds,
		F.CollarDiameterStuds,
		looks.Ferrule,
		model
	)
	shaftCylinder("Shaft", B.ShaftStartStuds, halfLength, across(0.25), looks.Shaft, model)
	shaftCylinder(
		"Shaft2",
		B.ShaftStartStuds + halfLength,
		halfLength,
		across(0.75),
		looks.Shaft,
		model
	)
	shaftCylinder(
		"FerruleRing",
		B.ShaftStartStuds + B.ShaftLengthStuds * F.RingPosition - F.RingLengthStuds / 2,
		F.RingLengthStuds,
		across(F.RingPosition) + F.RingExtraDiameterStuds,
		looks.Ferrule,
		model
	)
	shaftCylinder(
		"Cap",
		F.CapFromStuds,
		F.CapToStuds - F.CapFromStuds,
		F.CapDiameterStuds,
		looks.Cap,
		model
	)

	model.WorldPivot = CFrame.new()
	finish(model)
	model.Parent = parent
	return model
end

--- A bridge for one shooter: the imported model when there is one (`templateOverride` lets an
--- Edit-mode preview pass ServerStorage.BridgeModel), else the parts stand-in. May yield (see
--- template()); build them up front.
function BridgeBuilder.build(parent: Instance, templateOverride: Model?): Model
	local template = templateOverride or BridgeBuilder.template()
	if template then
		local model = template:Clone()
		if BridgeBuilder.normalize(model) then
			finish(model)
			model.Parent = parent
			return model
		end
		model:Destroy()
	end
	return BridgeBuilder.buildFromParts(parent)
end

--- Draw the shaft's extension, `studs` rounded up to whole Config.Cue.Extension steps (none
--- when nil): a ring at the shaft's butt, then the body, with the cap moved out to its end.
--- The parts are only touched when the rounded length changes. Keeps the model where it is.
function BridgeBuilder.setExtension(model: Model, studs: number?)
	local E = CueStickBuilder.quantizeExtension(studs)
	local was = (model:GetAttribute("ExtensionStuds") :: number?) or 0
	if math.abs(E - was) <= 1e-3 then
		return
	end
	model:SetAttribute("ExtensionStuds", E)
	local pivot = model:GetPivot()
	local ring, body = extensionLayout(E)
	local z0 = shaftEnd()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local rest = part:GetAttribute("RestOffset")
			if part.Name == "ExtensionRing" then
				part.Size = Vector3.new(math.max(ring, 1e-3), part.Size.Y, part.Size.Z)
				part.CFrame = pivot * onAxis(z0, ring)
			elseif part.Name == "Extension" then
				part.Size = Vector3.new(math.max(body, 1e-3), part.Size.Y, part.Size.Z)
				part.CFrame = pivot * onAxis(z0 + ring, body)
			elseif typeof(rest) == "CFrame" then
				part.CFrame = pivot * CFrame.new(0, 0, E) * rest
			end
		end
	end
	applyVisibility(model)
end

-- The bridge's axes for a shaft running along `u` (+Z): +X level (no roll), +Y up and over.
local function axesFor(u: Vector3): (Vector3, Vector3)
	local right = -u:Cross(Vector3.yAxis) -- up x u: the shooter's right, looking down -u
	right = if right.Magnitude < 1e-6 then Vector3.xAxis else right.Unit
	return right, u:Cross(right)
end

--- Stand the bridge so the cue's rest point in `notchName` is exactly at `head` (world) and the
--- shaft's axis passes through `hold` (world, where the off hand holds it), turned about the
--- notch with the plate upright and no roll, with `extensionStuds` of extension (none when
--- nil). Both points come from ShooterStance's rake, turned into world space by the caller.
--- Returns the hand's grip on the shaft: on the shaft's axis at `hold`, +Z down the shaft
--- away from the head (the model's own axes). An unknown notch name rests on the pivot, the
--- High notch.
function BridgeBuilder.place(
	model: Model,
	head: Vector3,
	hold: Vector3,
	notchName: string,
	extensionStuds: number?
): CFrame
	local B = Config.Bridge
	local nx, ny = 0, 0
	for _, notch in B.Notches do
		if notch.Name == notchName then
			nx, ny = notch.X, notch.Y
		end
	end
	-- The shaft starts beside the notch, so turning the model to aim it at the hand moves its
	-- start a little: aim from where the start is, recompute, until it settles.
	local u = hold - head
	u = if u.Magnitude < 1e-6 then Vector3.zAxis else u.Unit
	local right, up = axesFor(u)
	for _ = 1, 8 do
		local start = head - right * nx + up * (B.ShaftAxisYStuds - ny)
		local v = hold - start
		if v.Magnitude < 1e-6 then
			break
		end
		local settled = (v.Unit - u).Magnitude < 1e-9
		u = v.Unit
		right, up = axesFor(u)
		if settled then
			break
		end
	end
	local pivot = CFrame.fromMatrix(head - right * nx - up * ny, right, up, u)
	model:PivotTo(pivot)
	BridgeBuilder.setExtension(model, extensionStuds)
	local start = pivot.Position + up * B.ShaftAxisYStuds
	return CFrame.fromMatrix(start + u * (hold - start):Dot(u), right, up, u)
end

--- Show or hide the bridge. The extension shows only while it has a length.
function BridgeBuilder.setVisible(model: Model, visible: boolean)
	if model:GetAttribute("Visible") == visible then
		return
	end
	model:SetAttribute("Visible", visible)
	applyVisibility(model)
end

return BridgeBuilder
