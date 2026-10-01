--!strict
-- CueStickBuilder: the drawn cue, in the shape of CueShape.pieces (the same shape CueClearance
-- keeps clear of the rails and the balls), painted as a catalog cue. It is always its own
-- length: the shooter's body reaches it, never an extension (ShooterStance).
--
-- The stick is a row of cylinder BANDS (CueArt.bands): each lies inside one shape piece, drawn
-- at that piece's diameter so the silhouette is always the shape's, and inside one segment of
-- the cue's style (Catalog.style: tip, ferrule, shaft, joint ring, forearm with its accent or
-- rainbow bands, ring, wrap, cap), so it has one colour. Every stick is built up front with as
-- many parts as the most banded catalog cue needs, and paint() only recolours, resizes and
-- places them (a plainer cue hides the spares): nothing is created or destroyed after build,
-- which is what lets Camera.fadeNear find a stick's parts once.
--
-- A cue with a template in ReplicatedStorage[Config.Cue.MeshSkinsFolder] (every cue with a
-- skin, CueSkins) is drawn instead from the shared cue mesh (assets/cue): the same outline as
-- the bands, with real detail and its SurfaceAppearance. build() makes one hidden MESH SLOT
-- next to the bands (a clone of a template's MeshPart; they share one mesh), and paint() shows
-- either the bands or the slot, giving the slot a clone of the cue's SurfaceAppearance (a
-- clone, because a game script cannot write a SurfaceAppearance's maps), so the promise above
-- holds for both. Without the folder (someone else's place file) a cue falls back to its
-- bands, with one warning. The skin's effects (aura, pieces, pulses) are CueSkinLook's.
--
-- Whose cue a stick shows: wear(model, player) paints it as that player's equipped cue (their
-- Config.Cue.EquippedAttribute) and repaints when it changes. Everyone sees the shooter's own.
--
-- The model's pivot is the tip, and the stick runs along the pivot's local +Z toward the butt:
-- frame() gives that tip CFrame for a shot, and the poser is handed the same CFrame, which is
-- what keeps the hands on the cue. The pitch is VISUAL ONLY (CueClearance): the shot is always
-- fired at Config.Cue.CueElevationDegrees.
--
-- Attributes on the model: Visible (the last setVisible), CueId (the catalog cue painted),
-- Mesh (true while the mesh slot, not the bands, draws it).
--
-- Loading (designer, 2026-10-01: a switched-in cue appears fully loaded, swapped in one frame,
-- never as the old cue being retextured): on the client, setLoader(CueAssets) makes paint() of
-- a cue whose look the renderer has not loaded yet keep the stick as it is and paint it the
-- moment the look is ready. Only for sticks that are not welded to anything (BackCue swaps a
-- back stick itself, once the cue is ready). Without a loader (the server, tests) paint is
-- immediate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local CueArt = require(script.Parent.CueArt)
local CueShape = require(script.Parent.CueShape)
local Catalog = require(script.Parent.Progression.Catalog)

local CueStickBuilder = {}

--- The cue's radius (studs) at a distance from the tip: the clearance envelope (CueShape).
CueStickBuilder.radiusAt = CueShape.radiusAt

export type Spin = { x: number, y: number }

-- The material each shape piece's look is drawn in; the colours come from the cue's style.
local MATERIALS: { [string]: Enum.Material } = {
	Tip = Enum.Material.SmoothPlastic,
	Shaft = Enum.Material.Wood,
	Butt = Enum.Material.Wood,
}

-- The shape, measured once: its pieces and where each ends as a share of the length.
local PIECES = CueShape.pieces(Config.Cue.CueLengthStuds)
local PIECE_ENDS: { number } = {}
for i, piece in PIECES do
	PIECE_ENDS[i] = piece.to / Config.Cue.CueLengthStuds
end

-- A hidden spare band: the smallest part Roblox allows, fully transparent.
local SPARE_SIZE = Vector3.new(1e-3, 1e-3, 1e-3)

-- Catalog id -> its bands, cut once per cue for the life of the client.
local layouts: { [string]: { CueArt.Band } } = {}

-- A catalog id for anything: a known id as it is, anything else (nil, a typo, an id a newer
-- server knows) the default cue.
local function known(cueId: any): string
	return if Catalog.exists(cueId) then cueId else Config.Cue.DefaultStyle
end

local function layout(cueId: string): { CueArt.Band }
	local bands = layouts[cueId]
	if bands == nil then
		bands = CueArt.bands(Catalog.style(cueId), PIECE_ENDS, Config.Cue.BandSnap)
		layouts[cueId] = bands
	end
	return bands
end

-- As many parts as the most banded catalog cue needs (the rainbow ones).
local BAND_PARTS = 1
for _, cue in Catalog.list() do
	BAND_PARTS = math.max(BAND_PARTS, #layout(cue.Id))
end

-- The mesh templates, found once (after the game's first replication, so a template is never
-- missed for loading late): catalog id -> the template's MeshPart and its offset from the
-- template's pivot (the tip). Only catalog cues count.
type Template = { part: MeshPart, offset: CFrame }
local templates: { [string]: Template }? = nil
local warned = false

local function meshTemplates(): { [string]: Template }
	if templates then
		return templates
	end
	local found: { [string]: Template } = {}
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	local folder = ReplicatedStorage:FindFirstChild(Config.Cue.MeshSkinsFolder)
	for _, model in if folder then folder:GetChildren() else {} do
		local part = if model:IsA("Model") then model.PrimaryPart else nil
		if part and part:IsA("MeshPart") and Catalog.exists(model.Name) then
			found[model.Name] =
				{ part = part, offset = model:GetPivot():ToObjectSpace(part.CFrame) }
		end
	end
	if folder == nil and not warned then
		warned = true
		warn(
			("CueStickBuilder: no ReplicatedStorage.%s; every cue is drawn with bands"):format(
				Config.Cue.MeshSkinsFolder
			)
		)
	end
	templates = found
	return found
end

-- Model -> its band parts in order, tip first, how many the painted cue uses, and its mesh
-- slot (nil when no template exists) with its size (display thickens it) and its offset from
-- the tip (the templates share one mesh, so one offset).
type Stick = {
	parts: { Part },
	used: number,
	mesh: MeshPart?,
	meshSize: Vector3?,
	meshOffset: CFrame,
	meshOn: boolean,
	meshSkin: string?, -- whose SurfaceAppearance the slot wears
	wanted: boolean, -- the last setVisible
	pending: string?, -- a cue waiting for its look to load before it is painted (the stick
	-- shows its current cue meanwhile)
}

-- The client's cue loader (CueAssets), or nil: paint() is then immediate.
export type Loader = {
	ready: (id: string) -> boolean,
	whenReady: (id: string, fn: () -> ()) -> (),
}
local loader: Loader? = nil
local sticks: { [Model]: Stick } = setmetatable({}, { __mode = "k" }) :: any

-- Model -> the player whose equipped cue it wears, and the listener that repaints it.
type Wearer = { player: Player, connection: RBXScriptConnection }
local wearers: { [Model]: Wearer } = {}

-- Cylinders lie along X; turned to lie along +Z, centred on their stretch of the stick.
local function along(zStart: number, length: number): CFrame
	return CFrame.new(0, 0, zStart + length / 2) * CFrame.Angles(0, math.rad(90), 0)
end

-- Show the used bands (or the mesh slot) for the model's Visible attribute; spares stay hidden
-- either way.
local function applyVisibility(model: Model)
	local stick = sticks[model]
	if stick == nil then
		return
	end
	local visible = stick.wanted
	if model:GetAttribute("Visible") ~= visible then
		model:SetAttribute("Visible", visible)
	end
	for i, part in stick.parts do
		part.Transparency = if visible and i <= stick.used then 0 else 1
	end
	if stick.mesh then
		stick.mesh.Transparency = if visible and stick.meshOn then 0 else 1
	end
end

--- The catalog id of the cue `player` has equipped: their Config.Cue.EquippedAttribute when it
--- names a catalog cue, the default cue otherwise (nil player, not loaded yet, unknown id).
function CueStickBuilder.equippedCue(player: Player?): string
	return known(if player then player:GetAttribute(Config.Cue.EquippedAttribute) else nil)
end

-- Paint a stick's bands, or (`bandsOnly` false and a template exists) its mesh slot.
local function paintStick(model: Model, id: string, bandsOnly: boolean)
	local stick = sticks[model]
	local L = Config.Cue.CueLengthStuds
	-- Placed from the stick's pivot, so a stick repainted mid-shot stays where it is drawn.
	local pivot = model:GetPivot()
	local template = if bandsOnly or stick.mesh == nil then nil else meshTemplates()[id]
	stick.meshOn = template ~= nil
	model:SetAttribute("Mesh", stick.meshOn)
	if stick.mesh then
		local mesh = stick.mesh :: MeshPart
		-- Every mesh skin shares one mesh, so a slot only ever needs its SurfaceAppearance
		-- changed: a clone of the template's. That creates no part, so Camera.fadeNear's
		-- cached list stays right.
		if template and stick.meshSkin ~= id then
			for _, child in mesh:GetChildren() do
				if child:IsA("SurfaceAppearance") then
					child:Destroy()
				end
			end
			local look = template.part:FindFirstChildOfClass("SurfaceAppearance")
			if look then
				look:Clone().Parent = mesh
			end
			stick.meshSkin = id
		end
		mesh.CFrame = pivot * stick.meshOffset
		mesh.CastShadow = template ~= nil
	end
	local bands = if template then {} else layout(id)
	for i, part in stick.parts do
		local band = bands[i]
		if band then
			local piece = PIECES[band.piece]
			local length = (band.to - band.from) * L
			part.Size = Vector3.new(math.max(length, 1e-3), piece.diameter, piece.diameter)
			part.CFrame = pivot * along(band.from * L, length)
			part.Color = Color3.fromRGB(band.color[1], band.color[2], band.color[3])
			part.Material = MATERIALS[piece.look] or Enum.Material.Wood
			part.CastShadow = true
		else
			part.Size = SPARE_SIZE
			part.CFrame = pivot
			part.CastShadow = false
		end
	end
	stick.used = math.min(#bands, #stick.parts)
	applyVisibility(model)
end

--- Paint a built stick as catalog cue `cueId` (unknown or nil: the default cue): from its mesh
--- template when it has one (ReplicatedStorage[Config.Cue.MeshSkinsFolder]), with bands
--- otherwise. Nothing happens when
--- it already shows that cue, so it is safe to call whenever a cue may have changed; it never
--- creates a part.
function CueStickBuilder.paint(model: Model, cueId: string?)
	local stick = sticks[model]
	local id = known(cueId)
	if stick == nil then
		return
	end
	if model:GetAttribute("CueId") == id then
		stick.pending = nil -- already wears it (and so holds its look loaded)
		return
	end
	if loader and not loader.ready(id) then
		-- Keeps its current cue until the renderer has loaded this one, then swaps in one frame
		-- (a newer paint wins).
		if stick.pending ~= id then
			stick.pending = id
			loader.whenReady(id, function()
				if sticks[model] == stick and stick.pending == id then
					stick.pending = nil
					CueStickBuilder.paint(model, id)
				end
			end)
		end
		return
	end
	stick.pending = nil
	model:SetAttribute("CueId", id)
	paintStick(model, id, false)
end

--- Client only: paint a new cue only once the renderer has loaded its look (CueAssets).
function CueStickBuilder.setLoader(l: Loader)
	loader = l
end

--- True while the stick waits for its new cue's look to load.
function CueStickBuilder.loading(model: Model): boolean
	local stick = sticks[model]
	return stick ~= nil and stick.pending ~= nil
end

--- Lay the stick's parts out again from the model's pivot, as its current cue: for a stick whose
--- parts were moved some other way (BackCue welds them to a body, and sets the pivot back
--- before letting go). Creates nothing.
function CueStickBuilder.relayout(model: Model)
	local id = model:GetAttribute("CueId")
	if sticks[model] and type(id) == "string" then
		paintStick(model, id, false)
	end
end

--- Paint the stick as `player`'s equipped cue and keep it so, repainting whenever their
--- EquippedCue changes, until it is handed to someone else. Calling it again for the same
--- player does nothing; nil paints the default cue and stops listening.
function CueStickBuilder.wear(model: Model, player: Player?)
	local wearer = wearers[model]
	if wearer and wearer.player == player then
		return
	end
	if wearer then
		wearer.connection:Disconnect()
		wearers[model] = nil
	end
	if player then
		local connection = player
			:GetAttributeChangedSignal(Config.Cue.EquippedAttribute)
			:Connect(function()
				CueStickBuilder.paint(model, CueStickBuilder.equippedCue(player))
			end)
		wearers[model] = { player = player, connection = connection }
	end
	CueStickBuilder.paint(model, CueStickBuilder.equippedCue(player))
end

--- A stick, painted as catalog cue `cueId` (default: the default cue), visible.
function CueStickBuilder.build(parent: Instance, cueId: string?): Model
	local model = Instance.new("Model")
	model.Name = "CueStick"
	local parts: { Part } = table.create(BAND_PARTS)
	for i = 1, BAND_PARTS do
		local part = Instance.new("Part")
		part.Name = ("Band%02d"):format(i)
		part.Shape = Enum.PartType.Cylinder
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Size = SPARE_SIZE
		part.Transparency = 1
		part.Parent = model
		parts[i] = part
	end
	-- The mesh slot: a clone of a template's MeshPart (they share one mesh; the default cue's
	-- when it has one), hidden until a mesh cue is painted.
	local mesh: MeshPart? = nil
	local meshOffset = CFrame.identity
	local all = meshTemplates()
	local ids = {}
	for id in all do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		return (a == Config.Cue.DefaultStyle) or (b ~= Config.Cue.DefaultStyle and a < b)
	end)
	for _, id in ids do
		local template = all[id]
		if template then
			local slot = template.part:Clone()
			slot.Name = "Mesh"
			slot.Anchored = true
			slot.CanCollide = false
			slot.CanQuery = false
			slot.CanTouch = false
			slot.Transparency = 1
			slot.CFrame = template.offset
			slot.Parent = model
			for _, child in slot:GetChildren() do
				if not child:IsA("SurfaceAppearance") then
					child:Destroy() -- a template's Frames folder stays with the template
				end
			end
			mesh = slot
			meshOffset = template.offset
			break
		end
	end
	sticks[model] = {
		parts = parts,
		used = 0,
		mesh = mesh,
		meshSize = if mesh then mesh.Size else nil,
		meshOffset = meshOffset,
		meshOn = false,
		meshSkin = if mesh then ids[1] else nil,
		wanted = true,
		pending = nil,
	}
	model.WorldPivot = CFrame.new(0, 0, 0)
	model:SetAttribute("Visible", true)
	CueStickBuilder.paint(model, cueId)
	model.Parent = parent
	return model
end

--- A stick for a picture (the Index's turning cue, CueViewport): as build(), `thickness` times
--- as thick so it reads at a small size, and never repainted (paint would undo the
--- thickness). `silhouette` paints every band in that one colour, smooth plastic: the cue's
--- shape with nothing of its look (always the bands: the same outline).
function CueStickBuilder.display(
	parent: Instance,
	cueId: string?,
	thickness: number,
	silhouette: Color3?
): Model
	local model = CueStickBuilder.build(parent, cueId)
	local stick = sticks[model]
	if silhouette and stick.meshOn then
		paintStick(model, known(cueId), true)
	end
	if stick.meshOn and stick.mesh then
		local mesh = stick.mesh :: MeshPart
		local size = stick.meshSize :: Vector3
		-- Thicker across, the same length; the slot is centred on the cue's axis, so its
		-- placement along the cue does not change.
		mesh.Size = Vector3.new(size.X * thickness, size.Y * thickness, size.Z)
		mesh.CastShadow = false
	end
	for i, part in stick.parts do
		if i <= stick.used then
			part.Size = Vector3.new(part.Size.X, part.Size.Y * thickness, part.Size.Z * thickness)
			part.CastShadow = false
			if silhouette then
				part.Color = silhouette
				part.Material = Enum.Material.SmoothPlastic
			end
		end
	end
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
	local stick = sticks[model]
	if stick == nil or stick.wanted == visible then
		return
	end
	stick.wanted = visible
	applyVisibility(model)
end

return CueStickBuilder
