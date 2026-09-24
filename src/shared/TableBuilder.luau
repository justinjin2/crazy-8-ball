--!strict
-- TableBuilder: builds the visible pool table out of Parts from the same Config numbers
-- the physics uses, so the cushions you see are exactly the cushions the balls bounce off.
-- It touches Instances only inside functions, so the Lune tests can load it and check the
-- pure parts (lookFor); tests/table_looks_test.luau does.
--
-- Two builds: the imported Blender model with its looks (the section below), and the
-- parts-and-solid-modelling fallback used when the place has no template. The fallback's
-- layout, from the outside in: a wooden frame ring at rail-top height, the rubber cushion
-- strips (one per physics segment, inner face on the cushion line, lower than the frame),
-- the cloth bed inside, and six dark pocket liners cut through the frame at the mouths.

local Config = require(script.Parent.Config)
local Placement = require(script.Parent.Placement)
local TableGeometry = require(script.Parent.Physics.Table)

local TableBuilder = {}

export type Placement = Placement.Placement

--- Folder in Workspace that holds every server-built table model.
TableBuilder.FolderName = "Tables"

--- Instance name for table `id`: Table_01 ... Table_12.
function TableBuilder.modelName(id: number): string
	return ("Table_%02d"):format(id)
end

local function color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function material(name: string): Enum.Material
	return (Enum.Material :: any)[name]
end

--- World-space position for a physics point (inches) on table `p` at a height above the
--- cloth (inches). The maths lives in Placement (pure, tested); this only makes a Vector3.
function TableBuilder.toWorld(p: Placement, xIn: number, yIn: number, heightIn: number): Vector3
	return Vector3.new(Placement.toWorld(p, xIn, yIn, heightIn))
end

--- Physics coordinates (inches) on table `p` for a world position.
function TableBuilder.toTable(p: Placement, world: Vector3): (number, number)
	return Placement.toTable(p, world.X, world.Z)
end

--- World-space aim direction on table `p` for a physics aim angle.
function TableBuilder.aimDirection(p: Placement, angle: number): Vector3
	return Vector3.new(Placement.aimVector(p, angle))
end

--- The CFrame that turns table-space offsets into world ones (no translation): used for
--- rotating parts and angular velocity onto the table.
function TableBuilder.yawCFrame(p: Placement): CFrame
	return CFrame.Angles(0, p.yaw, 0)
end

--- Studs for an inch length.
function TableBuilder.studs(inches: number): number
	return inches * Config.Table.StudsPerInch
end

local function makePart(
	name: string,
	size: Vector3,
	position: Vector3,
	rgb: { number },
	mat: string,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.CastShadow = true
	part.Size = size
	part.Position = position
	part.Color = color(rgb)
	part.Material = material(mat)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

--- Name of the cloth MaterialVariant to use, or "" for the plain built-in material.
---
--- Game scripts are not allowed to write material maps (plugin-only), so the variant must
--- already exist in MaterialService in the saved place. `TableBuilder.createClothMaterial()`
--- (re)creates it from the Config map ids when run from the Studio command bar or by the
--- assistant in Edit mode; save the place afterwards so it ships with the game.
function TableBuilder.ensureClothMaterial(): string
	local L = Config.Look
	if L.FeltMaterialVariant == "" then
		return ""
	end
	local existing = game:GetService("MaterialService"):FindFirstChild(L.FeltMaterialVariant)
	if existing and existing:IsA("MaterialVariant") then
		return existing.Name
	end
	-- Not in the place: try to make it (works in Edit mode / plugins only).
	local ok = pcall(TableBuilder.createClothMaterial)
	if ok then
		return L.FeltMaterialVariant
	end
	warn(
		"[8ball] cloth MaterialVariant '"
			.. L.FeltMaterialVariant
			.. "' is missing from MaterialService; using plain "
			.. L.FeltMaterial
	)
	return ""
end

--- Create or refresh the cloth MaterialVariant from Config. Edit mode / plugin context only.
function TableBuilder.createClothMaterial(): MaterialVariant
	local L = Config.Look
	local MaterialService = game:GetService("MaterialService")
	local existing = MaterialService:FindFirstChild(L.FeltMaterialVariant)
	local variant: MaterialVariant
	if existing and existing:IsA("MaterialVariant") then
		variant = existing
	else
		variant = Instance.new("MaterialVariant")
		variant.Name = L.FeltMaterialVariant
		variant.BaseMaterial = material(L.FeltMaterial)
	end
	variant.ColorMap = L.FeltMaps.Color
	variant.NormalMap = L.FeltMaps.Normal
	variant.RoughnessMap = L.FeltMaps.Roughness
	variant.MetalnessMap = L.FeltMaps.Metalness
	variant.StudsPerTile = L.FeltStudsPerTile
	variant.Parent = MaterialService
	return variant
end

---------------------------------------------------------------------------------------------
-- The imported table model and its looks
--
-- One Blender-built model (eight MeshParts, see Config.TableModel) is shared by every table.
-- A look only changes SurfaceAppearances. Their map ids are plugin-only writes, so each look
-- is built once in Edit mode by prepareImport into ServerStorage.<LooksFolder>.<Look>.<Mesh>
-- and saved in the place; at run time a table clones its look's SurfaceAppearances (cloning
-- is allowed) and sets the cloth tint (SurfaceAppearance.Color is script-writable).
--
--   TableBuilder.lookFor(id)             -- which look table `id` wears (pure)
--   TableBuilder.checkTemplate(template) -- plain-English list of what is wrong with it
--   TableBuilder.prepareImport(spec?)    -- Edit mode: tidy a fresh import, build the looks
--   TableBuilder.applyLook(model, look)  -- run time: dress a clone in a look
---------------------------------------------------------------------------------------------

