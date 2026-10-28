--!strict
-- CuePiece: a cue skin's 3D piece (CueSkins.piece rows: Phoenix's wings, the Kraken's
-- tentacles, the Celestial Dragon, the Kitsune's mask and running fox, Eclipse's orbits, the
-- pocket creatures), built from its Edit-mode template and moved every frame by its joints
-- (CueSkins.Motion, the Blender reference's maths).
--
-- Templates: ReplicatedStorage[Config.CueSkins.PiecesFolder].<piece> holds one MeshPart per
-- rigid part (named as the row's part) and one Model per skinned file (RootPart, Bones and
-- skinned MeshParts, as the importer made them), dressed in Edit by
-- tools/build_cue_templates.luau (Material, Color, SurfaceAppearance cannot all be set here).
--
-- Every part is unanchored, massless and touches nothing, welded to a ROOT part: the cue's
-- mesh (so the piece follows the stick in the hands and on a back with no extra code) or the
-- pocket finisher's own anchored root. Roblox's importer turns every uploaded model half a
-- turn about its up axis (FLIP; the shared cue mesh too), so a rigid part's Weld.C0 is
-- J(t) * Offset * FLIP, a skinned model's RootPart is welded at FLIP, and each Bone gets
-- Transform = B^-1 * Motion.jointDelta * B, B the bone's rest frame in the piece's frame read
-- from the template (the importer turns bones too: the dragon's top bone is half a turn
-- about Y, and assuming square bones threw its body past the butt).
-- Joints marked Aura (the dragon, the running fox) hide with the aura. Joints marked Aim
-- "fade" (a body reaching past the butt: the Broom's bristles) ease to clear on the owner's own
-- screen while the stick is drawn for a shot (setAim) and back after it. A body's parts also
-- take their own camera fade (setModifier with an eye), so a long part never pokes into the lens.
-- A joint's Visual rows (Fade, Blink, Glow, Type) are looks applied every step: the first
-- three on the joint's rigid parts, Type as a typing SurfaceGui riding the joint (the Beta
-- Cue's blueprint panels), Config.CueSkins.Typing holding the shared numbers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CueSkins = require(Shared:WaitForChild("CueSkins"))
local Motion = require(Shared:WaitForChild("CueSkins"):WaitForChild("Motion"))
local Quality = require(script.Parent:WaitForChild("Quality"))

local CuePiece = {}
CuePiece.__index = CuePiece

-- The importer's half turn about Y (its own inverse).
local FLIP = CFrame.Angles(0, math.pi, 0)

type Rigid = {
	part: BasePart,
	weld: Weld,
	joint: string,
	offset: CFrame,
	base: number,
	color: Color3, -- as dressed, for Glow visuals
	visuals: { any }, -- the joint's Visual rows (Fade, Blink, Glow), empty for most
}
type Skinned = {
	model: Model,
	parts: { BasePart },
	base: { number },
	bones: { { bone: Bone, joint: string, parent: string?, rest: CFrame } },
}
type Rider = { part: BasePart, weld: Weld, joint: string, rest: CFrame }
-- A Type visual's typing panel: a SurfaceGui riding its joint (a Rider), one label per row.
type Typer = {
	gui: SurfaceGui,
	labels: { TextLabel },
	joint: string,
	row: any,
	visuals: { any },
	text: { string }, -- the rows' full gibberish, redrawn each life
	cycle: number, -- the life the text was drawn for
	typed: number, -- glyphs shown last step
	hidden: boolean, -- aura hidden or camera-faded
}

export type CuePiece = typeof(setmetatable(
	{} :: {
		id: string,
		model: Model,
		noInk: Model?, -- parts with Outline = false: a sibling Model the cue's Highlights never adorn
		rig: Motion.Rig,
		rigid: { Rigid },
		skinned: { Skinned },
		riders: { Rider },
		typers: { Typer },
		auraJoints: { [string]: boolean },
		lowJoints: { [string]: boolean }, -- joints (and their children) gone under Lower effects
		aimJoints: { [string]: boolean }, -- joints (and their children) clear while aiming
		aimOn: boolean, -- aiming now (the target of the ease)
		aim: number, -- the Aim joints' clear share, eased toward aimOn
		lastT: number?,
		auraShown: boolean,
		low: boolean, -- Lower effects is on
		qualityConnection: RBXScriptConnection?,
		lastModifier: number?, -- the last setModifier arguments (reused by the Quality and aura toggles)
		lastEye: Vector3?,
		lastStuds: number?,
		scale: number,
		lift: CFrame, -- the whole piece raised on its root (a Carrier piece to the body's head)
		turn: CFrame, -- each rigid part's rest turn: FLIP for decor, none for a body
		fade: number,
		pose: { [string]: Motion.Xf },
	},
	CuePiece
))

local WHITE = Color3.new(1, 1, 1)
local T = Config.CueSkins.Typing
local rng = Random.new()

-- Fresh gibberish for a typing panel: `cols` glyphs a row, tokens of TokenMin..TokenMax
-- glyphs from the Typing alphabet, split by spaces. Never words.
local function gibberish(rows: number, cols: number): { string }
	local out = {}
	local glyphs = T.Glyphs
	for _ = 1, rows do
		local line = {}
		local n = 0
		while n < cols do
			local len = math.min(rng:NextInteger(T.TokenMin, T.TokenMax), cols - n)
			for _ = 1, len do
				local i = rng:NextInteger(1, #glyphs)
				table.insert(line, glyphs:sub(i, i))
			end
			table.insert(line, " ")
			n += len + 1
		end
		table.insert(out, table.concat(line))
	end
	return out
end

-- A Type visual's rider part and gui: a thin part the size of the panel (Size [w, h] studs)
-- at Frame (Origin, Right, Up in the Blender cue frame, turned to Roblox), its Front face
-- carrying Rows labels.
local function buildTyper(row: any, zoff: number): (BasePart, CFrame, Typer)
	local f = row.Frame
	local o = Motion.toRoblox(f.Origin)
	local right = Motion.toRoblox(f.Right)
	local up = Motion.toRoblox(f.Up)
	local vx = Vector3.new(right[1], right[2], right[3])
	local vy = Vector3.new(up[1], up[2], up[3])
	local rest = CFrame.fromMatrix(Vector3.new(o[1], o[2], o[3] + zoff), vx, vy, vx:Cross(vy))
	local part = Instance.new("Part")
	part.Name = "Typer"
	part.Size = Vector3.new(row.Size[1], row.Size[2], 0.01)
	part.Transparency = 1
	part.CastShadow = false
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Typing"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = T.PixelsPerStud
	gui.LightInfluence = 0
	gui.Brightness = T.Brightness
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	local area = row.Area or { 0.05, 0.1, 0.95, 0.9 }
	local rows = row.Rows or 4
	local pitch = (area[4] - area[2]) / rows
	local color = Color3.fromHex(row.Color or "#9FD0FF")
	local labels = {}
	for i = 1, rows do
		local label = Instance.new("TextLabel")
		label.Name = "Row" .. i
		label.BackgroundTransparency = 1
		label.BorderSizePixel = 0
		label.Position = UDim2.fromScale(area[1], area[2] + (i - 1) * pitch)
		label.Size = UDim2.fromScale(area[3] - area[1], pitch)
		label.Font = (Enum.Font :: any)[T.Font] or Enum.Font.Code
		label.TextSize = math.max(8, row.Size[2] * T.PixelsPerStud * pitch / T.LineHeight)
		label.TextColor3 = color
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.TextTransparency = 1
		label.Text = ""
		label.Parent = gui
		table.insert(labels, label)
	end
	gui.Parent = part
	return part,
		rest,
		{
			gui = gui,
			labels = labels,
			joint = "",
			row = row,
			visuals = {},
			text = {},
			cycle = -1,
			typed = -1,
			hidden = false,
		}
end

local function cframe(x: Motion.Xf, scale: number?): CFrame
	local R, P = x.R, x.P
	local s = scale or 1
	return CFrame.new(
		P[1] * s,
		P[2] * s,
		P[3] * s,
		R[1],
		R[2],
		R[3],
		R[4],
		R[5],
		R[6],
		R[7],
		R[8],
		R[9]
	)
end
CuePiece.cframe = cframe

local function loose(part: BasePart)
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

local function template(id: string): Instance?
	local folder = ReplicatedStorage:FindFirstChild(Config.CueSkins.PiecesFolder)
	return folder and folder:FindFirstChild(id)
end

--- True when the piece's template is in the place.
function CuePiece.available(id: string): boolean
	return CueSkins.piece(id) ~= nil and template(id) ~= nil
end

--- Build piece `id` welded to `root` (its frame: the cue mesh for a cue piece, the pocket
--- root for a pocket piece), in `parent`. Nil when the row or the template is missing.
--- `lift`: studs the whole piece is raised on its root (a Carrier piece lifted to the body's head).
export type Opts = {
	body: boolean?, -- a cue body (Halloween 2026): its rigid parts keep the design's orientation
}
-- A piece row's Upright = true (piece.json, the builder's k.upright) asks the same for a decor or
-- pocket piece: a creature with a face, built after the half turn was understood (the
-- Jack-o'-Lantern's pocket jack, 2026-10-28). Older pieces leave it unset and keep their look.

function CuePiece.new(
	id: string,
	root: BasePart,
	parent: Instance,
	lift: number?,
	opts: Opts?
): CuePiece?
	local row = CueSkins.piece(id)
	local source = template(id)
	if row == nil or source == nil then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Piece_" .. id
	-- A rigid part's GLB (tools/cue_pieces_glb.py) is written so the importer's half turn lands
	-- it in the cue frame already; FLIP then turns it once more, end for end. Every shipped decor
	-- piece was approved looking that way, so it keeps it; a body must wear its tip at the tip.
	local turn = if (opts and opts.body) or row.Upright == true then CFrame.identity else FLIP
	local rig = Motion.rig(row)
	local auraJoints: { [string]: boolean } = {}
	local lowJoints: { [string]: boolean } = {}
	local aimJoints: { [string]: boolean } = {}
	for _, name in rig.order do
		local j = rig.joints[name]
		auraJoints[name] = j.aura or (j.parent ~= nil and auraJoints[j.parent] == true)
		lowJoints[name] = j.low == "hide" or (j.parent ~= nil and lowJoints[j.parent] == true)
		aimJoints[name] = j.aim == "fade" or (j.parent ~= nil and aimJoints[j.parent] == true)
	end
	local rigid: { Rigid } = {}
	local skinned: { Skinned } = {}
	local doneModels: { [string]: boolean } = {}
	-- A part row with Outline = false (a Broom's two hundred straws, 2026-10-28) goes under a
	-- sibling Model, so the body's inked Highlight (CueSkinLook adorns the piece Model) skips it;
	-- its weld, motion and fades are the same.
	local noInk: Model? = nil
	for _, p in row.Parts do
		if p.Model then
			if not doneModels[p.Model] then
				doneModels[p.Model] = true
				local src = source:FindFirstChild(p.Model)
				if src and src:IsA("Model") then
					local copy = src:Clone()
					local parts, base = {}, {}
					local rootPart = copy:FindFirstChild("RootPart") :: BasePart?
					for _, d in copy:GetDescendants() do
						if d:IsA("BasePart") then
							loose(d)
							if d ~= rootPart then
								table.insert(parts, d)
								table.insert(base, d.Transparency)
							end
						end
					end
					-- Rest frames before the weld moves anything: the template's RootPart frame is
					-- the importer's turned piece frame.
					local rootFrame = if rootPart then rootPart.CFrame else CFrame.identity
					local bones = {}
					for _, d in copy:GetDescendants() do
						if d:IsA("Bone") and rig.joints[d.Name] then
							local parentBone = d.Parent
							table.insert(bones, {
								bone = d,
								joint = d.Name,
								parent = if parentBone and parentBone:IsA("Bone")
									then parentBone.Name
									else nil,
								rest = FLIP * rootFrame:ToObjectSpace(d.WorldCFrame),
							})
						end
					end
					if rootPart then
						rootPart.Transparency = 1
						-- A Highlight outlines a fully transparent part too: the importer's 2x2x1 root
						-- drew a gold box round the Cat's middle (2026-10-28). Shrunk to a dot; the
						-- bones hang off its CFrame, not its size.
						rootPart.Size = Vector3.one * 0.01
						local weld = Instance.new("Weld")
						weld.Part0 = root
						weld.Part1 = rootPart
						weld.C0 = FLIP
						weld.C1 = CFrame.identity
						weld.Parent = rootPart
					end
					copy.Parent = model
					table.insert(
						skinned,
						{ model = copy, parts = parts, base = base, bones = bones }
					)
				end
			end
		else
			local src = source:FindFirstChild(p.Name)
			if src and src:IsA("BasePart") then
				local part = src:Clone()
				loose(part)
				local weld = Instance.new("Weld")
				weld.Part0 = root
				weld.Part1 = part
				weld.Parent = part
				if p.Outline == false then
					if noInk == nil then
						local made = Instance.new("Model")
						made.Name = "Piece_" .. id .. "_NoOutline"
						noInk = made
					end
					part.Parent = noInk :: Model
				else
					part.Parent = model
				end
				local o = p.Offset
				local joint = rig.joints[p.Joint]
				table.insert(rigid, {
					part = part,
					weld = weld,
					joint = p.Joint,
					offset = CFrame.new(o[1], o[2], o[3]) * turn,
					base = part.Transparency,
					color = part.Color,
					visuals = if joint then joint.visuals else {},
				})
			end
		end
	end
	model.Parent = parent
	if noInk then
		noInk.Parent = parent
	end
	local self = setmetatable({
		id = id,
		model = model,
		noInk = noInk,
		rig = rig,
		rigid = rigid,
		skinned = skinned,
		riders = {},
		typers = {},
		auraJoints = auraJoints,
		lowJoints = lowJoints,
		aimJoints = aimJoints,
		aimOn = false,
		aim = 0,
		lastT = nil,
		auraShown = true,
		low = Quality.isLow(),
		qualityConnection = nil :: RBXScriptConnection?,
		lastModifier = nil :: number?,
		lastEye = nil :: Vector3?,
		lastStuds = nil :: number?,
		scale = 1,
		lift = CFrame.new(0, lift or 0, 0),
		turn = turn,
		fade = 0,
		pose = {},
	}, CuePiece)
	-- Typing panels: one rider per Type visual.
	for _, name in rig.order do
		local j = rig.joints[name]
		for _, v in j.visuals do
			if v.Kind == "Type" then
				local part, rest, typer = buildTyper(v, rig.zoff)
				typer.joint = name
				typer.visuals = j.visuals
				part.Parent = model
				self:ride(part, name, rest, root)
				table.insert(self.typers, typer)
			end
		end
	end
	self:step(0)
	self:applyHidden()
	self.qualityConnection = Quality.Changed:Connect(function(on: boolean)
		self.low = on
		-- With the last modifier (a hidden stick's 1), so toggling Lower effects never shows a
		-- hidden body as a ghost where the cue was last drawn (review, 2026-10-28).
		self:applyHidden(self.lastModifier, self.lastEye, self.lastStuds)
	end)
	return self
end

--- Whether a joint is hidden now: its aura is off, or Lower effects took it.
function CuePiece.hidden(self: CuePiece, joint: string): boolean
	return (not self.auraShown and self.auraJoints[joint] == true)
		or (self.low and self.lowJoints[joint] == true)
end

--- Weld `part` to ride joint `joint` (its rest place `rest` in the piece's frame): an
--- emitter host on a moving wing or a swimming body. It is moved with the joint every step.
function CuePiece.ride(self: CuePiece, part: BasePart, joint: string, rest: CFrame, root: BasePart)
	loose(part)
	local weld = Instance.new("Weld")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	table.insert(self.riders, { part = part, weld = weld, joint = joint, rest = rest })
	local x = self.pose[joint]
	weld.C0 = self.lift * (if x then cframe(x, self.scale) else CFrame.identity) * rest
end

--- Whether a joint (or one of its parents) is aura.
function CuePiece.isAura(self: CuePiece, joint: string): boolean
	return self.auraJoints[joint] == true
end

-- A joint's Visual rows at time t on one rigid part: Fade (visible share by an effect wave,
-- 1 as built), Blink (gone on alternate sub-steps of a short window once a period) and Glow
-- (the colour pushed toward white, or the row's Color, by an effect wave). The part's
-- Transparency composes the share with its dressed base and the piece's fade.
local function applyVisuals(r: Rigid, t: number, fade: number)
	local shown = 1
	local glow = 0
	local glowTo: Color3? = nil
	for _, v in r.visuals do
		local kind = v.Kind
		if kind == "Fade" then
			shown *= Motion.vfxWave(t, v)
		elseif kind == "Blink" then
			if Motion.blinkGone(t, v) then
				shown = 0
			end
		elseif kind == "Glow" then
			local k = Motion.vfxWave(t, v)
			if k > glow then
				glow = k
				glowTo = if v.Color then Color3.fromHex(v.Color) else nil
			end
		end
	end
	r.part.Transparency = 1 - (1 - r.base) * (1 - fade) * shown
	r.part.Color = r.color:Lerp(glowTo or WHITE, math.clamp(glow, 0, 1))
end

-- The visible share a joint's Fade and Blink rows give at time t (1 with none).
local function shownShare(visuals: { any }, t: number): number
	local shown = 1
	for _, v in visuals do
		if v.Kind == "Fade" then
			shown *= Motion.vfxWave(t, v)
		elseif v.Kind == "Blink" and Motion.blinkGone(t, v) then
			shown = 0
		end
	end
	return shown
end

-- Type a panel at time t: the life (Period, Phase as a share) is the clock; new gibberish
-- each life, Rate glyphs a second from Delay seconds in, row by row, a blinking cursor at
-- the end; the rows fade with the joint's Fade/Blink share.
local function stepTyper(ty: Typer, t: number, fade: number)
	local row = ty.row
	local period = row.Period or 8
	local u = (t / period + (row.Phase or 0)) % 1
	local cycle = math.floor(t / period + (row.Phase or 0))
	local rows = #ty.labels
	local cols = row.Cols or 18
	if cycle ~= ty.cycle then
		ty.cycle = cycle
		ty.text = gibberish(rows, cols)
		ty.typed = -1
	end
	local typed =
		math.clamp(math.floor((u * period - (row.Delay or 0.3)) * (row.Rate or 30)), 0, rows * cols)
	local cursorOn = (t % T.CursorPeriod) < T.CursorPeriod / 2
	local key = typed * 2 + (if cursorOn then 1 else 0)
	if key ~= ty.typed then
		ty.typed = key
		local left = typed
		for i, label in ty.labels do
			local line = ty.text[i] or ""
			local n = math.clamp(left, 0, #line)
			left -= #line
			local cursor = if left < 0 and cursorOn then T.CursorGlyph else ""
			label.Text = line:sub(1, n) .. cursor
		end
	end
	local alpha = 1 - (1 - fade) * shownShare(ty.visuals, t)
	for _, label in ty.labels do
		label.TextTransparency = alpha
	end
end

--- Move every joint to time `t` (seconds on the piece's clock).
function CuePiece.step(self: CuePiece, t: number)
	local pose = Motion.pose(self.rig, t)
	self.pose = pose
	-- The Aim joints ease to clear while aiming and back after (Config.CueSkins.Bodies).
	local target = if self.aimOn then 1 else 0
	if self.aim ~= target then
		local dt = math.clamp(t - (self.lastT or t), 0, 0.1)
		local by = dt / math.max(Config.CueSkins.Bodies.AimFadeSeconds, 1e-3)
		self.aim = if self.aim < target
			then math.min(target, self.aim + by)
			else math.max(target, self.aim - by)
	end
	self.lastT = t
	local s = self.scale
	for _, r in self.rigid do
		if not self:hidden(r.joint) then
			local x = pose[r.joint]
			local offset = if s == 1
				then r.offset
				else CFrame.new(r.offset.Position * s) * self.turn
			r.weld.C0 = self.lift * (if x then cframe(x, s) else CFrame.identity) * offset
		end
		if #r.visuals > 0 then
			applyVisuals(r, t, self.fade)
		end
	end
	for _, r in self.riders do
		local x = pose[r.joint]
		r.weld.C0 = self.lift * (if x then cframe(x, s) else CFrame.identity) * r.rest
	end
	for _, ty in self.typers do
		if not ty.hidden then
			stepTyper(ty, t, self.fade)
		end
	end
	for _, sk in self.skinned do
		for _, b in sk.bones do
			if not self:hidden(b.joint) then
				local x = Motion.jointDelta(pose, b.joint, b.parent)
				local rest = if s == 1
					then b.rest
					else CFrame.new(b.rest.Position * s) * b.rest.Rotation
				b.bone.Transform = rest:Inverse() * cframe(x, s) * rest
			end
		end
	end
end

-- A skinned model's root joint.
local function skinnedRoot(sk: Skinned): string?
	for _, b in sk.bones do
		if b.parent == nil then
			return b.joint
		end
	end
	return nil
end

-- How far a part fades for an eye within `studs` of its box (Camera.fadeNear's formula,
-- quantised the same way): 0 outside, 1 with the eye inside the part.
local function nearFade(part: BasePart, eye: Vector3, studs: number): number
	local v = part.CFrame:PointToObjectSpace(eye)
	local half = part.Size / 2
	local out = Vector3.new(
		math.max(math.abs(v.X) - half.X, 0),
		math.max(math.abs(v.Y) - half.Y, 0),
		math.max(math.abs(v.Z) - half.Z, 0)
	)
	local fade = math.clamp(1 - out.Magnitude / math.max(studs, 1e-3), 0, 1)
	return math.floor(fade * 50 + 0.5) / 50
end

-- Hide or show every part by its joint's state (aura off, Lower effects):
-- LocalTransparencyModifier, so nothing about the parts is rebuilt. Given an `eye`, each rigid
-- part also fades by its own distance to it (within `studs`), and the Aim joints by the aim
-- share; a part takes the largest. This is the one writer of the parts' modifier.
function CuePiece.applyHidden(self: CuePiece, modifier: number?, eye: Vector3?, studs: number?)
	if modifier ~= nil then
		-- Remembered for the Quality and aura toggles, which have no eye of their own.
		self.lastModifier, self.lastEye, self.lastStuds = modifier, eye, studs
	end
	local base = modifier or 0
	for _, r in self.rigid do
		local m = if self:hidden(r.joint) then 1 else base
		if m < 1 then
			if eye then
				m = math.max(m, nearFade(r.part, eye, studs or 1))
			end
			if self.aimJoints[r.joint] and self.aim > 0 then
				m = math.max(m, self.aim)
			end
		end
		if r.part.LocalTransparencyModifier ~= m then
			r.part.LocalTransparencyModifier = m
		end
	end
	for _, sk in self.skinned do
		local root = skinnedRoot(sk)
		local hidden = root ~= nil and self:hidden(root)
		local m = if hidden then 1 else base
		-- A skinned Aim joint (the Broom's hat charm, the Spider's crown) clears with the rigid
		-- ones; no near fade, its box is the bind pose (hw-cues-a, 2026-10-28).
		if m < 1 and root ~= nil and self.aimJoints[root] and self.aim > 0 then
			m = math.max(m, self.aim)
		end
		for _, part in sk.parts do
			if part.LocalTransparencyModifier ~= m then
				part.LocalTransparencyModifier = m
			end
		end
	end
	self:showTypers(modifier)
end

--- Show or hide the aura joints (the shooter's turn hides them).
function CuePiece.setAura(self: CuePiece, shown: boolean)
	if shown == self.auraShown then
		return
	end
	self.auraShown = shown
	self:applyHidden(self.lastModifier, self.lastEye, self.lastStuds)
end

-- A typing panel's gui is on or off (a SurfaceGui ignores LocalTransparencyModifier): off
-- while its joint is hidden or the stick is camera-faded past half.
function CuePiece.showTypers(self: CuePiece, modifier: number?)
	local faded = (modifier or 0) >= 0.5
	for _, ty in self.typers do
		local hidden = faded or self:hidden(ty.joint)
		if hidden ~= ty.hidden then
			ty.hidden = hidden
			ty.gui.Enabled = not hidden
		end
	end
end

--- Fade the whole piece: 0 as built, 1 gone (the pocket piece's Transparency curve). Parts
--- with visuals take it on their next step.
function CuePiece.setFade(self: CuePiece, fade: number)
	self.fade = fade
	for _, r in self.rigid do
		if #r.visuals == 0 then
			r.part.Transparency = r.base + (1 - r.base) * fade
		end
	end
	for _, sk in self.skinned do
		for i, part in sk.parts do
			part.Transparency = sk.base[i] + (1 - sk.base[i]) * fade
		end
	end
end

--- Deepen the piece against bright light (a pocket finisher's creature): its ForceField shell
--- parts `shellFade` of the way to clear (setFade fades from there), every glow
--- (SurfaceAppearance EmissiveStrength) `emissiveScale` as strong and, given `tint`, its
--- colour maps tinted by it (SurfaceAppearance.Color multiplies the map).
function CuePiece.deepen(self: CuePiece, shellFade: number, emissiveScale: number, tint: Color3?)
	local function shell(part: BasePart, base: number): number
		if part.Material ~= Enum.Material.ForceField then
			return base
		end
		local deeper = base + (1 - base) * shellFade
		part.Transparency = deeper
		return deeper
	end
	for _, r in self.rigid do
		r.base = shell(r.part, r.base)
	end
	for _, sk in self.skinned do
		for i, part in sk.parts do
			sk.base[i] = shell(part, sk.base[i])
		end
	end
	local holders: { Model } = { self.model }
	if self.noInk then
		table.insert(holders, self.noInk)
	end
	for _, holder in holders do
		for _, d in holder:GetDescendants() do
			if d:IsA("SurfaceAppearance") then
				d.EmissiveStrength *= emissiveScale
				if tint then
					d.Color = tint
				end
			end
		end
	end
end

--- Every part of the piece follows `modifier` (a stick's camera fade), hidden joints staying
--- hidden; with an `eye`, each part also fades by its own distance to it within `studs`.
function CuePiece.setModifier(self: CuePiece, modifier: number, eye: Vector3?, studs: number?)
	self:applyHidden(modifier, eye, studs)
end

--- Aiming on the owner's own screen: the Aim joints ease to clear (true) or back (false) on
--- the following steps.
function CuePiece.setAim(self: CuePiece, on: boolean)
	self.aimOn = on
end

--- Uniform scale about the root (the pocket piece grows as it rises): sizes and every
--- position the joints give.
function CuePiece.setScale(self: CuePiece, scale: number)
	if math.abs(scale - self.scale) < 1e-4 then
		return
	end
	self.model:ScaleTo(math.max(scale, 0.01))
	if self.noInk then
		self.noInk:ScaleTo(math.max(scale, 0.01))
	end
	self.scale = scale
end

function CuePiece.destroy(self: CuePiece)
	if self.qualityConnection then
		self.qualityConnection:Disconnect()
		self.qualityConnection = nil
	end
	self.model:Destroy()
	if self.noInk then
		self.noInk:Destroy()
	end
end

return CuePiece
