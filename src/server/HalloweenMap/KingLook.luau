--!strict
-- KingLook (Halloween 2026, hw-map lane): the Pumpkin King's look (the approved
-- mocks/v2/P1_pumpkin_king.png), used by the bot at a table (BotService.playBoss's description,
-- icon, animations and dress) and by the figure on his throne alike, and the throne itself
-- at the piano's spot (an EventMap part: built once into ServerStorage, parented while Live).
--
-- Every piece is welded (WeldConstraint, so AvatarPose keeps them while he shoots), Massless
-- and touches nothing; the throne has one invisible collision box and nothing else collides.
-- The carved pumpkin (his head, the throne's back, the small pumpkins) and the crown are the
-- event's meshes (HalloweenMap/Assets); while they are not loaded, code-built shapes stand in. Real lights: his aura's one, the
-- throne's two (Config.HalloweenMap.Props.Budget.Lights).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Catalog = require(Shared:WaitForChild("Progression"):WaitForChild("Catalog"))
local Once = require(Shared:WaitForChild("HalloweenMap"):WaitForChild("Once"))
local Rules = require(Shared:WaitForChild("HalloweenMap"):WaitForChild("Rules"))
local Assets = require(script.Parent:WaitForChild("Assets"))

local HM = Config.HalloweenMap
local KL = HM.King
local T = HM.Throne

local KingLook = {}

local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- A plain decor part: anchored or not, touching nothing, no shadow.
local function piece(
	name: string,
	shape: Enum.PartType?,
	size: Vector3,
	colour: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.Color = colour
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	return p
end

local function weld(part: BasePart, to: BasePart, at: CFrame)
	part.CFrame = to.CFrame * at
	part.Anchored = false
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = part
	w.Parent = part
	part.Parent = to.Parent
end

-- A prop from the event's meshes (Assets: "Pumpkin", "Crown") laid out with its origin at
-- `cf`, each piece stretched by `scale` (studs per stud, per axis): welded to `to` (a body
-- part, `cf` in its space) or anchored into `parent` (`cf` in world space). False while the
-- meshes are not loaded (the caller builds its fallback shape).
local function prop(
	name: string,
	cf: CFrame,
	scale: Vector3,
	to: BasePart?,
	parent: Instance?
): boolean
	local model = Assets.clone(name)
	if model == nil then
		return false
	end
	if name == "Pumpkin" then
		-- A glowing core, so the carved holes glow straight on (the shell is one-sided).
		local c = Config.HalloweenMap.Assets
		local core = piece(
			"PumpkinCore",
			Enum.PartType.Ball,
			Vector3.new(c.PumpkinCore[1], c.PumpkinCore[2], c.PumpkinCore[3]) * scale,
			rgb(c.Glow.Pumpkin),
			Enum.Material.Neon
		)
		if to then
			weld(core, to, cf)
		else
			core.Anchored = true
			core.CFrame = cf
			core.Parent = parent
		end
	end
	local pivot = model:GetPivot()
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(part.CFrame)
			part.Size = part.Size * scale
			local at = cf * CFrame.new(rel.Position * scale) * rel.Rotation
			if to then
				weld(part, to, at)
			else
				part.Anchored = true
				part.CFrame = at
				part.Parent = parent
			end
		end
	end
	model:Destroy()
	return true
end

-- A carved face (two triangle eyes and a toothy grin) in Neon on the front (-Z) of a pumpkin
-- of size `size`, welded to `to` at `at` (the pumpkin's centre). Scaled by the pumpkin.
local function carve(to: BasePart, at: CFrame, size: Vector3, glow: Color3, prefix: string)
	local w, h, d = size.X, size.Y, size.Z
	local front = -d / 2 + d * 0.06
	local eye = Vector3.new(0.05 * d, h * 0.2, w * 0.2)
	for side = -1, 1, 2 do
		local e = Instance.new("WedgePart")
		e.Name = prefix .. "Eye"
		e.Size = eye
		e.Color = glow
		e.Material = Enum.Material.Neon
		e.CanCollide, e.CanQuery, e.CanTouch, e.CastShadow, e.Massless =
			false, false, false, false, true
		-- A wedge's slope faces +Z: turned to face out of the pumpkin's front, point up.
		weld(
			e,
			to,
			at * CFrame.new(side * w * 0.2, h * 0.12, front) * CFrame.Angles(0, math.rad(90), 0)
		)
	end
	local mouth = piece(
		prefix .. "Grin",
		nil,
		Vector3.new(w * 0.5, h * 0.13, 0.05 * d),
		glow,
		Enum.Material.Neon
	)
	weld(mouth, to, at * CFrame.new(0, -h * 0.16, front))
	for i = -1, 1 do
		local tooth = piece(
			prefix .. "Tooth",
			nil,
			Vector3.new(w * 0.07, h * 0.07, 0.06 * d),
			rgb(KL.Pumpkin)
		)
		weld(
			tooth,
			to,
			at
				* CFrame.new(
					i * w * 0.14,
					-h * 0.12 + (if i == 0 then -h * 0.05 else 0),
					front - 0.01
				)
		)
	end
end

--- The King's portrait for the match HUD (an image), or nil (the PC robot's).
function KingLook.icon(): string?
	return if KL.Icon ~= "" then KL.Icon else nil
end

--- His cue: Cues A's Jack-o'-Lantern Cue once its row exists, else an existing cue.
function KingLook.cue(): string?
	return if Catalog.exists(HM.Boss.Cue) then HM.Boss.Cue else nil -- nil: the bot's own pick
end

--- His animations (Body.build's keys), or nil for Config.Bots.Animations.
function KingLook.animations(): { [string]: string }?
	return KL.Animations
end

--- His body: a blocky R15 in a black suit (Config.HalloweenMap.King.Body).
function KingLook.description(): HumanoidDescription
	local d = Instance.new("HumanoidDescription")
	local B = KL.Body
	d.HeadColor = rgb(B.Head)
	d.TorsoColor = rgb(B.Torso)
	d.LeftArmColor = rgb(B.Arms)
	d.RightArmColor = rgb(B.Arms)
	d.LeftLegColor = rgb(B.Legs)
	d.RightLegColor = rgb(B.Legs)
	if KL.Shirt ~= 0 then
		d.Shirt = KL.Shirt
	end
	if KL.Pants ~= 0 then
		d.Pants = KL.Pants
	end
	return d
end

--- His aura on `root`: purple and orange flame wisps, embers and one orange light.
function KingLook.aura(root: BasePart)
	local A = HM.Boss.Aura
	for _, colour in { Color3.fromRGB(170, 70, 255), Color3.fromRGB(255, 122, 26) } do
		local fire = Instance.new("ParticleEmitter")
		fire.Name = "KingAura"
		fire.Texture = FIRE
		fire.Color = ColorSequence.new(colour)
		fire.LightEmission = 1
		fire.Rate = A.Rate
		fire.Lifetime = NumberRange.new(0.7, 1.1)
		fire.Speed = NumberRange.new(1, 2.5)
		fire.SpreadAngle = Vector2.new(25, 25)
		fire.Acceleration = Vector3.new(0, 3, 0)
		fire.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.4),
			NumberSequenceKeypoint.new(1, 0),
		})
		fire.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		})
		fire.Parent = root
	end
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "KingAura"
	embers.Texture = SPARKLE
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 190, 90))
	embers.LightEmission = 1
	embers.Rate = A.Rate / 3
	embers.Lifetime = NumberRange.new(1, 1.6)
	embers.Speed = NumberRange.new(1, 2)
	embers.SpreadAngle = Vector2.new(60, 60)
	embers.Acceleration = Vector3.new(0, 2, 0)
	embers.Size = NumberSequence.new(0.25)
	embers.Parent = root
	local light = Instance.new("PointLight")
	light.Name = "KingAura"
	light.Color = Color3.fromRGB(255, 140, 50)
	light.Range = A.LightRange
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = root
end

