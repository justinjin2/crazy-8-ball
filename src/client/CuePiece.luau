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
-- Joints marked Aura (the dragon, the running fox) hide with the aura.
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
		rig: Motion.Rig,
		rigid: { Rigid },
		skinned: { Skinned },
		riders: { Rider },
		typers: { Typer },
		auraJoints: { [string]: boolean },
		lowJoints: { [string]: boolean }, -- joints (and their children) gone under Lower effects
		auraShown: boolean,
		low: boolean, -- Lower effects is on
		qualityConnection: RBXScriptConnection?,
		scale: number,
		lift: CFrame, -- the whole piece raised on its root (a Carrier piece to the body's head)
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
function CuePiece.new(id: string, root: BasePart, parent: Instance, lift: number?): CuePiece?
	local row = CueSkins.piece(id)
	local source = template(id)
	if row == nil or source == nil then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Piece_" .. id
	local rig = Motion.rig(row)
	local auraJoints: { [string]: boolean } = {}
	local lowJoints: { [string]: boolean } = {}
	for _, name in rig.order do
		local j = rig.joints[name]
		auraJoints[name] = j.aura or (j.parent ~= nil and auraJoints[j.parent] == true)
		lowJoints[name] = j.low == "hide" or (j.parent ~= nil and lowJoints[j.parent] == true)
	end
	local rigid: { Rigid } = {}
	local skinned: { Skinned } = {}
	local doneModels: { [string]: boolean } = {}
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
				part.Parent = model
				local o = p.Offset
				local joint = rig.joints[p.Joint]
				table.insert(rigid, {
					part = part,
					weld = weld,
					joint = p.Joint,
					offset = CFrame.new(o[1], o[2], o[3]) * FLIP,
					base = part.Transparency,
					color = part.Color,
					visuals = if joint then joint.visuals else {},
				})
			end
		end
	end
	model.Parent = parent
	local self = setmetatable({
		id = id,
		model = model,
		rig = rig,
		rigid = rigid,
		skinned = skinned,
		riders = {},
		typers = {},
		auraJoints = auraJoints,
		lowJoints = lowJoints,
		auraShown = true,
		low = Quality.isLow(),
		qualityConnection = nil :: RBXScriptConnection?,
		scale = 1,
		lift = CFrame.new(0, lift or 0, 0),
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
		self:applyHidden()
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
	local s = self.scale
	for _, r in self.rigid do
		if not self:hidden(r.joint) then
			local x = pose[r.joint]
			local offset = if s == 1 then r.offset else CFrame.new(r.offset.Position * s) * FLIP
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

-- Hide or show every part by its joint's state (aura off, Lower effects):
-- LocalTransparencyModifier, so nothing about the parts is rebuilt.
function CuePiece.applyHidden(self: CuePiece, modifier: number?)
	local base = modifier or 0
	for _, r in self.rigid do
		r.part.LocalTransparencyModifier = if self:hidden(r.joint) then 1 else base
	end
	for _, sk in self.skinned do
		local root = skinnedRoot(sk)
		local hidden = root ~= nil and self:hidden(root)
		for _, part in sk.parts do
			part.LocalTransparencyModifier = if hidden then 1 else base
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
	self:applyHidden()
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
	for _, d in self.model:GetDescendants() do
		if d:IsA("SurfaceAppearance") then
			d.EmissiveStrength *= emissiveScale
			if tint then
				d.Color = tint
			end
		end
	end
end

--- Every part of the piece follows `modifier` (a stick's camera fade), hidden joints staying
--- hidden.
function CuePiece.setModifier(self: CuePiece, modifier: number)
	self:applyHidden(modifier)
end

--- Uniform scale about the root (the pocket piece grows as it rises): sizes and every
--- position the joints give.
function CuePiece.setScale(self: CuePiece, scale: number)
	if math.abs(scale - self.scale) < 1e-4 then
		return
	end
	self.model:ScaleTo(math.max(scale, 0.01))
	self.scale = scale
end

function CuePiece.destroy(self: CuePiece)
	if self.qualityConnection then
		self.qualityConnection:Disconnect()
		self.qualityConnection = nil
	end
	self.model:Destroy()
end

return CuePiece
