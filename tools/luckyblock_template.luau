-- Turns uploaded lucky block models (tools/luckyblock_build.py's glbs) into their templates in
-- ReplicatedStorage.LuckyBlocks (designer, 2026-10-07). An Edit-mode command, not a script: paste
-- it into the Studio MCP's execute_luau (Edit), with ONLY set to the template names to rebuild
-- (nil rebuilds all). Every SurfaceAppearance map can only be set in Edit (docs/STUDIO_NOTES.md),
-- so the templates live in the place: save and publish after a run.
--
-- Each MeshPart's colour map is the image the glb upload made (its TextureID), moved into a
-- SurfaceAppearance with a roughness map (the gloss) and the white emissive mask every block
-- uses (assets/luckyblocks/Readme.md, "Rooftop look"). The pack's glow particles and light (from
-- YellowLuckyBlock) go on the RootPart, tinted per kind, and each kind adds its own particles
-- (tools/luckyblock_sprites.py's sprites).

local ONLY: { [string]: boolean }? = nil

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- { Asset = <model id>, Tint = Color3? (the pack particles and light), Scroll = <image>? (a
--   moving texture on every face of the frame, tagged for LuckyWorld), Extra = { <emitter> } }
local BLOCKS = {
	StandardBlock = { Asset = 113193396541681, Extra = {} }, -- v5: beige rims, brown faces
	UncommonBlock = { Asset = 94210612552833, Tint = rgb(130, 255, 150), Extra = { "Leaves", "GreenTwinkles" } },
	RareBlock = { Asset = 108972427994896, Tint = rgb(120, 190, 255), Extra = { "Bubbles", "BlueTwinkles" } },
	EpicBlock = { Asset = 99183682386093, Tint = rgb(196, 128, 255), Extra = { "Sparks", "Motes" } },
	LegendaryBlock = { Asset = 97519713909243, Tint = rgb(255, 176, 70), Extra = { "Embers", "GoldFeathers" } },
	GrandOpeningBlock = { Asset = 126115756520229, Tint = rgb(255, 214, 96), Extra = { "PartyConfetti", "GoldTwinkles" } },
	EightBallBlock = { Asset = 89229796360554, Extra = { "MiniBalls", "WhiteTwinkles" } },
	StarterBlock = { Asset = 74890867189012, Tint = rgb(255, 110, 100), Extra = { "GiftConfetti", "GoldTwinkles" } },
	GiftBlock = { Asset = 86403411186613, Tint = rgb(255, 220, 120), Extra = { "GoldTwinkles", "GoldConfetti" } },
	MythicBlock = { Asset = 78926971295305, Tint = rgb(255, 196, 236), Extra = { "PastelTwinkles", "PastelFeathers" } },
	SkyBlock = { Asset = 91079315755859, Tint = rgb(176, 222, 255), Extra = { "CloudPuffs", "WhiteFeathers" } },
	MysteryBlock = { Asset = 131944205075030, Scroll = "RAINBOW", Extra = { "RainbowTwinkles" } }, -- v3
}
local IMAGES = {
	RAINBOW = "rbxassetid://107891048379160", -- textures/rainbow_scroll.png (decal 121880113191370)
}
-- particles/*.png (tools/luckyblock_sprites.py), image ids from their decals.
local SPRITE = {
	Twinkle = "rbxassetid://93784382803534", -- the cue skins' white twinkle (Config, Sparkle)
	Ball8 = "rbxassetid://132995437184043",
	Bubble = "rbxassetid://84209151109662",
	Confetti = "rbxassetid://97972156068128",
	Ember = "rbxassetid://121486915965496",
	Feather = "rbxassetid://77217970540986",
	Leaf = "rbxassetid://84420758908393",
	Puff = "rbxassetid://108727667390410",
	Spark = "rbxassetid://108916634623762",
}
local SCROLL_TAG = "LuckyScroll" -- Config.LuckyBlocks.Look.Scroll.Tag

local function sequence(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keys = {}
	for i, c in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(keys)
end
local RAINBOW = {}
for i = 0, 6 do
	table.insert(RAINBOW, Color3.fromHSV((i / 6) % 1, 0.75, 1))
end
local PASTEL = { rgb(255, 196, 228), rgb(214, 196, 255), rgb(190, 246, 222), rgb(190, 226, 255) }

-- Size grows in, holds and shrinks out: peak `s` studs.
local function pop(s: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.25, s),
		NumberSequenceKeypoint.new(0.8, s),
		NumberSequenceKeypoint.new(1, 0),
	})
end

type Spec = {
	Texture: string,
	Colors: { Color3 },
	Rate: number,
	Life: { number },
	Speed: { number },
	Size: number,
	Up: number?, -- acceleration up (negative falls)
	From: string?, -- "Frame" (default), "Top" (the frame's top face), "Wings", "Base"
	Spin: number?,
	Glow: number?,
}
-- Our own particles by name, added to the pack's glow set.
local EMITTERS: { [string]: Spec } = {
	RainbowTwinkles = { Texture = SPRITE.Twinkle, Colors = RAINBOW, Rate = 4, Life = { 1.2, 1.8 }, Speed = { 0.6, 1.2 }, Size = 0.35, Up = 0.8, Spin = 90, Glow = 0.8 },
	GreenTwinkles = { Texture = SPRITE.Twinkle, Colors = { rgb(170, 255, 170) }, Rate = 3, Life = { 1, 1.6 }, Speed = { 0.5, 1 }, Size = 0.3, Up = 0.8, Spin = 90, Glow = 0.8 },
	BlueTwinkles = { Texture = SPRITE.Twinkle, Colors = { rgb(170, 220, 255) }, Rate = 3, Life = { 1, 1.6 }, Speed = { 0.5, 1 }, Size = 0.3, Up = 0.8, Spin = 90, Glow = 0.8 },
	GoldTwinkles = { Texture = SPRITE.Twinkle, Colors = { rgb(255, 222, 110) }, Rate = 5, Life = { 1, 1.6 }, Speed = { 0.5, 1 }, Size = 0.35, Up = 0.8, Spin = 90, Glow = 0.9 },
	WhiteTwinkles = { Texture = SPRITE.Twinkle, Colors = { rgb(255, 255, 255) }, Rate = 3, Life = { 1, 1.6 }, Speed = { 0.5, 1 }, Size = 0.3, Up = 0.8, Spin = 90, Glow = 0.8 },
	PastelTwinkles = { Texture = SPRITE.Twinkle, Colors = PASTEL, Rate = 6, Life = { 1.2, 1.8 }, Speed = { 0.5, 1 }, Size = 0.38, Up = 0.8, Spin = 90, Glow = 0.9 },
	Leaves = { Texture = SPRITE.Leaf, Colors = { rgb(120, 230, 110), rgb(70, 190, 80) }, Rate = 2.5, Life = { 1.8, 2.6 }, Speed = { 0.6, 1.1 }, Size = 0.42, Up = 0.6, Spin = 140 },
	Bubbles = { Texture = SPRITE.Bubble, Colors = { rgb(190, 230, 255) }, Rate = 3, Life = { 1.6, 2.4 }, Speed = { 0.3, 0.6 }, Size = 0.38, Up = 1.4, Spin = 0, Glow = 0.4 },
	Sparks = { Texture = SPRITE.Spark, Colors = { rgb(226, 190, 255), rgb(170, 100, 255) }, Rate = 7, Life = { 0.15, 0.3 }, Speed = { 0, 0.2 }, Size = 0.55, Spin = 0, Glow = 1 },
	Motes = { Texture = SPRITE.Ember, Colors = { rgb(200, 140, 255) }, Rate = 6, Life = { 1.2, 1.8 }, Speed = { 0.4, 0.9 }, Size = 0.28, Up = 1, Glow = 1 },
	Embers = { Texture = SPRITE.Ember, Colors = { rgb(255, 220, 120), rgb(255, 140, 40) }, Rate = 10, Life = { 1, 1.6 }, Speed = { 0.6, 1.2 }, Size = 0.24, Up = 1.5, Glow = 1 },
	GoldFeathers = { Texture = SPRITE.Feather, Colors = { rgb(255, 222, 130) }, Rate = 1.2, Life = { 2.5, 3.5 }, Speed = { 0.2, 0.5 }, Size = 0.5, Up = -0.6, From = "Wings", Spin = 60 },
	PastelFeathers = { Texture = SPRITE.Feather, Colors = PASTEL, Rate = 1.4, Life = { 2.5, 3.5 }, Speed = { 0.2, 0.5 }, Size = 0.5, Up = -0.6, From = "Wings", Spin = 60 },
	WhiteFeathers = { Texture = SPRITE.Feather, Colors = { rgb(255, 255, 255) }, Rate = 1.2, Life = { 2.5, 3.5 }, Speed = { 0.2, 0.5 }, Size = 0.45, Up = -0.6, From = "Wings", Spin = 60 },
	PartyConfetti = { Texture = SPRITE.Confetti, Colors = { rgb(255, 90, 110), rgb(255, 210, 70), rgb(90, 200, 255), rgb(140, 230, 120) }, Rate = 5, Life = { 1.8, 2.4 }, Speed = { 2.2, 3 }, Size = 0.28, Up = -3, From = "Top", Spin = 300 },
	GiftConfetti = { Texture = SPRITE.Confetti, Colors = { rgb(255, 80, 80), rgb(255, 214, 80) }, Rate = 4, Life = { 1.8, 2.4 }, Speed = { 2, 2.8 }, Size = 0.28, Up = -3, From = "Top", Spin = 300 },
	GoldConfetti = { Texture = SPRITE.Confetti, Colors = { rgb(255, 214, 80), rgb(255, 255, 255) }, Rate = 2.5, Life = { 1.8, 2.4 }, Speed = { 2, 2.8 }, Size = 0.26, Up = -3, From = "Top", Spin = 300 },
	MiniBalls = { Texture = SPRITE.Ball8, Colors = { rgb(255, 255, 255) }, Rate = 1.2, Life = { 2.2, 3 }, Speed = { 0.4, 0.8 }, Size = 0.55, Up = 0.5, Spin = 90 },
	CloudPuffs = { Texture = SPRITE.Puff, Colors = { rgb(255, 255, 255) }, Rate = 1.5, Life = { 2.5, 3.5 }, Speed = { 0.2, 0.4 }, Size = 1.1, Up = 0.15, From = "Base", Spin = 10 },
}

local function emitter(name: string, spec: Spec): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = spec.Texture
	e.Color = sequence(spec.Colors)
	e.Rate = spec.Rate
	e.Lifetime = NumberRange.new(spec.Life[1], spec.Life[2])
	e.Speed = NumberRange.new(spec.Speed[1], spec.Speed[2])
	e.Size = pop(spec.Size)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.75, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Rotation = NumberRange.new(0, 360)
	local spin = spec.Spin or 0
	e.RotSpeed = NumberRange.new(-spin, spin)
	e.Acceleration = Vector3.new(0, spec.Up or 0, 0)
	e.LightEmission = spec.Glow or 0
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	if spec.From == "Top" then
		e.EmissionDirection = Enum.NormalId.Top
		e.SpreadAngle = Vector2.new(35, 35)
	else
		e.SpreadAngle = Vector2.new(180, 180)
	end
	return e
end

local ROUGH = {
	Glossy = "rbxassetid://98760410664616", -- rough_022.png
	Satin = "rbxassetid://120409166438752", -- rough_045.png
}
local PIECE_ROUGH = { Glyph = "Satin", Base = "Satin", WingL = "Satin", WingR = "Satin" }
local EMISSIVE_MASK = "rbxassetid://104192408636466" -- textures/neutral_mask.png

local IS = game:GetService("InsertService")
local folder = game.ReplicatedStorage.LuckyBlocks
local vfxSource = folder.YellowLuckyBlock:FindFirstChild("VFX", true)

local report = {}
for name, b in BLOCKS do
	if ONLY and not ONLY[name] then
		continue
	end
	local model = IS:LoadAsset(b.Asset):FindFirstChildOfClass("Model")
	model.Name = name
	local poses = model:FindFirstChild("InitialPoses")
	if poses then
		poses:Destroy()
	end
	local root = model:FindFirstChild("RootPart")
	root.Transparency = 1
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.CanCollide = false
	model.PrimaryPart = root
	for _, part in model:GetChildren() do
		if part:IsA("MeshPart") then
			part.Name = part.Name:gsub("%.%d+$", "") -- Blender's "Glyph.001"
			local sa = Instance.new("SurfaceAppearance")
			sa.ColorMapContent = Content.fromUri(part.TextureID)
			sa.RoughnessMapContent = Content.fromUri(ROUGH[PIECE_ROUGH[part.Name] or "Glossy"])
			sa.EmissiveMaskContent = Content.fromUri(EMISSIVE_MASK)
			sa.EmissiveTint = Color3.new(1, 1, 1)
			sa.AlphaMode = Enum.AlphaMode.Overlay
			sa.Parent = part
			part.TextureID = ""
			part.Color = Color3.new(1, 1, 1)
			part.CanCollide = false
		end
	end
	local controller = model:FindFirstChildOfClass("AnimationController")
		or Instance.new("AnimationController", model)
	if not controller:FindFirstChildOfClass("Animator") then
		Instance.new("Animator", controller)
	end
	-- The pivot at the bottom centre of the block itself (wings and toppers left out; the cloud
	-- counts, the block sits on it), as the pack's blocks: the game sets blocks down by it.
	local frame = model:FindFirstChild("Frame") :: BasePart
	local bottom = frame.Position - Vector3.new(0, frame.Size.Y / 2, 0)
	local base = model:FindFirstChild("Base") :: BasePart?
	if base then
		bottom = Vector3.new(bottom.X, base.Position.Y - base.Size.Y / 2, bottom.Z)
	end
	root.PivotOffset = CFrame.new(root.CFrame:PointToObjectSpace(bottom))
	local vfx = vfxSource:Clone()
	vfx.Position = Vector3.zero
	if b.Tint then
		for _, d in vfx:GetDescendants() do
			if d:IsA("ParticleEmitter") then
				d.Color = ColorSequence.new(b.Tint)
			elseif d:IsA("Light") then
				d.Color = b.Tint
			end
		end
	end
	vfx.Parent = root
	-- On a part, so a Box emitter spawns over that part's surface, not inside the block.
	for _, extra in b.Extra or {} do
		local spec = EMITTERS[extra]
		local from = spec.From
		local parts = if from == "Wings"
			then { model:FindFirstChild("WingL"), model:FindFirstChild("WingR") }
			elseif from == "Base" then { model:FindFirstChild("Base") }
			else { frame }
		for _, part in parts do
			local e = emitter(extra, spec)
			if from == "Wings" then
				e.Rate /= 2
			end
			e.Parent = part
		end
	end
	if b.Scroll then
		for _, face in Enum.NormalId:GetEnumItems() do
			local t = Instance.new("Texture")
			t.Name = "Scroll" .. face.Name
			t.Face = face
			t.Texture = IMAGES[b.Scroll]
			t.StudsPerTileU = 6
			t.StudsPerTileV = 6
			t.Parent = frame
			t:AddTag(SCROLL_TAG)
		end
	end
	local old = folder:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	model.Parent = folder
	local _, size = model:GetBoundingBox()
	table.insert(report, ("%s: %d parts, box %.1f x %.1f x %.1f"):format(name, #model:GetDescendants(), size.X, size.Y, size.Z))
end
table.sort(report)
return table.concat(report, "\n")