--- Config.TableModel's shape. prepareImport and checkTemplate take a fresh copy of it,
--- because Edit-mode requires are cached for the whole Studio session.
export type ModelSpec = typeof(Config.TableModel)

type MeshSpec = { CanCollide: boolean, Collision: string?, CastShadow: boolean, AlphaMode: string? }

-- Each distinct message is printed once per server, not once per table.
local warned: { [string]: boolean } = {}
local function warnOnce(message: string)
	if not warned[message] then
		warned[message] = true
		warn("[8ball] " .. message)
	end
end

-- Names in a fixed order, so reports and problem lists read the same on every run.
local function sortedKeys(t: { [string]: any }): { string }
	local keys = {}
	for key in t do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

--- The look table `id` wears: Config.TableModel.LookByTable, else DefaultLook. A name that
--- is not a look falls back to DefaultLook with a warning. Pure (no Instances).
function TableBuilder.lookFor(id: number): string
	local TM = Config.TableModel
	local wanted = TM.LookByTable[id] or TM.DefaultLook
	if TM.Looks[wanted] ~= nil then
		return wanted
	end
	warnOnce(
		("table %d asks for look '%s', which Config.TableModel.Looks does not have; using '%s'"):format(
			id,
			wanted,
			TM.DefaultLook
		)
	)
	return TM.DefaultLook
end

--- The imported table model template, if the place has one.
function TableBuilder.findModelTemplate(): Model?
	local ServerStorage = game:GetService("ServerStorage")
	local found = ServerStorage:FindFirstChild(Config.TableModel.Name)
	if found and found:IsA("Model") then
		return found
	end
	return nil
end

-- Centre and half size of a part's bounding box, on the axes of `frame` (the part may be
-- turned inside it). MeshPart.Size is the mesh's own bounding box, centred on its CFrame.
local function boundsIn(part: BasePart, frame: CFrame): (Vector3, Vector3)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 =
		frame:ToObjectSpace(part.CFrame):GetComponents()
	local h = part.Size / 2
	local half = Vector3.new(
		math.abs(r00) * h.X + math.abs(r01) * h.Y + math.abs(r02) * h.Z,
		math.abs(r10) * h.X + math.abs(r11) * h.Y + math.abs(r12) * h.Z,
		math.abs(r20) * h.X + math.abs(r21) * h.Y + math.abs(r22) * h.Z
	)
	return Vector3.new(x, y, z), half
end

local function meshNamed(model: Instance, name: string): MeshPart?
	local found = model:FindFirstChild(name)
	if found and found:IsA("MeshPart") then
		return found
	end
	return nil
end

local function findMeshDeep(model: Instance, name: string): MeshPart?
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") and d.Name == name then
			return d
		end
	end
	return nil
end

