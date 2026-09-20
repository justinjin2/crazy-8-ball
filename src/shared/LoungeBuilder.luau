--!strict
-- LoungeBuilder: turns the six imported lounge FBX packages into a working room.
--
-- The import itself is a click job (meshes are plugin-only), but everything after it is
-- scripted and re-runnable, because the lounge in the place today is a placeholder that
-- will be replaced. When a new build of the package is imported, run `LoungeBuilder.setUp`
-- again from Studio's command bar and the whole pass repeats from Config.
--
-- Two of these steps write properties that only a plugin or Studio itself may set
-- (CollisionFidelity) and one uploads nothing but must still happen in Edit mode and be
-- saved into the place, so this is not called at run time. Bootstrap only checks the work
-- was done.
--
--   LoungeBuilder.correctImport(parent)  -- undo Studio's 180 degree import rotation
--   LoungeBuilder.applyPackages(lounge)  -- materials, collision, shadows, render fidelity
--   LoungeBuilder.buildPendants(lounge)  -- the twelve non-shadow lights over the tables
--   LoungeBuilder.applyLighting()        -- the package's lighting recipe
--   LoungeBuilder.setUp(parent)          -- all of the above, in order

local Config = require(script.Parent.Config)
local Placement = require(script.Parent.Placement)

local LoungeBuilder = {}

-- Config holds plain data, so the shapes it is read through are named here.
type PackageSpec = {
	CanCollide: boolean,
	Collision: string?,
	CastShadow: boolean,
	Material: string?,
	Hide: boolean?,
}

type PartRule = {
	Material: string?,
	Transparency: number?,
	Color: { number }?,
	CanCollide: boolean?,
}

-- Config is plain data with one entry per package, so Luau infers a struct with six named
-- fields rather than a map; go through `any` to read it as the map it is meant to be.
local PACKAGES = (Config.Lounge.Packages :: any) :: { [string]: PackageSpec }
local PART_RULES = (Config.Lounge.PartRules :: any) :: { [string]: PartRule }

LoungeBuilder.ModelName = "Lounge"
LoungeBuilder.PendantFolderName = "Pendants"

local function color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function material(name: string): Enum.Material
	return (Enum.Material :: any)[name]
end

--- Studio's 3D Importer reads the package's "-Z forward" axis as +Z, so every FBX arrives
--- turned half a turn, and the importer stacks the six at different heights. It does keep
--- each file's own origin as the model's pivot, so putting every pivot on the world origin
--- with a 180 degree yaw undoes the rotation and the stacking together.
---
--- Both X and Z are negated, which is a rotation and not a mirror, so nothing ends up
--- back to front: signs read the right way round.
---
--- Safe to run twice: a model already at the origin is left alone.
function LoungeBuilder.correctImport(parent: Instance): (Model, number)
	local found = parent:FindFirstChild(LoungeBuilder.ModelName)
	local lounge: Model
	if found and found:IsA("Model") then
		lounge = found
	else
		lounge = Instance.new("Model")
		lounge.Name = LoungeBuilder.ModelName
		lounge.Parent = parent
	end
	local moved = 0
	for name in PACKAGES do
		local package = parent:FindFirstChild(name) or lounge:FindFirstChild(name)
		if package and package:IsA("Model") then
			if package.Parent ~= lounge then
				package.Parent = lounge
			end
			if package:GetPivot().Position.Magnitude > 1e-3 then
				package:PivotTo(CFrame.Angles(0, math.pi, 0))
				moved += 1
			end
		else
			warn(("[8ball] lounge package %s is not imported"):format(name))
		end
	end
	lounge.WorldPivot = CFrame.new()
	return lounge, moved
end

local function ruleFor(part: BasePart): PartRule?
	return PART_RULES[part.Name]
end

local function noCollide(part: BasePart): boolean
	for _, fragment in Config.Lounge.NoCollideFragments do
		if part.Name:find(fragment, 1, true) then
			return true
		end
	end
	return false
end

--- Delete the pieces the package ships that the game itself provides, so the two cannot
--- clash. See Config.Lounge.RemovePartFragments.
function LoungeBuilder.removeClutter(lounge: Model): number
	local removed = 0
	for _, part in lounge:GetDescendants() do
		if part:IsA("BasePart") then
			for _, fragment in Config.Lounge.RemovePartFragments do
				if part.Name:find(fragment, 1, true) then
					part:Destroy()
					removed += 1
					break
				end
			end
		end
	end
	return removed