-- His pumpkin head on `head` (the R15 Head made see-through).
local function dressHead(head: BasePart)
	head.Transparency = 1
	for _, child in head:GetChildren() do
		if child:IsA("Decal") then
			child:Destroy()
		end
	end
	local size = Vector3.new(1.9, 1.55, 1.9)
	local at = CFrame.new(0, 0.12, 0)
	local meshed = prop("Pumpkin", at, Vector3.new(0.95, 0.85, 0.95), head)
	if not meshed then
		local shell = piece("PumpkinHead", Enum.PartType.Ball, size, rgb(KL.Pumpkin))
		weld(shell, head, at)
		carve(head, at, size, rgb(KL.Glow), "Head")
		local stem = piece(
			"PumpkinStem",
			Enum.PartType.Cylinder,
			Vector3.new(0.4, 0.22, 0.22),
			Color3.fromRGB(70, 90, 30)
		)
		weld(stem, head, at * CFrame.new(0, size.Y / 2, 0) * CFrame.Angles(0, 0, math.rad(90)))
	end
	-- The tilted gold crown with purple gems.
	local crownAt = at
		* CFrame.new(0.15, size.Y / 2 + (if meshed then KL.CrownOnMesh else 0.15), 0)
		* CFrame.Angles(0, 0, math.rad(-KL.CrownTiltDegrees))
	if prop("Crown", crownAt * CFrame.new(0, -0.1, 0), Vector3.one, head) then
		-- the purple gems at the points' feet (the .glb's points: Blender angle 72k degrees)
		for k = 0, 4 do
			local a = 2 * math.pi * k / 5
			local gem = piece(
				"CrownGem",
				Enum.PartType.Ball,
				Vector3.new(0.17, 0.17, 0.17),
				rgb(KL.Gem),
				Enum.Material.Neon
			)
			weld(gem, head, crownAt * CFrame.new(-math.cos(a) * 0.56, 0.08, math.sin(a) * 0.56))
		end
	else
		local band = piece(
			"Crown",
			Enum.PartType.Cylinder,
			Vector3.new(0.4, 1.05, 1.05),
			rgb(KL.Gold),
			Enum.Material.Metal
		)
		weld(band, head, crownAt * CFrame.Angles(0, 0, math.rad(90)))
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			local spike = Instance.new("WedgePart")
			spike.Name = "CrownPoint"
			spike.Size = Vector3.new(0.08, 0.35, 0.3)
			spike.Color = rgb(KL.Gold)
			spike.Material = Enum.Material.Metal
			spike.CanCollide, spike.CanQuery, spike.CanTouch, spike.CastShadow, spike.Massless =
				false, false, false, false, true
			weld(spike, head, crownAt * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.37, -0.45))
			local gem = piece(
				"CrownGem",
				Enum.PartType.Ball,
				Vector3.new(0.16, 0.16, 0.16),
				rgb(KL.Gem),
				Enum.Material.Neon
			)
			weld(
				gem,
				head,
				crownAt * CFrame.Angles(0, a + math.pi / 5, 0) * CFrame.new(0, 0, -0.53)
			)
		end
	end