--- What is wrong with a table template, in plain English; empty when it is ready. Checks,
--- in the template's pivot frame (the one buildFromModel places): every Config mesh is a
--- MeshPart at the top level and nothing else is there; the Rails footprint matches
--- Config.Table (a mismatch means a wrong Scale Unit or a 90 degree turn); the pivot is on
--- the floor under the table centre; and the LogoPlate (the foot end) is at +X.
function TableBuilder.checkTemplate(template: Model, spec: ModelSpec?): { string }
	local TM = spec or Config.TableModel
	local T = Config.Table
	local s = T.StudsPerInch
	local problems: { string } = {}
	local function problem(message: string)
		table.insert(problems, message)
	end

	for _, name in sortedKeys(TM.Meshes) do
		local found = template:FindFirstChild(name)
		local nested = findMeshDeep(template, name)
		if found and found:IsA("MeshPart") then
			continue
		elseif nested and nested:IsA("MeshPart") then
			problem(
				("mesh %s is nested inside %s; run prepareImport, which moves it to the top"):format(
					name,
					(nested.Parent :: Instance).Name
				)
			)
		elseif found then
			problem(("%s is a %s, not a MeshPart"):format(name, found.ClassName))
		elseif not (name == TM.CapsMesh and not TM.Caps) then
			problem(("mesh %s is missing"):format(name))
		end
	end
	local extras: { string } = {}
	for _, d in template:GetDescendants() do
		if d:IsA("BasePart") and TM.Meshes[d.Name] == nil then
			table.insert(extras, d.Name)
		end
	end
	table.sort(extras)
	for _, name in extras do
		problem(
			("extra part %s is not in Config.TableModel.Meshes (tables draw it with collision and shadows off)"):format(
				name
			)
		)
	end

	local pivot = template:GetPivot()
	local rails = meshNamed(template, "Rails")
	if rails then
		local centre, half = boundsIn(rails, pivot)
		local wantX = (T.LengthInches + 2 * T.RailWidthInches) * s
		local wantZ = (T.WidthInches + 2 * T.RailWidthInches) * s
		local gotX, gotZ = half.X * 2, half.Z * 2
		local function close(got: number, want: number): boolean
			return math.abs(got - want) <= want * TM.FootprintTolerance
		end
		if close(gotX, wantX) and close(gotZ, wantZ) then
			local crown = centre.Y + half.Y
			local wantCrown = T.SurfaceHeightStuds + T.RailTopInches * s
			local tol = TM.PivotToleranceStuds
			if math.abs(crown - wantCrown) > tol then
				problem(
					("the rail crown is %.3f studs above the pivot, not %.3f: the pivot is not on the floor (run prepareImport)"):format(
						crown,
						wantCrown
					)
				)
			end
			if math.abs(centre.X) > tol or math.abs(centre.Z) > tol then
				problem(
					("the rails are centred %.3f, %.3f studs off the pivot: the pivot is not at the table centre (run prepareImport)"):format(
						centre.X,
						centre.Z
					)
				)
			end
		elseif close(gotX, wantZ) and close(gotZ, wantX) then
			problem(
				("the table is turned 90 degrees: its long side runs along the pivot's Z (%.2f x %.2f studs); run prepareImport"):format(
					gotX,
					gotZ
				)
			)
		else
			problem(
				("the rails are %.2f x %.2f studs, expected %.2f x %.2f (%.3g times the size): re-import with Scale Unit: Stud at scale 1"):format(
					gotX,
					gotZ,
					wantX,
					wantZ,
					math.max(gotX, gotZ) / wantX
				)
			)
		end
	end

	local logo = meshNamed(template, "LogoPlate")
	if logo then
		local at = boundsIn(logo, pivot)
		if at.X <= 0 or math.abs(at.X) < math.abs(at.Z) then
			problem(
				("the LogoPlate (the foot end) is at X %.2f, Z %.2f in the pivot's frame, not at +X: the table is turned (run prepareImport)"):format(
					at.X,
					at.Z
				)
			)
		end
	end
	return problems
end

--- Dress `model` in `look`: clone the look's SurfaceAppearances from ServerStorage onto its
--- meshes, set the Config tint, and record the look in the model's "Look" attribute. Runs
--- at run time on the server. A mesh whose look has no stored SurfaceAppearance (maps not
--- uploaded yet) keeps what it wears, and the tint goes on that (or on the bare part). An
--- overlay mesh (a Meshes entry with an AlphaMode, such as Marks) is see-through only through
--- its SurfaceAppearance, so it is hidden (Transparency 1, script-writable) while it has none
--- and shown once it has one. Returns the names of the overlays left hidden.
function TableBuilder.applyLook(model: Model, look: string, spec: ModelSpec?): { string }
	local TM = spec or Config.TableModel
	if TM.Looks[look] == nil then
		warnOnce(
			("look '%s' is not in Config.TableModel.Looks; using '%s'"):format(look, TM.DefaultLook)
		)
		look = TM.DefaultLook
	end
	local parts = TM.Looks[look]
	local folder = game:GetService("ServerStorage"):FindFirstChild(TM.LooksFolder)
	local stored = folder and folder:FindFirstChild(look)
	if stored == nil then
		warnOnce(
			("ServerStorage.%s.%s is missing (run TableBuilder.prepareImport in Edit mode); tables keep the template's own maps"):format(
				TM.LooksFolder,
				look
			)
		)
	end
	for _, meshName in sortedKeys(parts) do
		local mesh = meshNamed(model, meshName)
		if mesh == nil then
			continue
		end
		local source = stored and stored:FindFirstChild(meshName)
		if source and source:IsA("SurfaceAppearance") then
			for _, old in mesh:GetChildren() do
				if old:IsA("SurfaceAppearance") then
					old:Destroy()
				end
			end
			source:Clone().Parent = mesh
		end
		local tint = parts[meshName].Tint
		if tint then
			local appearance = mesh:FindFirstChildOfClass("SurfaceAppearance")
			if appearance then
				appearance.Color = color(tint)
			else
				mesh.Color = color(tint)
			end
		end
	end
	local hidden: { string } = {}
	for _, meshName in sortedKeys(TM.Meshes) do
		local ms: MeshSpec = TM.Meshes[meshName]
		local mesh = meshNamed(model, meshName)
		if ms.AlphaMode == nil or mesh == nil then
			continue
		end
		if mesh:FindFirstChildOfClass("SurfaceAppearance") then
			mesh.Transparency = 0
		else
			mesh.Transparency = 1
			table.insert(hidden, meshName)
		end
	end
	model:SetAttribute("Look", look)
	return hidden