end

--- Materials, collision, shadows and render fidelity, package by package.
function LoungeBuilder.applyPackages(lounge: Model): number
	local touched = 0
	for name, spec in PACKAGES do
		local package = lounge:FindFirstChild(name)
		if package == nil then
			continue
		end
		for _, part in package:GetDescendants() do
			if not part:IsA("BasePart") then
				continue
			end
			touched += 1
			-- Every environment piece is anchored; nothing here should ever fall or be
			-- pushed by a player walking into it.
			part.Anchored = true
			part.CanCollide = spec.CanCollide and not noCollide(part)
			part.CanQuery = part.CanCollide
			part.CanTouch = false
			part.CastShadow = spec.CastShadow
			if spec.Material then
				part.Material = material(spec.Material)
			end
			if spec.Hide then
				-- The COL_* proxies are the collision the decorative meshes do not carry.
				part.Transparency = 1
				part.CastShadow = false
			end
			if part:IsA("MeshPart") then
				-- ARCHITECTURE.md section 7: automatic LOD on every mesh.
				part.RenderFidelity = Enum.RenderFidelity.Automatic
				if spec.Collision and part.CanCollide then
					part.CollisionFidelity = (Enum.CollisionFidelity :: any)[spec.Collision]
				end
			end
			local rule = ruleFor(part)
			if rule then
				if rule.Material then
					part.Material = material(rule.Material)
				end
				if rule.Transparency then
					part.Transparency = rule.Transparency
				end
				if rule.Color then
					part.Color = color(rule.Color)
				end
				if rule.CanCollide ~= nil then
					part.CanCollide = rule.CanCollide
					part.CanQuery = rule.CanCollide
				end
			end
		end
	end
	return touched
end

--- One downward light over each table. No shadows: see the note on Config.Lounge.Pendant.
function LoungeBuilder.buildPendants(lounge: Model): number
	local existing = lounge:FindFirstChild(LoungeBuilder.PendantFolderName)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = LoungeBuilder.PendantFolderName
	folder.Parent = lounge

	local P = Config.Lounge.Pendant
	local made = 0
	for _, row in Config.Lounge.Tables do
		local mount = Instance.new("Part")
		mount.Name = ("Pendant_%02d"):format(row.id)
		mount.Anchored = true
		mount.CanCollide = false
		mount.CanQuery = false
		mount.CanTouch = false
		mount.CastShadow = false
		mount.Transparency = 1
		mount.Size = Vector3.new(1, 0.2, 1)
		-- Directly over its own table, a fixed height above that tier's floor.
		mount.Position = Vector3.new(row.X, row.Y + P.HeightAboveFloor, row.Z)
		mount.Parent = folder

		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Bottom
		light.Angle = P.AngleDegrees
		light.Brightness = P.Brightness
		light.Range = P.RangeStuds
		light.Color = color(P.Color)
		light.Shadows = P.Shadows
		light.Parent = mount
		made += 1
	end
	return made
end

--- Invisible seats on the sofas and chairs. Sitting is free look: the player is seated and
--- nothing else happens, which is the call recorded in DECISIONS.md. A seat is spread along
--- the furniture's longer horizontal axis so a three-seat sofa really has three places.
function LoungeBuilder.buildSeats(lounge: Model): number
	local existing = lounge:FindFirstChild("Seats")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Seats"
	folder.Parent = lounge

	local F = Config.Lounge.SeatingFocus
	local focus = Vector3.new(F.X, F.Y, F.Z)
	local size = Config.Lounge.SeatSizeStuds
	local made = 0
	for _, row in Config.Lounge.Seating do
		local part = lounge:FindFirstChild(row.Part, true)
		if part == nil or not part:IsA("BasePart") then
			warn(("[8ball] no lounge furniture called %s to seat"):format(row.Part))
			continue
		end
		local alongX = part.Size.X >= part.Size.Z
		local span = if alongX then part.Size.X else part.Size.Z
		local top = part.Position.Y
			- part.Size.Y / 2
			+ part.Size.Y * Config.Lounge.SeatHeightFraction
		for i = 1, row.Seats do
			-- Evenly spaced along the furniture, inset so nobody sits on the arm.
			local t = if row.Seats == 1 then 0 else ((i - 1) / (row.Seats - 1) - 0.5) * 0.7
			local offset = if alongX
				then Vector3.new(span * t, 0, 0)
				else Vector3.new(0, 0, span * t)
			local at = Vector3.new(part.Position.X, top, part.Position.Z) + offset

			local seat = Instance.new("Seat")
			seat.Name = ("Seat_%s_%d"):format(row.Part:gsub("Furniture_", ""), i)
			seat.Anchored = true
			seat.CanCollide = true
			seat.CanQuery = false
			seat.CastShadow = false
			seat.Transparency = 1
			seat.Size = Vector3.new(size[1], size[2], size[3])
			-- Face the middle of the seating area, flat: a seat tilted at the floor would
			-- point the sitter's head at it.
			local toFocus = Vector3.new(focus.X - at.X, 0, focus.Z - at.Z)
			if toFocus.Magnitude < 1e-3 then
				toFocus = Vector3.new(0, 0, -1)
			end
			seat.CFrame = CFrame.lookAt(at, at + toFocus.Unit)
			seat.Parent = folder
			made += 1
		end
	end
	return made