end

-- The suit's pieces on the UpperTorso: vest, bow tie, chain, epaulettes, cape.
local function dressTorso(torso: BasePart)
	local s = torso.Size
	local vest = piece("Vest", nil, Vector3.new(s.X * 0.42, s.Y * 0.8, 0.04), rgb(KL.Vest))
	weld(vest, torso, CFrame.new(0, -s.Y * 0.05, -s.Z / 2 - 0.02))
	local bow = piece("BowTie", nil, Vector3.new(0.5, 0.22, 0.08), rgb(KL.Vest))
	weld(bow, torso, CFrame.new(0, s.Y * 0.4, -s.Z / 2 - 0.06))
	local knot = piece("BowKnot", nil, Vector3.new(0.14, 0.16, 0.1), rgb(KL.Gold))
	weld(knot, torso, CFrame.new(0, s.Y * 0.4, -s.Z / 2 - 0.1))
	local chain =
		piece("Chain", nil, Vector3.new(s.X * 0.5, 0.06, 0.05), rgb(KL.Gold), Enum.Material.Metal)
	weld(
		chain,
		torso,
		CFrame.new(0.05, -s.Y * 0.05, -s.Z / 2 - 0.05) * CFrame.Angles(0, 0, math.rad(-15))
	)
	for side = -1, 1, 2 do
		local ep =
			piece("Epaulette", Enum.PartType.Ball, Vector3.new(0.5, 0.42, 0.5), rgb(KL.Pumpkin))
		weld(ep, torso, CFrame.new(side * s.X * 0.48, s.Y * 0.5, 0))
		local eyes = piece(
			"EpauletteGlow",
			nil,
			Vector3.new(0.26, 0.08, 0.04),
			rgb(KL.Glow),
			Enum.Material.Neon
		)
		weld(eyes, torso, CFrame.new(side * s.X * 0.48, s.Y * 0.5, -0.25))
	end
	local capeAt = CFrame.new(0, s.Y * 0.45, s.Z / 2 + 0.08)
		* CFrame.Angles(math.rad(8), 0, 0)
		* CFrame.new(0, -1.5, 0)
	do
		local outside = piece(
			"Cape",
			nil,
			Vector3.new(s.X * 1.15, 3.1, 0.08),
			rgb(KL.Cape),
			Enum.Material.Fabric
		)
		weld(outside, torso, capeAt * CFrame.new(0, 0, 0.05))
		local lining = piece(
			"CapeLining",
			nil,
			Vector3.new(s.X * 1.05, 3.0, 0.04),
			rgb(KL.Lining),
			Enum.Material.Fabric
		)
		weld(lining, torso, capeAt)
		local trim = piece(
			"CapeTrim",
			nil,
			Vector3.new(s.X * 1.17, 0.12, 0.1),
			rgb(KL.Gold),
			Enum.Material.Metal
		)
		weld(trim, torso, capeAt * CFrame.new(0, -1.55, 0.05))
	end