end

-- Triangles in a mesh, read through an EditableMesh (Edit mode, the user's own meshes).
local function triangleCount(mesh: MeshPart): number?
	local ok, result = pcall(function()
		local editable = game:GetService("AssetService"):CreateEditableMeshAsync(mesh.MeshContent)
		local count = #editable:GetFaces()
		editable:Destroy()
		return count
	end)
	return if ok then result else nil
end

local function hasAnyMap(maps: { [string]: string? }): boolean
	for _, id in maps do
		if id ~= "" then
			return true
		end
	end
	return false
end

--- Edit mode only (the writes it makes are plugin-only): turn a fresh import of the table
--- into the template every table is cloned from, and build the looks. Safe to run twice.
---   1. Finds `spec.Name` in ServerStorage (or Workspace, and moves it to ServerStorage).
---   2. Moves nested MeshParts to the top and deletes the emptied containers.
---   3. Rebuilds the pivot at the cloth centre on the floor, its +X towards the foot (the
---      LogoPlate), which undoes the importer's half turn (see LoungeBuilder.correctImport).
---   4. Sets collision, shadows, automatic render fidelity, CanTouch and CanQuery per mesh.
---   5. Strips the importer's SurfaceAppearances and TextureIDs.
---   6. Rebuilds ServerStorage.<LooksFolder>.<Look>.<Mesh> from the Config map ids (empty ids
---      are skipped) and dresses the template in DefaultLook.
--- Returns a plain-English report. `spec` defaults to Config.TableModel; pass a fresh copy
--- after changing Config (docs/STUDIO_NOTES.md has the command-bar line).
function TableBuilder.prepareImport(spec: ModelSpec?): string
	local TM = spec or Config.TableModel
	if game:GetService("RunService"):IsRunning() then
		error("TableBuilder.prepareImport runs in Edit mode only; stop the play session first")
	end
	local ServerStorage = game:GetService("ServerStorage")
	local lines: { string } = {}
	local function say(line: string)
		table.insert(lines, line)
	end

	local found = ServerStorage:FindFirstChild(TM.Name) or workspace:FindFirstChild(TM.Name)
	if not (found and found:IsA("Model")) then
		return ("No Model named %s in ServerStorage or Workspace. Import assets/table/PoolTable.fbx with the 3D Importer (Scale Unit: Stud), name the model %s and run this again."):format(
			TM.Name,
			TM.Name
		)
	end
	local template: Model = found
	if template.Parent ~= ServerStorage then
		template.Parent = ServerStorage
		say(("Moved %s from Workspace to ServerStorage."):format(TM.Name))
	end

	-- 2. Flatten. The snapshot from GetDescendants stays valid while parts move.
	local moved, removed = 0, 0
	for _, d in template:GetDescendants() do
		if d:IsA("MeshPart") and d.Parent ~= template then
			d.Parent = template
			moved += 1
		end
	end
	for _, child in template:GetChildren() do
		if
			(child:IsA("Model") or child:IsA("Folder"))
			and child:FindFirstChildWhichIsA("BasePart", true) == nil
		then
			child:Destroy()
			removed += 1
		end
	end
	if moved > 0 or removed > 0 then
		say(
			("Moved %d nested meshes to the top and removed %d empty containers."):format(
				moved,
				removed
			)
		)
	end

	-- 3. Pivot: the cloth's centre across the table, the floor under the legs (Body's
	-- bottom; the cloth mesh also carries the cushions, so its top is not the playing
	-- surface), and +X towards the LogoPlate on the foot end.
	local cloth, logo, body =
		meshNamed(template, "Cloth"), meshNamed(template, "LogoPlate"), meshNamed(template, "Body")
	if cloth and logo and body then
		local clothAt = boundsIn(cloth, CFrame.identity)
		local logoAt = boundsIn(logo, CFrame.identity)
		local bodyAt, bodyHalf = boundsIn(body, CFrame.identity)
		local foot = Vector3.new(logoAt.X - clothAt.X, 0, logoAt.Z - clothAt.Z)
		if foot.Magnitude < 1e-3 then
			say("Could not rebuild the pivot: the LogoPlate sits over the cloth centre.")
		else
			local before = template:GetPivot()
			template.PrimaryPart = nil -- a PrimaryPart would own the pivot instead
			template.WorldPivot = CFrame.fromMatrix(
				Vector3.new(clothAt.X, bodyAt.Y - bodyHalf.Y, clothAt.Z),
				foot.Unit,
				Vector3.yAxis
			)
			local turn = before.RightVector:Dot(foot.Unit)
			say(
				if turn < -0.5
					then "Pivot rebuilt at the cloth centre on the floor, undoing the importer's half turn."
					elseif
						turn < 0.5
					then "Pivot rebuilt at the cloth centre on the floor, turned a quarter turn."
					else "Pivot rebuilt at the cloth centre on the floor (the foot was already at +X)."
			)
		end
	else
		say("Could not rebuild the pivot: it needs the Cloth, LogoPlate and Body meshes.")
	end

	-- 4 and 5. Per-mesh settings, and a clean slate for the looks.
	local stripped = 0
	for _, child in template:GetChildren() do
		if not child:IsA("MeshPart") then
			continue
		end
		local ms: MeshSpec? = TM.Meshes[child.Name]
		local collide = if ms then ms.CanCollide else false
		child.Anchored = true
		child.CanCollide = collide
		child.CanQuery = collide
		child.CanTouch = false
		child.CastShadow = if ms then ms.CastShadow else false
		child.RenderFidelity = Enum.RenderFidelity.Automatic
		local fidelity = if ms and ms.CanCollide and ms.Collision then ms.Collision else "Box"
		child.CollisionFidelity = (Enum.CollisionFidelity :: any)[fidelity]
		if child.TextureID ~= "" then
			child.TextureID = ""
			stripped += 1
		end
		for _, old in child:GetChildren() do
			if old:IsA("SurfaceAppearance") then
				old:Destroy()
				stripped += 1
			end
		end
	end
	if stripped > 0 then
		say(("Stripped %d importer textures and SurfaceAppearances."):format(stripped))
	end

	-- 6. The looks, rebuilt from scratch so a changed id never lingers.
	local oldFolder = ServerStorage:FindFirstChild(TM.LooksFolder)
	if oldFolder then
		oldFolder:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = TM.LooksFolder
	for _, lookName in sortedKeys(TM.Looks) do
		local look = TM.Looks[lookName]
		local lookFolder = Instance.new("Folder")
		lookFolder.Name = lookName
		lookFolder.Parent = folder
		local made = 0
		local bare: { string } = {}
		for _, meshName in sortedKeys(look) do
			local entry = look[meshName]
			local maps = TM.Maps[entry.Maps]
			if maps == nil then
				say(
					("PROBLEM: look %s gives %s the map set %s, which Config.TableModel.Maps does not have."):format(
						lookName,
						meshName,
						entry.Maps
					)
				)
				continue
			end
			if not hasAnyMap(maps :: any) then
				table.insert(bare, meshName)
				continue
			end
			local ms: MeshSpec? = TM.Meshes[meshName]
			local appearance = Instance.new("SurfaceAppearance")
			appearance.Name = meshName
			appearance.AlphaMode = (Enum.AlphaMode :: any)[if ms and ms.AlphaMode
				then ms.AlphaMode
				else "Overlay"]
			if maps.Color ~= "" then
				appearance.ColorMap = maps.Color
			end
			if maps.Normal and maps.Normal ~= "" then
				appearance.NormalMap = maps.Normal
			end
			if maps.Roughness and maps.Roughness ~= "" then
				appearance.RoughnessMap = maps.Roughness
			end
			if maps.Metalness and maps.Metalness ~= "" then
				appearance.MetalnessMap = maps.Metalness
			end
			if entry.Tint then
				appearance.Color = color(entry.Tint)
			end
			appearance.Parent = lookFolder
			made += 1
		end
		say(
			("Look %s: %d SurfaceAppearances%s."):format(
				lookName,
				made,
				if #bare > 0
					then "; no maps uploaded yet for " .. table.concat(bare, ", ") .. " (left bare)"
					else ""
			)
		)
	end
	folder.Parent = ServerStorage
	local hidden = TableBuilder.applyLook(template, TM.DefaultLook, TM)
	say(("Template dressed in %s."):format(TM.DefaultLook))
	for _, name in hidden do
		say(
			("%s hidden until its maps are uploaded (an overlay with no SurfaceAppearance would draw as solid grey)."):format(
				name
			)
		)
	end

	-- Triangle budget (ARCHITECTURE section 7).
	local total, counted, uncounted = 0, {}, {}
	for _, name in sortedKeys(TM.Meshes) do
		local mesh = meshNamed(template, name)
		local count = mesh and triangleCount(mesh)
		if count then
			total += count
			table.insert(counted, ("%s %d"):format(name, count))
		else
			table.insert(uncounted, name)
		end
	end
	say(
		("Triangles: %d of %d%s (%s)%s."):format(
			total,
			TM.TriangleBudget,
			if total > TM.TriangleBudget then ", OVER BUDGET" else "",
			table.concat(counted, ", "),
			if #uncounted > 0 then "; could not count " .. table.concat(uncounted, ", ") else ""
		)
	)

	local problems = TableBuilder.checkTemplate(template, TM)
	if #problems == 0 then
		say("checkTemplate: no problems.")
	end
	for _, p in problems do
		say("PROBLEM: " .. p)
	end
	return table.concat(lines, "\n")
