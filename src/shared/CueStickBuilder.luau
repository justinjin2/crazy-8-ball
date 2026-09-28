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
-- Whose cue a stick shows: wear(model, player) paints it as that player's equipped cue (their
-- Config.Cue.EquippedAttribute) and repaints when it changes. Everyone sees the shooter's own.
--
-- The model's pivot is the tip, and the stick runs along the pivot's local +Z toward the butt:
-- frame() gives that tip CFrame for a shot, and the poser is handed the same CFrame, which is
-- what keeps the hands on the cue. The pitch is VISUAL ONLY (CueClearance): the shot is always
-- fired at Config.Cue.CueElevationDegrees.
--
-- Attributes on the model: Visible (the last setVisible), CueId (the catalog cue painted).

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

-- Model -> its band parts in order, tip first, and how many the painted cue uses.
type Stick = { parts: { Part }, used: number }
local sticks: { [Model]: Stick } = setmetatable({}, { __mode = "k" }) :: any

-- Model -> the player whose equipped cue it wears, and the listener that repaints it.
type Wearer = { player: Player, connection: RBXScriptConnection }
local wearers: { [Model]: Wearer } = {}

-- Cylinders lie along X; turned to lie along +Z, centred on their stretch of the stick.
local function along(zStart: number, length: number): CFrame
	return CFrame.new(0, 0, zStart + length / 2) * CFrame.Angles(0, math.rad(90), 0)
end

-- Show the used bands for the model's Visible attribute; spares stay hidden either way.
local function applyVisibility(model: Model)
	local stick = sticks[model]
	if stick == nil then
		return
	end
	local visible = model:GetAttribute("Visible") == true
	for i, part in stick.parts do
		part.Transparency = if visible and i <= stick.used then 0 else 1
	end
end

--- The catalog id of the cue `player` has equipped: their Config.Cue.EquippedAttribute when it
--- names a catalog cue, the default cue otherwise (nil player, not loaded yet, unknown id).
function CueStickBuilder.equippedCue(player: Player?): string
	return known(if player then player:GetAttribute(Config.Cue.EquippedAttribute) else nil)
end

--- Paint a built stick as catalog cue `cueId` (unknown or nil: the default cue). Nothing
--- happens when it already shows that cue, so it is safe to call whenever a cue may have
--- changed; it never creates a part.
function CueStickBuilder.paint(model: Model, cueId: string?)
	local stick = sticks[model]
	local id = known(cueId)
	if stick == nil or model:GetAttribute("CueId") == id then
		return
	end
	model:SetAttribute("CueId", id)
	local bands = layout(id)
	local L = Config.Cue.CueLengthStuds
	-- Placed from the stick's pivot, so a stick repainted mid-shot stays where it is drawn.
	local pivot = model:GetPivot()
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
	sticks[model] = { parts = parts, used = 0 }
	model.WorldPivot = CFrame.new(0, 0, 0)
	model:SetAttribute("Visible", true)
	CueStickBuilder.paint(model, cueId)
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