end

--- Dress a body built from KingLook.description (BotService runs it before the body shows):
--- the pumpkin head, crown, suit pieces, cape and aura. Never yields long (meshes are cached).
function KingLook.dress(model: Model)
	local head = model:FindFirstChild("Head")
	local torso = model:FindFirstChild("UpperTorso")
	local root = model:FindFirstChild("HumanoidRootPart")
	if head and head:IsA("BasePart") then
		dressHead(head)
	end
	if torso and torso:IsA("BasePart") then
		dressTorso(torso)
	end
	if root and root:IsA("BasePart") then
		KingLook.aura(root)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			d.CastShadow = false
		end
	end
end

--- The King at a table (BotService's dress): his look, and in Timed mode Boss.Timed.TableScale
--- times a normal avatar. The bot code places his body by its pivot for a normal one, so the
--- pivot drops below his root by the extra hip height: his feet stay on the floor.
function KingLook.dressTable(model: Model)
	KingLook.dress(model)
	local scale = if Rules.kingTimed() then HM.Boss.Timed.TableScale else 1
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	if scale == 1 or hum == nil or root == nil or not root:IsA("BasePart") then
		return
	end
	local rise = (hum.HipHeight + root.Size.Y / 2) * (scale - 1)
	model:ScaleTo(scale)
	model.PrimaryPart = root
	root.PivotOffset = CFrame.new(0, -rise, 0)
end

-- A sceptre-like cue for the throne figure: black shaft, gold ferrule, a pumpkin at the butt.
local function sceptre(hand: BasePart)
	local shaft = piece(
		"KingCue",
		Enum.PartType.Cylinder,
		Vector3.new(5.2, 0.16, 0.16),
		Color3.fromRGB(20, 20, 24)
	)
	weld(shaft, hand, CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)))
	local ring = piece(
		"KingCueRing",
		Enum.PartType.Cylinder,
		Vector3.new(0.4, 0.2, 0.2),
		rgb(KL.Gold),
		Enum.Material.Metal
	)
	weld(ring, hand, CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, math.rad(90)))
	local butt =
		piece("KingCueButt", Enum.PartType.Ball, Vector3.new(0.55, 0.48, 0.55), rgb(KL.Pumpkin))
	weld(butt, hand, CFrame.new(0, -2.1, 0))
end

---------------------------------------------------------------------------------------------
-- The throne (Config.HalloweenMap.Throne): at the piano's spot, facing the spawn (+Z). Its
-- local space: the origin on the floor at the pivot, +Z toward the spawn.
---------------------------------------------------------------------------------------------