end

--- Place a clone of the template at table `p`, dressed from Config: collision and shadows
--- per mesh (an unlisted part gets everything off and one warning), the caps removed when
--- Config.TableModel.Caps is false, and `look` (default: lookFor(id)). Joining is the floor
--- pad's job (src/server/TableService.luau), so no prompt is attached.
function TableBuilder.buildFromModel(
	template: Model,
	parent: Instance,
	p: Placement,
	id: number,
	look: string?
): Model
	local TM = Config.TableModel
	local model = template:Clone()
	model.Name = TableBuilder.modelName(id)
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		local ms: MeshSpec? = TM.Meshes[part.Name]
		part.Anchored = true
		part.CanTouch = false
		if ms then
			part.CanCollide = ms.CanCollide
			part.CanQuery = ms.CanCollide
			part.CastShadow = ms.CastShadow
		else
			part.CanCollide = false
			part.CanQuery = false
			part.CastShadow = false
			warnOnce(
				("table model part %s is not in Config.TableModel.Meshes; drawn with collision and shadows off"):format(
					part.Name
				)
			)
		end
	end
	if not TM.Caps then
		local caps = model:FindFirstChild(TM.CapsMesh)
		if caps then
			caps:Destroy()
		end
	end
	TableBuilder.applyLook(model, look or TableBuilder.lookFor(id))
	-- prepareImport put the pivot at the cloth centre on the floor with +X to the foot, so
	-- the placement's position and yaw carry the whole table.
	model:PivotTo(CFrame.new(p.x, p.y, p.z) * TableBuilder.yawCFrame(p))
	model.Parent = parent
	return model
