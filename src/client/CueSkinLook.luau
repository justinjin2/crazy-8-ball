--!strict
-- CueSkinLook: a cue skin's effects on a stick (CueStickBuilder), built from its CueSkins row:
-- the surface's pulses and frame swaps, the moving material (overlay Beams), the aura
-- (ParticleEmitters on their hosts, Beams, Orbiters, lightning Arcs, PointLights) and the 3D
-- piece (CuePiece). The rows follow the Blender preview (assets/cue/CueVfx.py), which the review
-- clips show; docs/ARCHITECTURE.md has the mapping.
--
-- attach(stick, opts) follows the stick: its CueId attribute rebuilds the look, its Visible
-- attribute switches it on and off, its mesh's camera fade carries over to the piece. The
-- designer's rules (2026-10-01, replacing "no aura in the hands" of 2026-09-30):
--   * the full aura shows everywhere (opts.aura): in the hands while aiming and on the back;
--   * on the back (opts.back) its emitters run at Config.CueSkins.BackRateScale and only its
--     torso-sized camera-facing sprites are drawn behind the body;
--   * a cue with an aura wears a faint outline of its colour (Config.CueSkins.Outline) and a
--     skin's Aura.Highlight softly outlines its piece (the dragon, the fox), on the cues
--     nearest the camera;
--   * every cue wears a solid outline in its theme colour (Config.CueSkins.Pop.Outline), with
--     close-range ribbons where Roblox's Highlight outline thins away (buildInk); a cue whose
--     aura pops (Pop.Ids) is built from its row rewritten by CueSkins.Pop;
--   * the aura stays on the cue as it moves: emitters are LockedToPart but for tiny specks,
--     and an orbiter's ribbon shortens while the stick moves (Config.CueSkins.Drift);
--   * the stick's AuraOff attribute turns the whole aura off at once (the raised hand cue,
--     Config.Cue.RaisedCueFade); the stick and its piece stay;
--   * the stick's AuraQuiet attribute (AuraQuiet: in a match, the shooter's cue and, on your
--     turn, every cue at your table) eases the aura down to its tier's Config.CueSkins.Quiet
--     share: emitter rates, aura beams and lights;
--   * the engulfing aura round the carrying player (the skin's Carrier piece and its
--     Carrier-host emitters) is all or nothing: gone while the stick is AuraQuiet or
--     CarrierQuiet (AuraQuiet: a shot in flight at the owner's table), back between shots.
--
-- Emitters, Beams and Lights live on Attachments in the stick's mesh; the look's own parts (a
-- Part host, a joint rider, the piece) sit in a Model next to the stick, welded to the mesh,
-- unanchored and massless: BackCue welds every part INSIDE a stick to the body, which would
-- stop a piece's joints. One RenderStepped steps every live look near the camera.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CueShape = require(Shared:WaitForChild("CueShape"))
local CueSkins = require(Shared:WaitForChild("CueSkins"))
local Motion = require(Shared:WaitForChild("CueSkins"):WaitForChild("Motion"))
local Pop = require(Shared:WaitForChild("CueSkins"):WaitForChild("Pop"))
local Catalog = require(Shared:WaitForChild("Progression"):WaitForChild("Catalog"))
local Textures = require(Shared:WaitForChild("CueSkins"):WaitForChild("Textures"))
local CuePiece = require(script.Parent.CuePiece)
local CueVfx = require(script.Parent.CueVfx)

local C = Config.CueSkins

local CueSkinLook = {}
CueSkinLook.__index = CueSkinLook

export type Opts = {
	aura: boolean, -- the aura shows (every stick today)
	back: boolean?, -- worn on a back: BackRateScale and the behind-the-body push
}

-- The carrier (designer, 2026-10-04: a Secret's aura engulfs the player too): a stick worn on a
-- back carries an ObjectValue "Carrier" naming the character (BackCue sets it). A skin row's
-- Carrier piece is built on that character's root, and aura rows with Host.Kind "Carrier" put
-- their emitter on a part welded to it. Both go when the stick is quiet (a match) or hidden.
local CARRIER_VALUE = "Carrier"

type DynBeam = {
	beam: Beam,
	a0: Attachment,
	a1: Attachment,
	row: any,
	base0: Vector3,
	base1: Vector3,
	transparency: { any }?,
	aura: boolean, -- dimmed by the quiet share
}
type Orbiter = {
	row: any,
	a: Attachment,
	b: Attachment,
	head: ParticleEmitter?,
	trail: Trail,
	lap: number,
}
type Arc = {
	row: any,
	strands: { { atts: { Attachment }, beams: { Beam } } },
	slot: number,
	shown: boolean,
}
type Light = { light: PointLight, row: any }

export type Look = typeof(setmetatable(
	{} :: {
		stick: Model,
		opts: Opts,
		cueId: string?,
		row: any,
		mesh: MeshPart?,
		folder: Model?, -- the look's own parts
		built: { Instance }, -- everything to destroy on rebuild
		emitters: { { e: ParticleEmitter, aura: boolean, rate: number, carrier: boolean } }, -- rate: unquieted; carrier: a Carrier host
		beams: { { b: Beam, aura: boolean } },
		dynBeams: { DynBeam },
		orbiters: { Orbiter },
		arcs: { Arc },
		lights: { Light },
		sound: { s: Sound, volume: number }?, -- the aura's sound (Aura.Sound), volume unquieted
		piece: any?,
		carrierPiece: any?, -- the skin's Carrier piece on the carrying character (backs only)
		carrierOn: boolean, -- the engulfing aura is drawn (see carrierShown)
		highlights: { Highlight }, -- the stick's outline and the piece's (nearest cues only)
		inks: { Beam }, -- the stick's close-range outline (buildInk)
		inkShown: boolean?, -- the inks are drawn now (step)
		palette: { string }?, -- a Legendary-and-above stick's moving outline (CueSkins.Pop.palette)
		outline: Highlight?, -- the stick's own outline, recoloured as the palette moves
		frames: { SurfaceAppearance }, -- frame 0 is the stick's own SurfaceAppearance
		frame: number,
		t0: number,
		visible: boolean,
		aura: boolean, -- visible and not AuraOff: the aura is drawn
		pending: boolean, -- a rebuild waits for the stick's repaint to finish
		share: number, -- the aura's strength now: 1 full, its Quiet share when quiet
		lastT: number?, -- the last step's time and the mesh's place then (the speed)
		lastAt: Vector3?,
		speed: number, -- the stick's eased speed, studs per second
		connections: { RBXScriptConnection },
	},
	CueSkinLook
))

local live: { [Look]: boolean } = {}
-- Seen closer than this to straight down the stick, its ink is off (Outline.Ink).
local inkEndOnCos = math.cos(math.rad(C.Pop.Outline.Ink.MinViewDegrees))
-- Popped skin rows (CueSkins.Pop), made once per cue.
local poppedRows: { [string]: any } = {}

local function texture(id: any, role: string): string
	return if type(id) == "string" and id ~= "" then id else (Textures :: any)[role] or ""
end

local function attachment(parent: Instance, position: Vector3, name: string): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = position
	a.Parent = parent
	return a
end

local function hostPart(name: string, size: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Transparency = 1
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

local function weldTo(part: BasePart, root: BasePart, c0: CFrame)
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = part
	weld.C0 = c0
	weld.Parent = part
end

--- Look for a stick: built now and kept in step with it until destroy().
function CueSkinLook.attach(stick: Model, opts: Opts): Look
	local self = setmetatable({
		stick = stick,
		opts = opts,
		cueId = nil,
		row = nil,
		mesh = nil,
		folder = nil,
		built = {},
		emitters = {},
		beams = {},
		dynBeams = {},
		orbiters = {},
		arcs = {},
		lights = {},
		sound = nil,
		piece = nil,
		carrierPiece = nil,
		carrierOn = true,
		highlights = {},
		inks = {},
		frames = {},
		frame = 0,
		t0 = os.clock(),
		visible = false,
		aura = false,
		pending = false,
		share = 1,
		lastT = nil,
		lastAt = nil,
		speed = 0,
		connections = {},
	}, CueSkinLook)
	table.insert(
		self.connections,
		stick:GetAttributeChangedSignal("CueId"):Connect(function()
			self:refreshSoon()
		end)
	)
	table.insert(
		self.connections,
		stick:GetAttributeChangedSignal("Visible"):Connect(function()
			self:applyVisible()
		end)
	)
	table.insert(
		self.connections,
		stick:GetAttributeChangedSignal("AuraOff"):Connect(function()
			self:applyVisible()
		end)
	)
	table.insert(
		self.connections,
		stick:GetAttributeChangedSignal("Mesh"):Connect(function()
			self:refreshSoon()
		end)
	)
	-- The carrier changes (BackCue): rebuild, so the Carrier piece and hosts follow the body.
	table.insert(
		self.connections,
		stick.ChildAdded:Connect(function(child: Instance)
			if child.Name == CARRIER_VALUE and child:IsA("ObjectValue") then
				table.insert(
					self.connections,
					child.Changed:Connect(function()
						self:refreshSoon()
					end)
				)
				self:refreshSoon()
			end
		end)
	)
	local carrier = stick:FindFirstChild(CARRIER_VALUE)
	if carrier and carrier:IsA("ObjectValue") then
		table.insert(
			self.connections,
			carrier.Changed:Connect(function()
				self:refreshSoon()
			end)
		)
	end
	live[self] = true
	self:refresh()
	return self
end

-- Rebuild once the stick's repaint is over (CueId and Mesh change one after the other, and
-- the SurfaceAppearance is swapped after them).
function CueSkinLook.refreshSoon(self: Look)
	if self.pending then
		return
	end
	self.pending = true
	task.defer(function()
		self.pending = false
		if live[self] then
			self:refresh()
		end
	end)
end

-- Take the current look apart. The stick's own SurfaceAppearance (frame 1) goes back on the
-- mesh while the stick still shows this cue; once it was repainted, CueStickBuilder has
-- already put the new cue's on, and every frame left over is dropped.
function CueSkinLook.clear(self: Look)
	if self.piece then
		self.piece:destroy()
		self.piece = nil
	end
	if self.carrierPiece then
		self.carrierPiece:destroy()
		self.carrierPiece = nil
	end
	local mesh = self.mesh
	local same = mesh ~= nil
		and self.stick:GetAttribute("CueId") == self.cueId
		and self.stick:GetAttribute("Mesh") == true
	for i, sa in self.frames do
		if i == 1 and same then
			sa.Parent = mesh
		elseif i > 1 or sa.Parent ~= mesh then
			sa:Destroy()
		end
	end
	self.frames = {}
	self.frame = 0
	for _, inst in self.built do
		inst:Destroy()
	end
	self.built = {}
	self.emitters = {}
	self.beams = {}
	self.dynBeams = {}
	self.orbiters = {}
	self.arcs = {}
	self.lights = {}
	self.sound = nil -- its attachment was in `built`
	self.highlights = {} -- they live in the folder
	self.inks = {} -- in `built`
	self.inkShown = nil
	self.palette = nil
	self.outline = nil
	if self.folder then
		self.folder:Destroy()
		self.folder = nil
	end
	self.row = nil
	self.visible = false -- a rebuilt look appears anew (its aura prefilled, applyVisible)
end

--- Rebuild for the stick's current cue (nothing happens if it is the one built).
function CueSkinLook.refresh(self: Look)
	local id = self.stick:GetAttribute("CueId")
	local meshOn = self.stick:GetAttribute("Mesh") == true
	local key = if meshOn and type(id) == "string" then id else nil
	if key == self.cueId and self.row ~= nil then
		return
	end
	self:clear()
	self.cueId = key
	local row = if key then CueSkins.get(key) else nil
	local popped = row ~= nil and Pop.applies(row.CatalogId, C.Pop)
	-- The solid theme outline: every cue (Config.CueSkins.Pop.Outline.Every), or the popped.
	local inked = row ~= nil and (C.Pop.Outline.Every or popped)
	if popped then
		poppedRows[key :: string] = poppedRows[key :: string] or Pop.pop(row, C.Pop)
		row = poppedRows[key :: string]
	end
	local mesh = self.stick:FindFirstChild("Mesh")
	if row == nil or mesh == nil or not mesh:IsA("MeshPart") then
		return
	end
	self.row = row
	self.mesh = mesh
	self.share = self:quietTarget() -- a cue built while quiet starts quiet
	local folder = Instance.new("Model")
	folder.Name = "CueLook"
	folder.Parent = self.stick.Parent
	self.folder = folder
	self.t0 = os.clock()
	self:buildSurface(row, popped)
	if row.Piece then
		self.piece = CuePiece.new(row.Piece, mesh, folder)
	end
	local carrierRoot = self:carrierRoot()
	if row.Carrier and carrierRoot and self.opts.aura then
		self.carrierPiece = CuePiece.new(row.Carrier, carrierRoot, folder, self:carrierLift())
	end
	local moving = row.Moving or {}
	for _, b in moving.Beams or {} do
		self:buildBeam(b, false)
	end
	for _, e in moving.Emitters or {} do
		self:buildEmitter(e, false)
	end
	local aura = row.Aura
	if aura and self.opts.aura then
		for _, e in aura.Emitters or {} do
			self:buildEmitter(e, true)
		end
		for _, b in aura.Beams or {} do
			self:buildBeam(b, true)
		end
		for _, o in aura.Orbiters or {} do
			self:buildOrbiter(o)
		end
		for _, a in aura.Arcs or {} do
			self:buildArc(a)
		end
		for _, l in aura.Lights or {} do
			local att = attachment(mesh, CueVfx.onCue(l.AtStuds or 5), "Light")
			local light = Instance.new("PointLight")
			light.Color = CueVfx.color(l.Color or "#FFFFFF")
			light.Brightness = l.Brightness or 1
			light.Range = l.Range or 6
			light.Shadows = false
			light.Parent = att
			table.insert(self.built, att)
			table.insert(self.lights, { light = light, row = l })
		end
		if aura.Sound then
			self:buildSound(aura.Sound)
		end
		-- The stick's faint outline in its colour (the solid theme one is built below), and
		-- the piece's own (Aura.Highlight).
		local O = C.Outline
		local color = aura.Outline or O.Colors[row.Tier]
		if color and not inked then
			self:addHighlight("CueOutline", self.stick, {
				FillColor = color,
				FillTransparency = O.FillTransparency,
				OutlineColor = color,
				OutlineTransparency = O.OutlineTransparency,
			})
		end
		if aura.Highlight and self.piece then
			local hl = aura.Highlight
			self:addHighlight("PieceHighlight", self.piece.model, {
				FillColor = hl.FillColor,
				FillTransparency = math.max(hl.FillTransparency or 0.6, O.PieceFillTransparencyMin),
				OutlineColor = hl.OutlineColor,
				OutlineTransparency = math.max(
					hl.OutlineTransparency or 0,
					O.PieceOutlineTransparencyMin
				),
			})
		end
	end
	-- The solid outline in the cue's theme colour, aura or not (CueSkins.Pop): thinner and
	-- fainter on the lower rarities (Outline.ByRarity).
	if inked and self.opts.aura then
		local O = C.Pop.Outline
		local level = Pop.level(Catalog.get(row.CatalogId), row)
		local tier = O.ByRarity[level] or {}
		local color = Pop.outline(row, C.Pop)
		self:addHighlight("CueOutline", self.stick, {
			FillColor = color,
			FillTransparency = C.Outline.FillTransparency,
			OutlineColor = color,
			OutlineTransparency = tier.Transparency or O.Transparency,
		})
		self.outline = self.highlights[#self.highlights]
		self.palette = Pop.palette(row, C.Pop, level)
		self:buildInk(color, O.Ink.LineStuds * (tier.LineScale or 1))
	end
	if self.piece then
		self.piece:setAura(self.opts.aura)
	end
	self.carrierOn = self:carrierShown()
	if self.carrierPiece then
		self.carrierPiece:setAura(self.carrierOn)
	end
	self:applyVisible()
	self:step(0)
end

-- A Highlight on `adornee`, off until the shared budget turns it on (the RenderStepped below).
function CueSkinLook.addHighlight(self: Look, name: string, adornee: Instance, hl: any)
	local h = Instance.new("Highlight")
	h.Name = name
	h.FillColor = CueVfx.color(hl.FillColor or "#FFFFFF")
	h.FillTransparency = hl.FillTransparency or 0.6
	h.OutlineColor = CueVfx.color(hl.OutlineColor or "#FFFFFF")
	h.OutlineTransparency = hl.OutlineTransparency or 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Enabled = false
	h.Adornee = adornee
	h.Parent = self.folder
	table.insert(self.highlights, h)
end

-- A stick's close-range outline (Config.CueSkins.Pop.Outline.Ink). Roblox thins a
-- Highlight's outline as the camera nears it, to nothing at the aiming distance, so the stick
-- also carries camera-facing ribbons along its axis, `line` studs wider than the cue each side:
-- the opaque cue hides their middle and a rim of colour shows at its edges, a real 3D line
-- (thicker near, thinner far). step turns them off when they cannot work (a faded stick, an
-- end-on view).
function CueSkinLook.buildInk(self: Look, color: string, line: number)
	local I = C.Pop.Outline.Ink
	local mesh = self.mesh :: MeshPart
	local length = 2 * CueVfx.onCue(0).Z -- the tip sits at Z = length / 2
	-- Where the pieces meet, from the tip: a short end piece at each end that narrows to the
	-- bare cue (a square end would stick out past the rounded tip and butt), Pieces between.
	local cuts = { 0 }
	for k = 0, I.Pieces do
		table.insert(cuts, I.EndStuds + (length - 2 * I.EndStuds) * k / I.Pieces)
	end
	table.insert(cuts, length)
	local function width(at: number): number
		local edge = at <= 0 or at >= length
		return 2 * (CueShape.radiusAt(at) + (if edge then 0 else line))
	end
	for i = 1, #cuts - 1 do
		local from, to = cuts[i], cuts[i + 1]
		local a0 = attachment(mesh, CueVfx.onCue(from), "Ink" .. i .. "A")
		local a1 = attachment(mesh, CueVfx.onCue(to), "Ink" .. i .. "B")
		local beam = Instance.new("Beam")
		beam.Name = "Ink"
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = width(from)
		beam.Width1 = width(to)
		beam.Segments = 1
		beam.FaceCamera = true
		beam.Texture = ""
		beam.Color = ColorSequence.new(CueVfx.color(color))
		beam.Transparency = NumberSequence.new(0)
		beam.LightEmission = 0
		beam.LightInfluence = 0
		beam.Enabled = false
		beam.Parent = mesh
		table.insert(self.built, a0)
		table.insert(self.built, a1)
		table.insert(self.built, beam)
		table.insert(self.inks, beam)
	end
end

-- The surface: the frames a Legendary swaps through (clones of its template's extra
-- SurfaceAppearances), and its colour; a popped row's raised emissive (CueSkins.Pop).
function CueSkinLook.buildSurface(self: Look, row: any, popped: boolean)
	local mesh = self.mesh :: MeshPart
	local base = mesh:FindFirstChildOfClass("SurfaceAppearance")
	if base == nil then
		return
	end
	local surface = row.Surface or {}
	if surface.Color then
		base.Color = CueVfx.color(surface.Color)
	end
	if popped and surface.EmissiveStrength then
		base.EmissiveStrength = surface.EmissiveStrength
	end
	self.frames = { base }
	if row.Frames then
		local folder = ReplicatedStorage:FindFirstChild(Config.Cue.MeshSkinsFolder)
		local template = folder and folder:FindFirstChild(self.cueId :: string)
		local frames = template and template:FindFirstChild("Frames")
		for i = 1, #row.Frames.Maps - 1 do
			local sa = frames and frames:FindFirstChild("F" .. i)
			if sa and sa:IsA("SurfaceAppearance") then
				local copy = sa:Clone()
				if surface.Color then
					copy.Color = base.Color
				end
				table.insert(self.frames, copy)
			end
		end
	end
end

--- How far up the carrying body's head top sits from where the Carrier piece and hosts were
--- modelled (Config.CueSkins.Carrier.HeadTopStuds above the root): a tall avatar wears them
--- higher, a short one lower. 0 with no carrier or no Head.
function CueSkinLook.carrierLift(self: Look): number
	local root = self:carrierRoot()
	local character = if root then root.Parent else nil
	local head = if character then character:FindFirstChild("Head") else nil
	if root == nil or head == nil or not head:IsA("BasePart") then
		return 0
	end
	local top = root.CFrame:PointToObjectSpace(head.Position).Y + head.Size.Y / 2
	return top - C.Carrier.HeadTopStuds
end

--- The carrying character's root part (a stick on a back with its Carrier value set), else nil.
function CueSkinLook.carrierRoot(self: Look): BasePart?
	local v = self.stick:FindFirstChild(CARRIER_VALUE)
	local character = if v and v:IsA("ObjectValue") then v.Value else nil
	if character == nil or not character:IsA("Model") then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- A host for an emitter row: an Attachment on the cue, or a Part welded to the mesh (or riding
-- a piece joint), or a Part welded to the carrying character ("Carrier": Size and Offset in
-- the character's frame, x right, y up, z back; nil when the stick has no carrier). Returns
-- the emitter's parent and its frame for EmissionDirection.
function CueSkinLook.host(self: Look, row: any): (Instance?, string)
	local h = row.Host or { Kind = "Attachment", AtStuds = 5.5 }
	local kind = h.Kind or "Attachment"
	local folder = self.folder :: Model
	if kind == "Carrier" then
		local root = self:carrierRoot()
		if root == nil then
			return nil, "part"
		end
		local size = h.Size or { 4, 4, 4 }
		local o = h.Offset or { 0, 0, 0 }
		local part = hostPart(row.Name or "Carrier", Vector3.new(size[1], size[2], size[3]))
		part.Parent = folder
		weldTo(part, root, CFrame.new(o[1], o[2] + self:carrierLift(), o[3]))
		table.insert(self.built, part)
		return part, "part"
	elseif kind == "Part" then
		local from, to = h.FromStuds or 3.8, h.ToStuds or 6.9
		local width = h.Width or 0.3
		local part =
			hostPart(row.Name or "Host", Vector3.new(width, math.max(to - from, 0.05), width))
		-- Laid along the cue: the part's +Y toward the tip (CueVfx's "part" directions).
		local rest = CFrame.new(CueVfx.onCue((from + to) / 2, h.Up, h.Side))
			* CFrame.Angles(math.rad(90), 0, 0)
		part.Parent = folder
		self:place(part, rest, h.Joint)
		return part, "part"
	elseif kind == "Segment" then
		local a = CueVfx.onCue(h.From[1], h.From[2], h.From[3])
		local b = CueVfx.onCue(h.To[1], h.To[2], h.To[3])
		local r = h.Radius or 0
		local length = (b - a).Magnitude
		local part =
			hostPart(row.Name or "Segment", Vector3.new(2 * r + 0.01, 2 * r + 0.01, length + 2 * r))
		local rest = CFrame.lookAt((a + b) / 2, b)
		part.Parent = folder
		self:place(part, rest, h.Joint)
		return part, "cue"
	elseif kind == "Point" then
		local o = h.Offset or { 0, 0, 0 }
		local size = h.Size or 0
		local at = Vector3.new(o[1], o[2], o[3])
		if size > 0 then
			local part = hostPart(row.Name or "Point", Vector3.new(size, 0.01, size))
			part.Parent = folder
			self:place(part, CFrame.new(at), h.Joint)
			return part, "cue"
		end
		return self:pointAttachment(at, h.Joint, row.Name or "Point"), "cue"
	end
	return self:pointAttachment(
		CueVfx.onCue(h.AtStuds or 0, h.Up, h.Side),
		h.Joint,
		row.Name or "At"
	),
		"cue"
end

-- An Attachment at a point of the cue frame: on the mesh, or on a small rider when it follows
-- a piece joint.
function CueSkinLook.pointAttachment(
	self: Look,
	at: Vector3,
	joint: string?,
	name: string
): Attachment
	local mesh = self.mesh :: MeshPart
	if joint and self.piece then
		local part = hostPart(name, Vector3.new(0.05, 0.05, 0.05))
		part.Parent = self.folder
		self:place(part, CFrame.new(at), joint)
		return attachment(part, Vector3.zero, name)
	end
	local a = attachment(mesh, at, name)
	table.insert(self.built, a)
	return a
end

-- Weld a look part at `rest` in the cue frame, riding `joint` when the piece has it.
function CueSkinLook.place(self: Look, part: BasePart, rest: CFrame, joint: string?)
	local mesh = self.mesh :: MeshPart
	if joint and self.piece then
		self.piece:ride(part, joint, rest, mesh)
	else
		weldTo(part, mesh, rest)
	end
end

--- The aura's sound (Config.CueSkins.Sound): a looping Sound on the cue, playing while the
--- aura shows (applyVisible), its volume following the quiet share (ease).
function CueSkinLook.buildSound(self: Look, row: any)
	local S = C.Sound
	local mesh = self.mesh :: MeshPart
	local att = attachment(mesh, CueVfx.onCue(row.AtStuds or S.AtStuds), "AuraSound")
	table.insert(self.built, att)
	local sound = Instance.new("Sound")
	sound.Name = "AuraSound"
	sound.SoundId = row.Asset or ""
	sound.Looped = row.Looped ~= false
	sound.Volume = (row.Volume or 0.1) * self.share
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = row.RollOffMinStuds or S.RollOffMinStuds
	sound.RollOffMaxDistance = row.RollOffMaxStuds or S.RollOffMaxStuds
	sound.Parent = att
	self.sound = { s = sound, volume = row.Volume or 0.1 }
end

function CueSkinLook.buildEmitter(self: Look, row: any, aura: boolean)
	local parent, frame = self:host(row)
	if parent == nil then
		return -- a Carrier host with no carrier (the hands, a stand)
	end
	local back = self.opts.back == true
	local rateScale = if back then C.BackRateScale else 1
	local size = CueVfx.maxOf(row.Size)
	local behind = back and size > C.BehindBodySizeStuds
	-- On the cue as it moves, but for tiny specks drifting off thinly (Config.CueSkins.Drift).
	local drifts = size <= C.Drift.MaxSizeStuds and row.LockedToPart ~= true
	local e = CueVfx.emitter(row, {
		frame = frame :: any,
		rateScale = rateScale * (if drifts then C.Drift.RateScale else 1),
		zOffset = if behind then C.BehindBodyZOffset else 0,
		locked = not drifts,
	})
	local rate = e.Rate
	if aura then
		e.Rate = rate * self.share
	end
	if e.Texture == "" then
		e.Texture = texture(nil, "Emitter")
	end
	if parent:IsA("BasePart") then
		local h = row.Host or {}
		e.Shape = if h.Shape == "Cylinder"
			then Enum.ParticleEmitterShape.Cylinder
			else Enum.ParticleEmitterShape.Box
		e.ShapeStyle = if h.Shape == "Cylinder" and h.ShapeStyle == "Surface"
			then Enum.ParticleEmitterShapeStyle.Surface
			else Enum.ParticleEmitterShapeStyle.Volume
		if h.ShapeInOut == "Inward" then
			e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		end
	end
	e.Parent = parent
	table.insert(self.built, e)
	local h = row.Host
	local carrier = h ~= nil and h.Kind == "Carrier"
	if carrier then
		e.Enabled = self:carrierShown()
	end
	table.insert(self.emitters, { e = e, aura = aura, rate = rate, carrier = carrier })
end

-- A beam's curve control offsets: Curve0/Curve1 are [up, side] and land on Roblox (+side, up)
-- (the preview's convention, mirrored against the Side keys), turned by Twist and swung by
-- Sway at time t.
local function curveOffsets(row: any, t: number): (Vector3?, Vector3?)
	local c0, c1 = row.Curve0, row.Curve1
	local sway = row.Sway
	if c0 == nil and c1 == nil and sway == nil then
		return nil, nil
	end
	local u0, s0 = (c0 or { 0, 0 })[1], (c0 or { 0, 0 })[2]
	local u1, s1 = (c1 or { 0, 0 })[1], (c1 or { 0, 0 })[2]
	if sway then
		local mid =
			math.sin(2 * math.pi * t / (sway.Period or 2) + math.rad(sway.Phase or 0) - math.pi / 2)
		u0 += (sway.Up or 0) * 0.35 * mid
		s0 -= (sway.Side or 0) * 0.35 * mid
		u1 += (sway.Up or 0) * 0.6 * mid
		s1 -= (sway.Side or 0) * 0.6 * mid
	end
	if row.Twist and (c0 or c1) then
		local a = math.rad(row.Twist * t)
		local ca, sa = math.cos(a), math.sin(a)
		u0, s0 = u0 * ca - s0 * sa, u0 * sa + s0 * ca
		u1, s1 = u1 * ca - s1 * sa, u1 * sa + s1 * ca
	end
	return Vector3.new(s0, u0, 0), Vector3.new(s1, u1, 0)
end

local function setCurve(d: DynBeam, t: number)
	local row = d.row
	local p0 = d.base0
	local p1 = d.base1
	local sway = row.Sway
	if sway then
		local s = math.sin(2 * math.pi * t / (sway.Period or 2) + math.rad(sway.Phase or 0))
		p1 = p1 + Vector3.new(-(sway.Side or 0) * s, (sway.Up or 0) * s, 0)
		d.a1.Position = p1
	end
	local o0, o1 = curveOffsets(row, t)
	if o0 and o1 then
		local c1 = p0 + (p1 - p0) / 3 + o0
		local c2 = p0 + 2 * (p1 - p0) / 3 + o1
		local v0, v1 = c1 - p0, p1 - c2
		if v0.Magnitude > 1e-4 then
			d.a0.Axis = v0.Unit
		end
		if v1.Magnitude > 1e-4 then
			d.a1.Axis = v1.Unit
		end
		d.beam.CurveSize0 = v0.Magnitude
		d.beam.CurveSize1 = v1.Magnitude
	end
end

function CueSkinLook.buildBeam(self: Look, row: any, aura: boolean)
	local mesh = self.mesh :: MeshPart
	local p0 = CueVfx.onCue(row.FromStuds or 3.8, row.Up, row.Side)
	local p1 = CueVfx.onCue(row.ToStuds or 5.3, row.Up1 or row.Up, row.Side1 or row.Side)
	local a0 = attachment(mesh, p0, (row.Name or "Beam") .. "0")
	local a1 = attachment(mesh, p1, (row.Name or "Beam") .. "1")
	local beam = Instance.new("Beam")
	beam.Name = row.Name or "Beam"
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = row.Width0 or 0.18
	beam.Width1 = row.Width1 or beam.Width0
	beam.Segments = row.Segments or 10
	beam.Texture = texture(row.Texture, "Beam")
	beam.TextureMode = (Enum.TextureMode :: any)[row.TextureMode or "Wrap"]
	beam.TextureLength = row.TextureLength or 1
	beam.TextureSpeed = row.TextureSpeed or 0
	beam.Color = CueVfx.colorSeq(row.Color)
	beam.Transparency = CueVfx.numberSeq(row.Transparency or 0)
	beam.LightEmission = row.LightEmission or 1
	beam.LightInfluence = row.LightInfluence or 0
	beam.Brightness = row.Brightness or 1
	beam.FaceCamera = row.FaceCamera ~= false
	beam.ZOffset = row.ZOffset or 0
	beam.Parent = mesh
	table.insert(self.built, a0)
	table.insert(self.built, a1)
	table.insert(self.built, beam)
	table.insert(self.beams, { b = beam, aura = aura })
	local d: DynBeam = {
		beam = beam,
		a0 = a0,
		a1 = a1,
		row = row,
		base0 = p0,
		base1 = p1,
		transparency = nil,
		aura = aura,
	}
	if row.Pulse or aura then
		local t = row.Transparency or 0
		d.transparency = if type(t) == "number" then { { 0, t }, { 1, t } } else t
	end
	setCurve(d, 0)
	if row.Sway or row.Twist or row.Pulse or aura then
		table.insert(self.dynBeams, d)
	end
end

function CueSkinLook.buildOrbiter(self: Look, row: any)
	local mesh = self.mesh :: MeshPart
	local a = attachment(mesh, Vector3.zero, (row.Name or "Orbiter") .. "A")
	local b = attachment(mesh, Vector3.zero, (row.Name or "Orbiter") .. "B")
	local tr = row.Trail or {}
	local trail = Instance.new("Trail")
	trail.Name = row.Name or "Orbiter"
	trail.Attachment0 = a
	trail.Attachment1 = b
	trail.FaceCamera = true
	trail.Lifetime = tr.Lifetime or 0.34
	trail.MinLength = 0.02
	trail.Color = CueVfx.colorSeq(tr.Color)
	trail.Transparency = CueVfx.numberSeq(tr.Transparency or { { 0, 0.55 }, { 1, 1 } })
	trail.WidthScale = CueVfx.numberSeq(tr.WidthScale or 1)
	trail.LightEmission = tr.LightEmission or 0.4
	trail.LightInfluence = 0
	trail.Brightness = tr.Brightness or 1
	trail.Texture = texture(tr.Texture, "Trail")
	trail.TextureMode = (Enum.TextureMode :: any)[tr.TextureMode or "Stretch"]
	trail.TextureLength = tr.TextureLength or 1
	trail.Parent = mesh
	local head: ParticleEmitter? = nil
	if row.Head then
		local h = row.Head
		local e = Instance.new("ParticleEmitter")
		e.Name = "Head"
		e.Texture = texture(h.Texture, "Head")
		e.Rate = C.HeadRate
		e.Lifetime = NumberRange.new(C.HeadLifetime)
		e.Speed = NumberRange.new(0)
		e.Size = NumberSequence.new(h.Size or 0.3)
		e.Color = CueVfx.colorSeq(h.Color or "#FFFFFF")
		e.Transparency = NumberSequence.new(h.Transparency or 0)
		e.LightEmission = h.LightEmission or 1
		e.LightInfluence = 0
		e.Brightness = h.Brightness or 1
		e.LockedToPart = true
		e.Parent = a
		head = e
	end
	table.insert(self.built, a)
	table.insert(self.built, b)
	table.insert(self.built, trail)
	table.insert(self.orbiters, { row = row, a = a, b = b, head = head, trail = trail, lap = 0 })
end

function CueSkinLook.buildArc(self: Look, row: any)
	local mesh = self.mesh :: MeshPart
	local segments = math.max(row.Segments or 6, 1)
	local strands = {}
	for n = 1, row.Count or 3 do
		local atts, beams = {}, {}
		for i = 0, segments do
			local a = attachment(mesh, Vector3.zero, ("%s%d_%d"):format(row.Name or "Arc", n, i))
			table.insert(atts, a)
			table.insert(self.built, a)
		end
		local width = row.WidthStuds or 0.05
		for i = 1, segments do
			local taperA = math.sin(0.15 + (math.pi - 0.3) * (i - 1) / segments)
			local taperB = math.sin(0.15 + (math.pi - 0.3) * i / segments)
			local beam = Instance.new("Beam")
			beam.Attachment0 = atts[i]
			beam.Attachment1 = atts[i + 1]
			beam.Width0 = width * taperA
			beam.Width1 = width * taperB
			beam.Segments = 1
			beam.FaceCamera = true
			beam.Texture = texture(row.Texture, "Arc")
			beam.TextureMode = Enum.TextureMode.Stretch
			beam.Color = CueVfx.colorSeq(row.Color or "#C9A0FF")
			beam.Transparency = NumberSequence.new(row.Transparency or 0)
			beam.LightEmission = row.LightEmission or 1
			beam.LightInfluence = 0
			beam.Brightness = row.Brightness or 1
			beam.Enabled = false
			beam.Parent = mesh
			table.insert(beams, beam)
			table.insert(self.built, beam)
		end
		table.insert(strands, { atts = atts, beams = beams })
	end
	table.insert(self.arcs, { row = row, strands = strands, slot = -1, shown = false })
end

-- Strike an arc's strands again (CueVfx.py's Arcs): a random stretch along the cue, bowed off
-- it, jagged at every joint but the two ends.
local function strike(arc: Arc)
	local row = arc.row
	local from, to = row.FromStuds or 3.6, row.ToStuds or 6.9
	local lmin, lmax = (row.Length or { 0.25, 0.7 })[1], (row.Length or { 0.25, 0.7 })[2]
	local radius, jitter = row.Radius or 0.12, row.Jitter or 0.05
	local around = math.rad(row.Around or 90)
	for _, strand in arc.strands do
		local n = #strand.atts - 1
		local L = lmin + (lmax - lmin) * math.random()
		local d0 = from + (to - from - L) * math.random()
		local th0 = math.random() * 2 * math.pi
		local th1 = th0 + (2 * math.random() - 1) * around
		local bow = 0.6 + 0.8 * math.random()
		for i = 0, n do
			local k = i / n
			local d = d0 + L * k
			local th = th0 + (th1 - th0) * k
			local r = radius + jitter * math.sin(math.pi * k) * bow
			local side, up = r * math.sin(th), -r * math.cos(th)
			local jag = if i == 0 or i == n
				then Vector3.zero
				else Vector3.new(
					(2 * math.random() - 1) * jitter,
					(2 * math.random() - 1) * jitter,
					(2 * math.random() - 1) * jitter
				)
			strand.atts[i + 1].Position = CueVfx.onCue(d, up, side) + jag
		end
	end
end

-- Show or hide the whole look (the stick's Visible attribute).
function CueSkinLook.applyVisible(self: Look)
	-- Never the previous cue's look on a stick already painted as the next one (its rebuild
	-- waits a frame, refreshSoon).
	local current = self.stick:GetAttribute("CueId") == self.cueId
	local visible = self.stick:GetAttribute("Visible") == true and self.row ~= nil and current
	-- The aura (emitters, beams, orbiters, arcs, lights) also goes with AuraOff; the stick
	-- and its piece do not.
	local aura = visible and self.stick:GetAttribute("AuraOff") ~= true
	local appearing = aura and not self.aura
	self.visible = visible
	self.aura = aura
	for _, item in self.emitters do
		item.e.Enabled = aura and item.e.Rate > 0 and (not item.carrier or self.carrierOn)
	end
	local sound = self.sound
	if sound then
		if aura and not sound.s.IsPlaying then
			sound.s:Play()
		elseif not aura and sound.s.IsPlaying then
			sound.s:Stop()
		end
	end
	if appearing and C.ShowPrefillShare > 0 then
		-- Coming into view: the aura is already there, not growing in (Config.CueSkins).
		for _, item in self.emitters do
			local e = item.e
			if item.aura and e.Enabled then
				local life = (e.Lifetime.Min + e.Lifetime.Max) / 2
				local n = math.floor(e.Rate * life * C.ShowPrefillShare + 0.5)
				if n > 0 then
					e:Emit(n)
				end
			end
		end
	end
	for _, item in self.beams do
		item.b.Enabled = aura
	end
	for _, o in self.orbiters do
		o.trail.Enabled = aura
		if o.head then
			o.head.Enabled = aura
		end
		if not aura then
			o.trail:Clear()
		end
	end
	for _, arc in self.arcs do
		if not aura then
			for _, strand in arc.strands do
				for _, beam in strand.beams do
					beam.Enabled = false
				end
			end
			arc.shown = false
		end
	end
	for _, l in self.lights do
		l.light.Enabled = aura
	end
	for _, ink in self.inks do
		ink.Enabled = visible and self.inkShown == true
	end
	if self.piece then
		self.piece:setModifier(if visible then 0 else 1)
	end
	if self.carrierPiece then
		self.carrierPiece:setModifier(if aura then 0 else 1)
	end
end

local function hsv(t: number, period: number, saturation: number): Color3
	return Color3.fromHSV((t / period) % 1, saturation, 1)
end

--- Move everything that moves to time `t` on the look's clock.
function CueSkinLook.step(self: Look, t: number)
	local row = self.row
	local mesh = self.mesh
	if row == nil or mesh == nil then
		return
	end
	local surface = row.Surface or {}
	local pulse = surface.Pulse or {}
	-- Frames: swap which SurfaceAppearance the mesh wears.
	if #self.frames > 1 and row.Frames then
		local order = row.Frames.Order or {}
		local count = #order
		local k = if count > 0
			then order[math.floor(t / (row.Frames.FrameSeconds or 0.25)) % count + 1] % #self.frames
			else 0
		if k ~= self.frame then
			local next = self.frames[k + 1]
			for _, sa in self.frames do
				if sa ~= next then
					sa.Parent = nil
				end
			end
			next.Parent = mesh
			self.frame = k
		end
	end
	local sa = self.frames[self.frame + 1]
	if sa then
		if pulse.EmissiveStrength then
			sa.EmissiveStrength = Motion.vfxWave(t, pulse.EmissiveStrength)
		end
		if pulse.EmissiveTintHue then
			local p = pulse.EmissiveTintHue
			sa.EmissiveTint = hsv(t, p.Period or 3, p.Saturation or 0.85)
		end
	end
	for _, d in self.dynBeams do
		setCurve(d, t)
		if d.transparency then
			local w = (if d.row.Pulse then Motion.vfxWave(t, d.row.Pulse) else 1)
				* (if d.aura then self.share else 1)
			local keys = {}
			for _, k in d.transparency do
				table.insert(keys, { k[1], 1 - (1 - k[2]) * w })
			end
			d.beam.Transparency = CueVfx.numberSeq(keys)
		end
	end
	-- The stick's speed (eased), which shortens the orbiters' ribbons (Config.CueSkins.Drift).
	local at = mesh.Position
	local lastT, lastAt = self.lastT, self.lastAt
	if lastT and lastAt and t > lastT then
		local dt = t - lastT
		local speed = (at - lastAt).Magnitude / dt
		self.speed += (speed - self.speed) * math.min(1, dt / C.Drift.MovingEaseSeconds)
	end
	self.lastT, self.lastAt = t, at
	local moving = math.clamp(self.speed / C.Drift.MovingSpeedStuds, 0, 1)
	for _, o in self.orbiters do
		local r = o.row
		local life = (r.Trail or {}).Lifetime or 0.34
		o.trail.Lifetime = life + (math.min(C.Drift.MovingTrailSeconds, life) - life) * moving
		local tt = t - (r.Delay or 0)
		if tt < 0 then
			o.trail.Enabled = false
			continue
		end
		local travel = r.TravelSeconds or 1.5
		local u = if travel > 0 then tt / travel else 0
		local f
		if r.Loop == "pingpong" then
			f = u % 2
			if f > 1 then
				f = 2 - f
			end
		else
			f = u % 1
			local lap = math.floor(u)
			if lap ~= o.lap then
				o.lap = lap
				o.trail:Clear()
			end
		end
		local from, to = r.FromStuds or 0.3, r.ToStuds or 6.9
		local d = from + (to - from) * f
		local th = math.rad(r.Phase or 0) + 2 * math.pi * (r.TurnsPerSecond or 1) * tt
		local rad = (r.Radius or 0.2)
			+ (r.Wobble or 0) * math.sin(2 * math.pi * tt * (r.WobbleHz or 1.3))
		if r.RadiusFromSurface then
			rad += CueShape.radiusAt(d)
		end
		local side, up = rad * math.sin(th), -rad * math.cos(th)
		local p = CueVfx.onCue(d, up, side)
		local half = ((r.Trail or {}).WidthStuds or 0.21) / 2
		local radial = Vector3.new(-side, up, 0)
		radial = if radial.Magnitude > 1e-4 then radial.Unit else Vector3.yAxis
		o.a.Position = p - radial * half
		o.b.Position = p + radial * half
		o.trail.Enabled = self.aura
	end
	for _, arc in self.arcs do
		local interval = arc.row.Interval or 0.12
		local slot = math.floor(t / interval)
		if slot ~= arc.slot then
			arc.slot = slot
			strike(arc)
		end
		local on = self.aura and ((t % interval) / interval) <= (arc.row.Duty or 0.6)
		if on ~= arc.shown then
			arc.shown = on
			for _, strand in arc.strands do
				for _, beam in strand.beams do
					beam.Enabled = on
				end
			end
		end
	end
	for _, l in self.lights do
		local lr = l.row
		l.light.Brightness = (lr.Brightness or 1)
			* (if lr.Flicker then Motion.vfxWave(t, lr.Flicker) else 1)
			* self.share
		if lr.Hue then
			l.light.Color = hsv(t, lr.Hue.Period or 4, lr.Hue.Saturation or 0.8)
		end
	end
	local carrierOn = self:carrierShown()
	if carrierOn ~= self.carrierOn then
		self.carrierOn = carrierOn
		for _, item in self.emitters do
			if item.carrier then
				item.e.Enabled = self.aura and item.e.Rate > 0 and carrierOn
			end
		end
	end
	if self.carrierPiece then
		self.carrierPiece:setAura(carrierOn)
		self.carrierPiece:step(t)
	end
	if self.piece then
		self.piece:step(t)
		if self.visible then
			self.piece:setModifier(mesh.LocalTransparencyModifier)
		end
	end
	-- A moving gradient outline: the colours flow along the ribbons, the Highlight cycles.
	local palette = self.palette
	if palette and #self.inks > 0 then
		local G = C.Pop.Outline.Gradient
		local phase = t / G.Period
		local n = #self.inks
		for i, ink in self.inks do
			local r0, g0, b0 = Pop.sample(palette, phase - G.Spread * (i - 1) / n)
			local r1, g1, b1 = Pop.sample(palette, phase - G.Spread * i / n)
			ink.Color = ColorSequence.new(Color3.new(r0, g0, b0), Color3.new(r1, g1, b1))
		end
		if self.outline then
			local r, g, b = Pop.sample(palette, phase - G.Spread / 2)
			self.outline.OutlineColor = Color3.new(r, g, b)
			self.outline.FillColor = self.outline.OutlineColor
		end
	end
	-- The ink is off while the stick fades for the camera at all (a see-through cue is drawn
	-- after the ribbons behind it, which then cover it), and seen nearly end-on (a ribbon
	-- that faces the camera cannot follow a cue pointing at it); the Highlight stays.
	if #self.inks > 0 then
		local eye = Workspace.CurrentCamera.CFrame.Position
		local toward = mesh.Position - eye
		local endOn = toward.Magnitude > 1e-3
			and math.abs(mesh.CFrame.LookVector:Dot(toward.Unit)) > inkEndOnCos
		local shown = self.visible and mesh.LocalTransparencyModifier <= 0 and not endOn
		if shown ~= self.inkShown then
			self.inkShown = shown
			for _, ink in self.inks do
				ink.Enabled = shown
			end
		end
	end
end

-- Whether the engulfing aura round the carrying player is drawn: never while the stick is
-- AuraQuiet (the owner shooting, or your own turn) or CarrierQuiet (a shot in flight at the
-- owner's table); back between shots.
function CueSkinLook.carrierShown(self: Look): boolean
	return self:quietTarget() >= 1 and self.stick:GetAttribute("CarrierQuiet") ~= true
end

-- The share the aura eases toward while the stick is AuraQuiet: its skin's Quiet share, else
-- its tier's.
function CueSkinLook.quietTarget(self: Look): number
	if self.stick:GetAttribute("AuraQuiet") ~= true then
		return 1
	end
	local row = self.row
	if row == nil then
		return C.Quiet.DefaultShare
	end
	return C.Quiet.SkinShares[row.CatalogId] or C.Quiet.Shares[row.Tier] or C.Quiet.DefaultShare
end

-- Ease the aura's share toward its target by `dt`; the emitters' rates follow at once, the
-- beams and lights on the next step.
function CueSkinLook.ease(self: Look, dt: number)
	local target = self:quietTarget()
	if self.share == target then
		return
	end
	local stepBy = dt / C.Quiet.FadeSeconds
	self.share = if self.share < target
		then math.min(target, self.share + stepBy)
		else math.max(target, self.share - stepBy)
	for _, item in self.emitters do
		if item.aura then
			item.e.Rate = item.rate * self.share
		end
	end
	if self.sound then
		self.sound.s.Volume = self.sound.volume * self.share
	end
end

function CueSkinLook.destroy(self: Look)
	live[self] = nil
	for _, c in self.connections do
		c:Disconnect()
	end
	self:clear()
end

-- One clock for every look: visible ones within reach of the camera are stepped. The nearest
-- looks' Highlights are on, up to Config.CueSkins.Outline.MaxShown; the rest, and any far,
-- hidden or faded by the camera (first person, a close shot), are off.
local lit: { { look: Look, near: number } } = {}
RunService.RenderStepped:Connect(function(dt: number)
	local camera = Workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position or Vector3.zero
	local now = os.clock()
	table.clear(lit)
	for look in live do
		look:ease(dt)
		local mesh = look.mesh
		local near = if mesh then (mesh.Position - eye).Magnitude else math.huge
		if look.visible and near <= C.StepDistanceStuds then
			look:step(now - look.t0)
		end
		if #look.highlights > 0 then
			if
				mesh
				and look.visible
				and near <= C.HighlightDistanceStuds
				and mesh.LocalTransparencyModifier < 0.5
			then
				table.insert(lit, { look = look, near = near })
			else
				for _, h in look.highlights do
					h.Enabled = false
				end
			end
		end
	end
	table.sort(lit, function(a, b)
		return a.near < b.near
	end)
	local shown = 0
	for _, item in lit do
		for _, h in item.look.highlights do
			h.Enabled = shown < C.Outline.MaxShown
			shown += 1
		end
	end
end)

return CueSkinLook