local holder: Folder? = nil -- ServerStorage: the built throne while not shown, and the piano while it is
local built: Model? = nil
local hidden: { { inst: Instance, parent: Instance } } = {}

local function storage(): Folder
	if holder == nil then
		local f = Instance.new("Folder")
		f.Name = "HalloweenThrone"
		f.Parent = ServerStorage
		holder = f
	end
	return holder :: Folder
end

-- The throne's pivot: at the piano (Throne), or his stage in the roof's middle (Boss.Mode
-- "Timed": Boss.Timed.Pivot, where the same throne fits the open cross between the tables).
local function pivot(): CFrame
	local at = if Rules.kingTimed() then HM.Boss.Timed else T
	local p = at.Pivot
	return CFrame.new(p[1], p[2], p[3]) * CFrame.Angles(0, math.rad(at.YawDegrees), 0)
end

--- Where the King's prompt anchor stands (Throne.PromptAt, kept at its place on the throne
--- when the throne stands elsewhere).
function KingLook.promptPosition(): Vector3
	local pa, tp = T.PromptAt, T.Pivot
	return (pivot() * CFrame.new(pa[1] - tp[1], pa[2] - tp[2], pa[3] - tp[3])).Position
end

-- An anchored throne part at local CFrame `at`.
local function place(model: Model, part: BasePart, at: CFrame)
	part.Anchored = true
	part.CFrame = pivot() * at
	part.Parent = model
end