end

--- The package's lighting recipe. Lighting.Technology is not scriptable, so if the shadows
--- look wrong it has to be set to Future by hand in the Lighting properties.
function LoungeBuilder.applyLighting()
	local L = Config.Lounge.Lighting
	local lighting = game:GetService("Lighting")
	lighting.ClockTime = L.ClockTime
	lighting.Brightness = L.Brightness
	lighting.Ambient = color(L.Ambient)
	lighting.OutdoorAmbient = color(L.OutdoorAmbient)
	lighting.ColorShift_Top = color(L.ColorShiftTop)
	lighting.EnvironmentDiffuseScale = L.EnvironmentDiffuseScale
	lighting.EnvironmentSpecularScale = L.EnvironmentSpecularScale
	lighting.GlobalShadows = true

	local bloom = lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = L.Bloom.Intensity
	bloom.Size = L.Bloom.Size
	bloom.Threshold = L.Bloom.Threshold
	bloom.Enabled = true
	bloom.Parent = lighting

	local cc = lighting:FindFirstChildOfClass("ColorCorrectionEffect")
		or Instance.new("ColorCorrectionEffect")
	cc.Brightness = L.ColorCorrection.Brightness
	cc.Contrast = L.ColorCorrection.Contrast
	cc.Saturation = L.ColorCorrection.Saturation
	cc.TintColor = color(L.ColorCorrection.TintColor)
	cc.Enabled = true
	cc.Parent = lighting
end

--- Put the spawn where the package says, facing the tables.
function LoungeBuilder.placeSpawn(parent: Instance)
	local S = Config.Lounge.Spawn
	local existing = parent:FindFirstChildOfClass("SpawnLocation")
	local spawn: SpawnLocation = existing or Instance.new("SpawnLocation")
	spawn.Name = "LoungeSpawn"
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Transparency = 1
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.Neutral = true
	-- Sunk into the floor so it is invisible but still catches the character, and turned to
	-- face down the room: the tables run away in -Z.
	spawn.CFrame = CFrame.new(S.X, S.Y - 0.5, S.Z) * CFrame.Angles(0, math.pi, 0)
	spawn.Parent = parent
end

--- Everything above, in order. Run from Studio's command bar in EDIT mode, then save.
function LoungeBuilder.setUp(parent: Instance): string
	local lounge, moved = LoungeBuilder.correctImport(parent)
	local removed = LoungeBuilder.removeClutter(lounge)
	local parts = LoungeBuilder.applyPackages(lounge)
	local lights = LoungeBuilder.buildPendants(lounge)
	local seats = LoungeBuilder.buildSeats(lounge)
	LoungeBuilder.applyLighting()
	LoungeBuilder.placeSpawn(parent)
	return ("[8ball] lounge ready: %d repositioned, %d clutter removed, %d parts set up, %d pendants, %d seats"):format(
		moved,
		removed,
		parts,
		lights,
		seats
	)
end

--- True when the place actually holds an imported lounge (Bootstrap warns if it does not).
function LoungeBuilder.isImported(parent: Instance): boolean
	local lounge = parent:FindFirstChild(LoungeBuilder.ModelName)
	if lounge == nil then
		return false
	end
	for name in PACKAGES do
		if lounge:FindFirstChild(name) == nil then
			return false
		end
	end
	return true
end

--- Where table `id` stands, straight from Config. Kept here so the lounge and the tables
--- can never disagree about a table's position.
function LoungeBuilder.placementFor(id: number): Placement.Placement?
	return Placement.forTable(id)
end

return LoungeBuilder
