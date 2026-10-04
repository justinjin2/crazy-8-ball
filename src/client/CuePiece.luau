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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CueSkins = require(Shared:WaitForChild("CueSkins"))
local Motion = require(Shared:WaitForChild("CueSkins"):WaitForChild("Motion"))

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

export type CuePiece = typeof(setmetatable(
	{} :: {
		id: string,
		model: Model,
		rig: Motion.Rig,
		rigid: { Rigid },
		skinned: { Skinned },
		riders: { Rider },
		auraJoints: { [string]: boolean },
		auraShown: boolean,
		scale: number,
		fade: number,
		pose: { [string]: Motion.Xf },
	},
	CuePiece
))

local WHITE = Color3.new(1, 1, 1)

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
function CuePiece.new(id: string, root: BasePart, parent: Instance): CuePiece?
	local row = CueSkins.piece(id)
	local source = template(id)
	if row == nil or source == nil then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Piece_" .. id
	local rig = Motion.rig(row)
	local auraJoints: { [string]: boolean } = {}
	for _, name in rig.order do
		local j = rig.joints[name]
		auraJoints[name] = j.aura or (j.parent ~= nil and auraJoints[j.parent] == true)
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
		auraJoints = auraJoints,
		auraShown = true,
		scale = 1,
		fade = 0,
		pose = {},
	}, CuePiece)
	self:step(0)
	return self
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
	weld.C0 = (if x then cframe(x, self.scale) else CFrame.identity) * rest
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

--- Move every joint to time `t` (seconds on the piece's clock).
function CuePiece.step(self: CuePiece, t: number)
	local pose = Motion.pose(self.rig, t)
	self.pose = pose
	local s = self.scale
	for _, r in self.rigid do
		if self.auraShown or not self.auraJoints[r.joint] then
			local x = pose[r.joint]
			local offset = if s == 1 then r.offset else CFrame.new(r.offset.Position * s) * FLIP
			r.weld.C0 = (if x then cframe(x, s) else CFrame.identity) * offset
		end
		if #r.visuals > 0 then
			applyVisuals(r, t, self.fade)
		end
	end
	for _, r in self.riders do
		local x = pose[r.joint]
		r.weld.C0 = (if x then cframe(x, s) else CFrame.identity) * r.rest
	end
	for _, sk in self.skinned do
		for _, b in sk.bones do
			if self.auraShown or not self.auraJoints[b.joint] then
				local x = Motion.jointDelta(pose, b.joint, b.parent)
				local rest = if s == 1
					then b.rest
					else CFrame.new(b.rest.Position * s) * b.rest.Rotation
				b.bone.Transform = rest:Inverse() * cframe(x, s) * rest
			end
		end
	end
end

-- A skinned model counts as aura when its root bone's joint is.
local function skinnedAura(self: CuePiece, sk: Skinned): boolean
	for _, b in sk.bones do
		if b.parent == nil then
			return self.auraJoints[b.joint] == true
		end
	end
	return false
end

--- Show or hide the aura joints (the shooter's turn hides them; LocalTransparencyModifier, so
--- nothing about the parts is rebuilt).
function CuePiece.setAura(self: CuePiece, shown: boolean)
	if shown == self.auraShown then
		return
	end
	self.auraShown = shown
	local modifier = if shown then 0 else 1
	for _, r in self.rigid do
		if self.auraJoints[r.joint] then
			r.part.LocalTransparencyModifier = modifier
		end
	end
	for _, sk in self.skinned do
		if skinnedAura(self, sk) then
			for _, part in sk.parts do
				part.LocalTransparencyModifier = modifier
			end
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

--- Every part of the piece follows `modifier` (a stick's camera fade), aura joints staying
--- hidden while the aura is.
function CuePiece.setModifier(self: CuePiece, modifier: number)
	for _, r in self.rigid do
		local hidden = not self.auraShown and self.auraJoints[r.joint]
		r.part.LocalTransparencyModifier = if hidden then 1 else modifier
	end
	for _, sk in self.skinned do
		local hidden = not self.auraShown and skinnedAura(self, sk)
		for _, part in sk.parts do
			part.LocalTransparencyModifier = if hidden then 1 else modifier
		end
	end
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
	self.model:Destroy()
end

return CuePiece