local function buildThrone(): Model
	local model = Instance.new("Model")
	model.Name = "PumpkinThrone"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- seen from the spawn
	local purple, gold, black = rgb(KL.Cape), rgb(KL.Gold), Color3.fromRGB(26, 22, 32)
	-- The carpet toward the aisle, the steps, the seat.
	place(
		model,
		piece("Carpet", nil, Vector3.new(7, 0.06, 9), purple, Enum.Material.Fabric),
		CFrame.new(0, 0.03, 4.4)
	)
	place(
		model,
		piece("CarpetTrim", nil, Vector3.new(7.4, 0.04, 9.2), gold, Enum.Material.Metal),
		CFrame.new(0, 0.02, 4.4)
	)
	place(model, piece("Step1", nil, Vector3.new(8, 0.6, 1.6), black), CFrame.new(0, 0.3, 1.1))
	place(model, piece("Step2", nil, Vector3.new(7, 1.2, 1.6), black), CFrame.new(0, 0.6, -0.4))
	place(model, piece("SeatBase", nil, Vector3.new(6, 2.4, 3.6), black), CFrame.new(0, 1.2, -2.6))
	place(
		model,
		piece("SeatTrim", nil, Vector3.new(6.2, 0.2, 3.8), gold, Enum.Material.Metal),
		CFrame.new(0, 2.4, -2.6)
	)
	place(
		model,
		piece("Cushion", nil, Vector3.new(5.2, 0.7, 3), purple, Enum.Material.Fabric),
		CFrame.new(0, 2.85, -2.5)
	)
	for side = -1, 1, 2 do
		place(
			model,
			piece("Arm", nil, Vector3.new(0.9, 1.4, 3.4), purple, Enum.Material.Fabric),
			CFrame.new(side * 3, 3.1, -2.6)
		)
		place(
			model,
			piece("ArmCap", Enum.PartType.Ball, Vector3.new(1, 1, 1), gold, Enum.Material.Metal),
			CFrame.new(side * 3, 3.9, -1)
		)
	end
	-- The giant jack-o'-lantern back with its glowing grin.
	local backSize = Vector3.new(12, 10.5, 5.5)
	local backAt = CFrame.new(0, 7.6, -6.6)
	-- (the pumpkin faces -Z; the throne's front is +Z: half a turn)
	if
		not prop(
			"Pumpkin",
			pivot() * backAt * CFrame.Angles(0, math.pi, 0),
			Vector3.new(6, 5.6, 2.9),
			nil,
			model
		)
	then
		local shell = piece("ThroneBack", Enum.PartType.Ball, backSize, rgb(KL.Pumpkin))
		place(model, shell, backAt)
		for i = -2, 2 do
			if i ~= 0 then
				local rib = piece(
					"ThroneRib",
					Enum.PartType.Ball,
					Vector3.new(backSize.X * 0.34, backSize.Y * 1.0, backSize.Z * 0.96),
					rgb(KL.Pumpkin):Lerp(Color3.new(0, 0, 0), 0.08)
				)
				place(model, rib, backAt * CFrame.new(i * backSize.X * 0.17, 0, 0))
			end
		end
		-- The carved face on its front (+Z here: the pumpkin faces the spawn), so turn the
		-- carve (which cuts -Z) round.
		local anchor = piece("ThroneFaceAnchor", nil, Vector3.new(0.2, 0.2, 0.2), black)
		anchor.Transparency = 1
		place(model, anchor, backAt * CFrame.Angles(0, math.pi, 0))
		carve(anchor, CFrame.new(0, 1.2, 0), backSize, rgb(KL.Glow), "Throne")
		local stem = piece(
			"ThroneStem",
			Enum.PartType.Cylinder,
			Vector3.new(1.6, 1, 1),
			Color3.fromRGB(70, 90, 30)
		)
		place(
			model,
			stem,
			backAt * CFrame.new(0, backSize.Y / 2 + 0.4, 0) * CFrame.Angles(0, 0, math.rad(90))
		)
	end
	-- The crown on top.
	local crownAt = backAt * CFrame.new(0, backSize.Y / 2 + 1.6, 0)
	place(
		model,
		piece(
			"ThroneCrown",
			Enum.PartType.Cylinder,
			Vector3.new(1.4, 4.4, 4.4),
			gold,
			Enum.Material.Metal
		),
		crownAt * CFrame.Angles(0, 0, math.rad(90))
	)
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2
		local spike = Instance.new("WedgePart")
		spike.Name = "ThroneCrownPoint"
		spike.Size = Vector3.new(0.3, 1.4, 1.2)
		spike.Color = gold
		spike.Material = Enum.Material.Metal
		spike.CanCollide, spike.CanQuery, spike.CanTouch, spike.CastShadow =
			false, false, false, false
		place(model, spike, crownAt * CFrame.Angles(0, a, 0) * CFrame.new(0, 1.35, -1.9))
		place(
			model,
			piece(
				"ThroneGem",
				Enum.PartType.Ball,
				Vector3.new(0.6, 0.6, 0.6),
				rgb(KL.Gem),
				Enum.Material.Neon
			),
			crownAt * CFrame.Angles(0, a + math.pi / 7, 0) * CFrame.new(0, 0, -2.25)
		)
	end
	-- Candles and small pumpkins round the steps.
	for side = -1, 1, 2 do
		for k, spot in { { 4.6, 1.6, 2.2 }, { 5.6, 2.4, -1.4 } } do
			local x, h, z = side * spot[1], spot[2], spot[3]
			place(
				model,
				piece(
					"Candle",
					Enum.PartType.Cylinder,
					Vector3.new(h, 0.45, 0.45),
					Color3.fromRGB(240, 230, 210)
				),
				CFrame.new(x, h / 2, z) * CFrame.Angles(0, 0, math.rad(90))
			)
			place(
				model,
				piece(
					"CandleFlame",
					Enum.PartType.Ball,
					Vector3.new(0.28, 0.45, 0.28),
					rgb(KL.Glow),
					Enum.Material.Neon
				),
				CFrame.new(x, h + 0.22, z)
			)
			local small = Vector3.new(1.7, 1.35, 1.7) * (if k == 1 then 1 else 1.25)
			local pAt = CFrame.new(side * (spot[1] + 1.6), small.Y / 2, z + 1)
			local scale = small.X / 2
			local meshed = prop(
				"PumpkinSmall", -- one piece (the event budget); the King's head keeps the carved one
				pivot() * pAt * CFrame.Angles(0, math.pi + side * 0.4, 0),
				Vector3.new(scale, scale, scale),
				nil,
				model
			)
			if not meshed then
				local pumpkin = piece("SmallPumpkin", Enum.PartType.Ball, small, rgb(KL.Pumpkin))
				place(model, pumpkin, pAt)
				local face = piece("SmallPumpkinFace", nil, Vector3.new(0.2, 0.2, 0.2), black)
				face.Transparency = 1
				place(model, face, pAt * CFrame.Angles(0, math.pi, 0))
				carve(face, CFrame.new(), small, rgb(KL.Glow), "Small")
			end
		end
		-- The purple crest banners on black posts.
		local bx = side * 8.2
		place(
			model,
			piece("BannerPost", Enum.PartType.Cylinder, Vector3.new(10, 0.35, 0.35), black),
			CFrame.new(bx, 5, -5) * CFrame.Angles(0, 0, math.rad(90))
		)
		place(
			model,
			piece(
				"BannerTop",
				Enum.PartType.Ball,
				Vector3.new(0.7, 0.7, 0.7),
				gold,
				Enum.Material.Metal
			),
			CFrame.new(bx, 10.2, -5)
		)
		place(
			model,
			piece("Banner", nil, Vector3.new(2.6, 5.6, 0.1), purple, Enum.Material.Fabric),
			CFrame.new(bx, 6.4, -4.8)
		)
		place(
			model,
			piece("BannerTrim", nil, Vector3.new(2.7, 0.25, 0.12), gold, Enum.Material.Metal),
			CFrame.new(bx, 3.65, -4.8)
		)
		place(
			model,
			piece(
				"BannerCrest",
				Enum.PartType.Cylinder,
				Vector3.new(0.12, 1.4, 1.4),
				gold,
				Enum.Material.Metal
			),
			CFrame.new(bx, 7, -4.72) * CFrame.Angles(0, math.rad(90), 0)
		)
		place(
			model,
			piece(
				"BannerCrestEight",
				Enum.PartType.Ball,
				Vector3.new(0.75, 0.75, 0.2),
				Color3.fromRGB(20, 20, 24)
			),
			CFrame.new(bx, 7, -4.62)
		)
	end
	-- Two real lights: the grin's glow and a warm fill on the seat.
	local glow = piece("ThroneGlow", nil, Vector3.new(0.2, 0.2, 0.2), black)
	glow.Transparency = 1
	place(model, glow, backAt * CFrame.new(0, 0, 3.4))
	local l1 = Instance.new("PointLight")
	l1.Color = Color3.fromRGB(255, 150, 50)
	l1.Range = 16
	l1.Brightness = 1.4
	l1.Shadows = false
	l1.Parent = glow
	local fill = piece("ThroneFill", nil, Vector3.new(0.2, 0.2, 0.2), black)
	fill.Transparency = 1
	place(model, fill, CFrame.new(0, 6, 2))
	local l2 = Instance.new("PointLight")
	l2.Color = Color3.fromRGB(190, 120, 255)
	l2.Range = 12
	l2.Brightness = 0.8
	l2.Shadows = false
	l2.Parent = fill
	-- The one collision box (seat and back), invisible.
	local box = piece("ThroneCollision", nil, Vector3.new(12, 12, 9.5), black)
	box.Transparency = 1
	box.CanCollide = true
	box.Massless = false
	place(model, box, CFrame.new(0, 6, -5.4))
	-- The prompt's anchor (MapClient puts the ProximityPrompt on it).
	local prompt = piece("KingPrompt", nil, Vector3.new(1, 1, 1), black)
	prompt.Transparency = 1
	prompt.Anchored = true
	prompt.CFrame = CFrame.new(KingLook.promptPosition())
	prompt.Parent = model
	return model
end

-- The figure on the throne: the King himself, seated, sceptre-cue upright, his billboard; no
-- bot attributes (never in the player list or the bots' nameplates).
local function buildFigure(model: Model)
	local ok, body = pcall(function()
		return Players:CreateHumanoidModelFromDescription(
			KingLook.description(),
			Enum.HumanoidRigType.R15
		)
	end)
	if not ok or not body then
		warn("[HalloweenMap] the throne King's body failed: " .. tostring(body))
		return
	end
	local figure = body :: Model
	figure.Name = "ThroneKing"
	local hum = figure:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	KingLook.dress(figure)
	local hand = figure:FindFirstChild("RightHand")
	if hand and hand:IsA("BasePart") then
		sceptre(hand)
	end
	for _, d in figure:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local root = figure:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	-- On his stage he is Boss.Timed.Scale times a normal avatar (his hips stay on the cushion,
	-- 3.2 studs up, and his back against the seat's).
	local scale = if Rules.kingTimed() then HM.Boss.Timed.Scale else 1
	if scale ~= 1 then
		figure:ScaleTo(scale)
	end
	figure.PrimaryPart = root
	-- The arrow core's timer points with (the Pumpkin King's figure, in workspace while shown).
	CollectionService:AddTag(figure, "PumpkinKing")
	-- Facing the aisle (the throne's front is +Z: half a turn, as the pumpkin back).
	figure:PivotTo(
		pivot()
			* CFrame.new(0, 3.2 + 1.4 * scale, -2.3 - 0.4 * (scale - 1))
			* CFrame.Angles(0, math.pi, 0)
	)
	-- His name over his head.
	local head = figure:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local bb = Instance.new("BillboardGui")
		bb.Name = "KingName"
		bb.Size = UDim2.fromOffset(220, 44)
		bb.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
		bb.MaxDistance = 90
		bb.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = Strings.HalloweenMap.KingName
		label.TextColor3 = Color3.fromRGB(255, 196, 64)
		label.TextStrokeColor3 = Color3.fromRGB(30, 16, 48)
		label.TextStrokeTransparency = 0
		label.Parent = bb
		bb.Parent = head
	end
	figure.Parent = model
	-- Seated, from the server's Animator (replicates to every client).
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	local anim = Instance.new("Animation")
	anim.AnimationId = (KL.Animations and KL.Animations.Sit) or Config.Bots.Animations.Sit
	local played, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if played and track then
		track.Looped = true
		track:Play(0)
	end
end

-- The map's piano pieces (Config.HalloweenMap.Throne.Hide), put away while the throne stands.
local function hidePiano()
	local map = workspace:FindFirstChild(Config.Map.Name)
	if map == nil then
		return
	end
	for _, inst in map:GetDescendants() do
		for _, pattern in T.Hide do
			if inst.Name:match(pattern) and inst.Parent then
				table.insert(hidden, { inst = inst, parent = inst.Parent :: Instance })
				inst.Parent = storage()
				break
			end
		end
	end
end

local function showPiano()
	for i = #hidden, 1, -1 do
		local h = hidden[i]
		if h.parent.Parent ~= nil or h.parent == workspace then
			h.inst.Parent = h.parent
		end
	end
	table.clear(hidden)
end

-- The one build (Once): a second caller during the mesh wait waits for this build.
local throneBuild = Once.new(function(): boolean
	Assets.wait() -- the meshes (a fallback shape for any that never come)
	local model = buildThrone()
	buildFigure(model)
	model.Parent = storage()
	built = model
	return true
end)

-- Whether the throne should show: on sets it, off clears it, so an off during the build's
-- wait wins over the on still waiting.
local wanted = false

--- Build the throne and its figure once (yields for the body), kept in ServerStorage.
function KingLook.prepareThrone()
	throneBuild:run()
end

--- Put the throne up (yields for its build): at the piano, which goes away meanwhile, or on
--- the King's stage while he visits (Timed: the piano stays).
function KingLook.showThrone()
	wanted = true
	KingLook.prepareThrone()
	if not wanted then
		return
	end
	if not Rules.kingTimed() then
		hidePiano()
	end
	if built then
		built.Parent = workspace
	end
end

--- Take the throne down (the piano back if it went).
function KingLook.hideThrone()
	wanted = false
	if built then
		built.Parent = storage()
	end
	showPiano()
end

--- The throne as an EventMap part (on while Live, when Throne.Enabled), in Throne mode only:
--- in Timed mode BossService puts it up for each visit.
function KingLook.thronePart(): any
	return {
		name = "Throne",
		enabled = function(): boolean
			return T.Enabled and not Rules.kingTimed()
		end,
		on = KingLook.showThrone,
		off = KingLook.hideThrone,
	}
end

return KingLook