end

local templateChecked = false

--- Build the visible table for `id` at placement `p` under `parent`: the imported model when
--- the place has one (checked once per server, problems go to the output), otherwise the
--- parts-and-solid-modelling build, with one warning saying why. Returns the model.
function TableBuilder.build(parent: Instance, p: Placement, id: number): Model
	local template = TableBuilder.findModelTemplate()
	if template then
		if not templateChecked then
			templateChecked = true
			for _, problem in TableBuilder.checkTemplate(template) do
				warn("[8ball] table template " .. Config.TableModel.Name .. ": " .. problem)
			end
		end
		return TableBuilder.buildFromModel(template, parent, p, id)
	end
	warnOnce(
		("ServerStorage.%s not found; drawing the parts-built table (the old PoolTableModel is not used by this code; import the new table and run TableBuilder.prepareImport)"):format(
			Config.TableModel.Name
		)
	)
	return TableBuilder.buildFromParts(parent, p, id)
end

--- Build the table from Parts and solid modelling (the pre-model fallback). Everything is
--- laid out around a zero origin with no yaw and the finished model is pivoted into place,
--- so the hundreds of offsets below stay readable.
function TableBuilder.buildFromParts(parent: Instance, p: Placement, id: number): Model
	local T = Config.Table
	local L = Config.Look
	local s = T.StudsPerInch
	local origin = Vector3.zero

	local model = Instance.new("Model")
	model.Name = TableBuilder.modelName(id)
	model.Parent = parent -- solid modelling below needs the parts to be in the world already
	local clothVariant = TableBuilder.ensureClothMaterial()

	local length = T.LengthInches
	local width = T.WidthInches
	local railW = T.RailWidthInches
	local railH = T.RailHeightInches
	local cushionW = T.CushionWidthInches
	local cushionH = T.CushionHeightInches
	local bed = T.BedThicknessInches
	local surfaceY = T.SurfaceHeightInches
	local apronH = 7

	-- Cloth bed: top face is the playing surface.
	local bedPart = makePart(
		"Bed",
		Vector3.new((length + 2 * cushionW) * s, bed * s, (width + 2 * cushionW) * s),
		origin + Vector3.new(0, (surfaceY - bed / 2) * s, 0),
		L.FeltColor,
		L.FeltMaterial,
		model
	)
	if clothVariant ~= "" then
		bedPart.MaterialVariant = clothVariant
	end

	-- Frame: four wooden boxes from below the bed up to the rail top. The pocket liners sit
	-- on top of the wood as matte dark discs, which reads as holes from the play views.
	local frameBottom = surfaceY - bed - apronH
	local frameTop = surfaceY + railH
	local frameH = frameTop - frameBottom
	local frameY = (frameBottom + frameH / 2) * s
	local ringW = railW - cushionW -- the frame starts where the cushion strip ends
	local outerL = length + 2 * railW
	local outerW = width + 2 * railW
	local geometry = TableGeometry.build({ pocketsOpen = true })
	for _, sz in { -1, 1 } do
		makePart(
			"FrameLong",
			Vector3.new(outerL * s, frameH * s, ringW * s),
			origin + Vector3.new(0, frameY, sz * (width / 2 + cushionW + ringW / 2) * s),
			L.RailColor,
			L.RailMaterial,
			model
		)
	end
	for _, sx in { -1, 1 } do
		makePart(
			"FrameShort",
			Vector3.new(ringW * s, frameH * s, (width + 2 * cushionW) * s),
			origin + Vector3.new(sx * (length / 2 + cushionW + ringW / 2) * s, frameY, 0),
			L.RailColor,
			L.RailMaterial,
			model
		)
	end
	-- Dark apron under the whole frame so nothing shows through from below.
	makePart(
		"Apron",
		Vector3.new(outerL * s, apronH * s, outerW * s),
		origin + Vector3.new(0, (frameBottom + apronH / 2) * s, 0),
		L.FrameColor,
		L.FrameMaterial,
		model
	)

	-- Cushions: one strip per physics segment (rails and the angled jaw facings). The inner
	-- face lies exactly on the segment line the balls bounce off; the strip is as tall as
	-- the wooden rail and tucks under it so cloth and wood meet flush.
	local cushionDepth = cushionW + T.CushionOverlapInches
	local cushionY = (surfaceY + cushionH / 2) * s
	for _, seg in geometry.segments do
		local dx, dy = seg.bx - seg.ax, seg.by - seg.ay
		local segLen = math.sqrt(dx * dx + dy * dy)
		local mx = (seg.ax + seg.bx) / 2 - seg.nx * cushionDepth / 2
		local my = (seg.ay + seg.by) / 2 - seg.ny * cushionDepth / 2
		local part = makePart(
			"Cushion_" .. seg.name,
			Vector3.new(segLen * s, cushionH * s, cushionDepth * s),
			origin + Vector3.new(mx * s, cushionY, -my * s),
			L.CushionColor,
			L.FeltMaterial,
			model
		)
		-- Physics y is world -Z, so a segment angle of a (physics) is a rotation of +a about Y.
		part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, math.atan2(dy, dx), 0)
		part.CanCollide = false
		if clothVariant ~= "" then
			part.MaterialVariant = clothVariant
		end
	end

	-- Pocket holes. Solid modelling cuts a cylinder through the cloth bed and the frame at
	-- each pocket so you look down into a dark shaft, like a real pocket. If the cut fails
	-- (solid modelling can refuse odd shapes), the dark discs are kept as a fallback.
	local holeR = {}
	local cutters: { BasePart } = {}
	local shaftTop = surfaceY + railH + 1
	local shaftBottom = surfaceY - L.PocketShaftDepthInches
	for _, pocket in geometry.pockets do
		-- Cut one leather thickness wider than the physics opening, so the lining's INNER
		-- face lands exactly on the rim the ball falls through. Art and physics then share
		-- one number and cannot drift apart.
		local r = pocket.radius + L.PocketWallThicknessInches
		holeR[pocket.id] = r
		local cutter = Instance.new("Part")
		cutter.Name = "Cutter" .. pocket.id
		cutter.Shape = Enum.PartType.Cylinder
		cutter.Anchored = true
		cutter.CanCollide = false
		cutter.Size = Vector3.new((shaftTop - shaftBottom + 2) * s, r * 2 * s, r * 2 * s)
		cutter.CFrame = CFrame.new(
			origin + Vector3.new(pocket.x * s, ((shaftTop + shaftBottom) / 2) * s, -pocket.y * s)
		) * CFrame.Angles(0, 0, math.rad(90))
		cutter.Parent = model
		table.insert(cutters, cutter)
	end
	local function cutHoles(part: BasePart)
		local ok, result = pcall(function()
			return part:SubtractAsync(
				cutters,
				Enum.CollisionFidelity.Box,
				Enum.RenderFidelity.Precise
			)
		end)
		if ok and result then
			result.Name = part.Name
			result.Anchored = true
			result.CanCollide = part.CanCollide
			result.UsePartColor = true
			result.Color = part.Color
			result.Material = part.Material
			if part:IsA("Part") and part.MaterialVariant ~= "" then
				result.MaterialVariant = part.MaterialVariant
			end
			result.Parent = model
			part:Destroy()
			return true
		end
		warn("[8ball] pocket cut failed on " .. part.Name .. ": " .. tostring(result))
		return false
	end
	local cutOk = true
	for _, name in { "Bed", "FrameLong", "FrameShort" } do
		for _, part in model:GetChildren() do
			if part.Name == name and part:IsA("Part") then
				cutOk = cutHoles(part) and cutOk
			end
		end
	end
	for _, cutter in cutters do
		cutter:Destroy()
	end

	-- Pocket castings. On a real table a leather U sits on the rail around the outer half
	-- of each hole (open towards the cloth) and lines the hole wall down to the cloth, so
	-- the ball never drops past bare wood. Built with solid modelling: an annulus minus a
	-- box over the inner half. Falls back to nothing if a cut is refused.
	local function subtract(part: BasePart, cutterParts: { BasePart }): BasePart?
		local ok, result = pcall(function()
			return part:SubtractAsync(
				cutterParts,
				Enum.CollisionFidelity.Box,
				Enum.RenderFidelity.Precise
			)
		end)
		for _, cutter in cutterParts do
			cutter:Destroy()
		end
		if ok and result then
			result.Name = part.Name
			result.Anchored = true
			result.CanCollide = false
			result.UsePartColor = true
			result.Color = part.Color
			result.Material = part.Material
			result.Parent = model
			part:Destroy()
			return result
		end
		part:Destroy()
		return nil
	end
	local function verticalCylinder(
		name: string,
		x: number,
		y: number,
		top: number,
		bottom: number,
		radius: number
	): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = Enum.PartType.Cylinder
		part.Anchored = true
		part.CanCollide = false
		part.CastShadow = false
		part.Material = material(L.PocketMaterial)
		part.Color = color(L.PocketColor)
		part.Size = Vector3.new((top - bottom) * s, radius * 2 * s, radius * 2 * s)
		part.CFrame = CFrame.new(origin + Vector3.new(x * s, ((top + bottom) / 2) * s, -y * s))
			* CFrame.Angles(0, 0, math.rad(90))
		part.Parent = model
		return part
	end
	-- Box covering the half-space on the table side of the pocket (used to open the U).
	local function innerHalfBox(pocket, top: number, bottom: number): Part
		local ix, iy = -pocket.x, -pocket.y -- towards the table centre
		local len = math.sqrt(ix * ix + iy * iy)
		ix, iy = ix / len, iy / len
		local box = Instance.new("Part")
		box.Anchored = true
		box.CanCollide = false
		local depth = 40
		box.Size = Vector3.new(depth * s, (top - bottom + 2) * s, depth * s)
		local cx, cy = pocket.x + ix * depth / 2, pocket.y + iy * depth / 2
		-- Physics y is world -Z; a direction angle a in physics is +a about Y in world.
		box.CFrame = CFrame.new(origin + Vector3.new(cx * s, ((top + bottom) / 2) * s, -cy * s))
			* CFrame.Angles(0, math.atan2(iy, ix), 0)
		box.Parent = model
		return box
	end
	if cutOk then
		for _, pocket in geometry.pockets do
			local r = holeR[pocket.id]
			-- Leather U on the rail top around the outer half of the hole.
			local ringTop = frameTop + L.PocketRingHeightInches
			local ring = verticalCylinder(
				"PocketRing" .. pocket.id,
				pocket.x,
				pocket.y,
				ringTop,
				frameTop - 0.02,
				r + L.PocketRingWidthInches
			)
			subtract(ring, {
				verticalCylinder("Cut", pocket.x, pocket.y, ringTop + 1, frameTop - 1, r),
				innerHalfBox(pocket, ringTop, frameTop),
			})
			-- Leather lining of the outer hole wall, from just under the cloth up to the rail.
			local wallTop = frameTop + 0.01
			local wallBottom = surfaceY - 0.3
			local wall = verticalCylinder(
				"PocketWall" .. pocket.id,
				pocket.x,
				pocket.y,
				wallTop,
				wallBottom,
				r + 0.02
			)
			subtract(wall, {
				verticalCylinder(
					"Cut",
					pocket.x,
					pocket.y,
					wallTop + 1,
					wallBottom - 1,
					r - L.PocketWallThicknessInches
				),
				innerHalfBox(pocket, wallTop, wallBottom),
			})
			-- Full leather tube for the throat below the cloth, down to the shaft floor, so no
			-- bare wood shows inside the drop.
			local throatTop = wallBottom + 0.05
			local throatBottom = shaftBottom + 0.4
			local throat = verticalCylinder(
				"PocketThroat" .. pocket.id,
				pocket.x,
				pocket.y,
				throatTop,
				throatBottom,
				r + 0.02
			)
			subtract(throat, {
				verticalCylinder(
					"Cut",
					pocket.x,
					pocket.y,
					throatTop + 1,
					throatBottom - 1,
					r - L.PocketWallThicknessInches
				),
			})
		end
	end

	-- Shaft: a matte near-black cylinder well below the cloth so the hole reads as depth.
	for _, pocket in geometry.pockets do
		local r = holeR[pocket.id] - 0.05
		local top = if cutOk then shaftBottom + 0.5 else surfaceY + railH + 0.02
		local bottom = shaftBottom
		local shaft = verticalCylinder("Pocket" .. pocket.id, pocket.x, pocket.y, top, bottom, r)
		shaft.Material = material(L.ShaftMaterial)
		shaft.Color = color(L.ShaftColor)
	end

	-- Legs.
	local legH = frameBottom
	local legSize = Vector3.new(5 * s, legH * s, 5 * s)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			makePart(
				"Leg",
				legSize,
				origin
					+ Vector3.new(sx * (length / 2 - 8) * s, legH / 2 * s, sz * (width / 2 - 4) * s),
				L.FrameColor,
				L.FrameMaterial,
				model
			)
		end
	end

	-- Everything above was built around zero; put the finished table where it belongs.
	model:PivotTo(CFrame.new(p.x, p.y, p.z) * TableBuilder.yawCFrame(p))
	return model
end

return TableBuilder
