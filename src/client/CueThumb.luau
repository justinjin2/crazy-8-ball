--!strict
-- CueThumb: a cue's picture for the inventory, the Index, the case reel, the shop and NEW RANK!
-- (docs/prompts/ECONOMY_UI_PROMPT.md section 10), and the rarity dressing of the cards that
-- hold them.
--
-- Thumbnails are stacked layer images that all share one canvas (Config.UI.Kit.Icons Cue*,
-- drawn by tools/gen_ui_art.py): the white layers are tinted with the catalog row's Look
-- colours (ImageColor3), so 44 cues need a handful of uploads, not 44. Bottom to top: the ink
-- outline and shadow (untinted), the shaft, the tip (the Classic cue's blue when the Look has
-- none), the joint ring, the forearm (or the house rainbow, untinted, for Look.Rainbow), the
-- accent band (only when the Look has one and no rainbow), the wrap, the butt cap (the wrap
-- darkened when the Look has none), and the gloss (untinted). A silhouette (the Index's
-- never-owned cues) is the one dark shape instead; if that image is missing, every layer is
-- tinted dark.
--
-- A cue with a skin (CueSkins) shows its rendered picture instead (one image, the cue on the
-- same diagonal with its surface, piece, aura and in-game outline; tools/cue_skin.py --thumb), drawn as one
-- dark shape for a silhouette; the layers stay for a cue with none (the Unique cues).
--
-- The dressing (CueThumb.dress) gives a card its rarity: a rarity-coloured edge inside its own
-- outline, a colour wash at its bottom and a strip across it. Mythic is pale and holographic:
-- a slow pastel shimmer over deep space with twinkling stars; Secret is the dark fill with a
-- slow red glow (UI_STYLE section 4; Secret's look is an overnight assumption). Their loops
-- share one clock and skip cards whose screen is switched off, so they stop with the menu.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Catalog = require(Shared:WaitForChild("Progression"):WaitForChild("Catalog"))
local CueSkins = require(Shared:WaitForChild("CueSkins"))

local K = Config.UI.Kit
local ICONS: { [string]: string } = K.Icons :: any
local RARITY: { [string]: { number } } = K.Rarity :: any
local R = Config.UI.Menu.Rarity
local T = Config.UI.Menu.Thumb
local TIER_COLORS: { [string]: { number } } = Config.Ranks.Colors :: any

local CueThumb = {}

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function darker(values: { number }, share: number): { number }
	return {
		math.floor(values[1] * share + 0.5),
		math.floor(values[2] * share + 0.5),
		math.floor(values[3] * share + 0.5),
	}
end

-- The layers, bottom to top, and the Kit.Icons key each draws.
local LAYERS: { { name: string, icon: string } } = {
	{ name = "Outline", icon = "CueOutline" },
	{ name = "Shaft", icon = "CueShaft" },
	{ name = "Tip", icon = "CueTip" },
	{ name = "Ring", icon = "CueRing" },
	{ name = "Forearm", icon = "CueForearm" },
	{ name = "Rainbow", icon = "CueRainbow" },
	{ name = "Accent", icon = "CueAccent" },
	{ name = "Wrap", icon = "CueWrap" },
	{ name = "Cap", icon = "CueCap" },
	{ name = "Gloss", icon = "CueGloss" },
	{ name = "Silhouette", icon = "CueSilhouette" },
}

local WHITE = Color3.new(1, 1, 1)

--------------------------------------------------------------------------------------------
-- Thumbnails
--------------------------------------------------------------------------------------------

--- A cue's thumbnail in a clear square Frame (size and place it yourself; the layers fit it).
--- An unknown id draws the Classic cue. `silhouette` draws the Index's dark "?" shape.
function CueThumb.new(parent: Instance, cueId: string, opts: { silhouette: boolean? }?): Frame
	local thumb = Instance.new("Frame")
	thumb.Name = "CueThumb"
	thumb.BackgroundTransparency = 1
	thumb.BorderSizePixel = 0
	thumb.Size = UDim2.fromScale(1, 1)
	for index, layer in LAYERS do
		local image = Instance.new("ImageLabel")
		image.Name = layer.name
		image.BackgroundTransparency = 1
		image.BorderSizePixel = 0
		image.ScaleType = Enum.ScaleType.Fit
		image.Size = UDim2.fromScale(1, 1)
		image.Image = ICONS[layer.icon] or ""
		image.ZIndex = index
		image.Parent = thumb
	end
	local picture = Instance.new("ImageLabel")
	picture.Name = "Picture"
	picture.BackgroundTransparency = 1
	picture.BorderSizePixel = 0
	picture.ScaleType = Enum.ScaleType.Fit
	picture.Size = UDim2.fromScale(1, 1)
	picture.ZIndex = #LAYERS + 1
	picture.Visible = false
	picture.Parent = thumb
	CueThumb.set(thumb, cueId, opts and opts.silhouette)
	thumb.Parent = parent
	return thumb
end

--- A cue's drawn picture (its skin's Thumb), or nil for a cue drawn from the layers.
function CueThumb.pictureOf(cueId: string): string?
	local row = Catalog.get(cueId)
	local skin = if row then CueSkins.index(row.Id) else nil
	return if skin ~= nil
			and type(skin.Thumb) == "string"
			and skin.Thumb ~= ""
		then skin.Thumb
		else nil
end

--- Draw another cue (or the same one as a silhouette) in a thumbnail made by CueThumb.new.
function CueThumb.set(thumb: Frame, cueId: string, silhouette: boolean?)
	local row = Catalog.get(cueId) or Catalog.get(Catalog.Default)
	if not row then
		return
	end
	local look = row.Look
	local shadow = silhouette == true
	local skin = CueSkins.index(row.Id)
	local picture = thumb:FindFirstChild("Picture") :: ImageLabel?
	local drawn = picture ~= nil and skin ~= nil and skin.Thumb ~= ""
	if picture then
		picture.Visible = drawn
		if drawn then
			picture.Image = skin.Thumb
			picture.ImageColor3 = if shadow then rgb(T.SilhouetteColor) else WHITE
		end
	end
	-- No silhouette image yet: the whole stack tinted dark reads as the same shape.
	local darkStack = shadow and (ICONS.CueSilhouette or "") == ""
	local tints: { [string]: { number }? } = {
		Shaft = look.Shaft,
		Tip = look.Tip or T.TipColor,
		Ring = look.Ring,
		Forearm = look.Forearm,
		Accent = look.Accent,
		Wrap = look.Wrap,
		Cap = look.Cap or darker(look.Wrap, T.CapShade),
	}
	local rainbow = look.Rainbow == true
	for _, child in thumb:GetChildren() do
		if not child:IsA("ImageLabel") then
			continue
		end
		local name = child.Name
		if name == "Picture" then
			continue
		end
		local visible: boolean
		if name == "Silhouette" then
			visible = not drawn and shadow and not darkStack
		elseif drawn or (shadow and not darkStack) then
			visible = false
		elseif name == "Forearm" then
			visible = not rainbow
		elseif name == "Rainbow" then
			visible = rainbow
		elseif name == "Accent" then
			visible = look.Accent ~= nil and not rainbow
		else
			visible = true
		end
		child.Visible = visible
		if darkStack then
			child.ImageColor3 = rgb(T.SilhouetteColor)
		else
			local tint = tints[name]
			child.ImageColor3 = if tint then rgb(tint) else WHITE
		end
	end
end

--------------------------------------------------------------------------------------------
-- Rarity colours
--------------------------------------------------------------------------------------------

--- A rarity's (or group's) colour: Common ... Secret, Exclusive, Unique, Default.
function CueThumb.rarityColor(rarity: string): Color3
	return rgb(RARITY[rarity] or RARITY.Default)
end

--- The colour a rarity shows on a light card and in words: its colour, but Secret's red glow
--- (its near-black would read as ink).
function CueThumb.accentColor(rarity: string): Color3
	if rarity == "Secret" then
		return rgb(K.SecretGlow)
	end
	return CueThumb.rarityColor(rarity)
end

--- A cue's colour for its card: its rarity's, but a rank cue shows its tier's (UI_STYLE 4's
--- note on Exclusive rank cues).
function CueThumb.cueColor(cueId: string): Color3
	local row = Catalog.get(cueId)
	if not row then
		return CueThumb.rarityColor("Default")
	end
	if row.Tier and TIER_COLORS[row.Tier] then
		return rgb(TIER_COLORS[row.Tier])
	end
	return CueThumb.accentColor(row.Rarity)
end

--- A cue's rarity (or group), "Default" for an unknown id.
function CueThumb.rarityOf(cueId: string): string
	local row = Catalog.get(cueId)
	return if row then row.Rarity else "Default"
end

--- A rarity's name for players ("Mythic"), from Strings.Items.Rarities.
function CueThumb.rarityName(rarity: string): string
	local names: { [string]: string } = Strings.Items.Rarities :: any
	return names[rarity] or rarity
end

--- A cue's name for players ("Starfall Cue"), from Strings.Items.Cues.
function CueThumb.cueName(cueId: string): string
	local names: { [string]: string } = Strings.Items.Cues :: any
	return names[cueId] or cueId
end

--------------------------------------------------------------------------------------------
-- The rarity dressing and its shared clock
--------------------------------------------------------------------------------------------

export type Dressing = {
	root: Frame,
	set: (rarity: string, tint: Color3?) -> (),
	destroy: () -> (),
}

-- What the clock moves on one dressed card.
type Moving = {
	root: Frame,
	gui: LayerCollector?,
	shimmer: UIGradient?, -- Mythic: turns slowly
	stars: { Frame }, -- Mythic: twinkle
	glowEdge: UIStroke?, -- Secret: breathes
	glowWash: Frame?,
}

local moving: { [Frame]: Moving } = {}
local clock: RBXScriptConnection? = nil

-- Evenly spread, fixed star spots (x, y as shares of the card), so every Mythic card twinkles
-- alike and nothing depends on randomness.
local STAR_SPOTS = {
	{ 0.18, 0.2 },
	{ 0.8, 0.14 },
	{ 0.62, 0.42 },
	{ 0.26, 0.58 },
	{ 0.86, 0.66 },
	{ 0.44, 0.12 },
	{ 0.12, 0.84 },
}

local function step()
	local now = os.clock()
	local empty = true
	for root, entry in moving do
		empty = false
		local gui = entry.gui
		if not gui then
			gui = root:FindFirstAncestorWhichIsA("LayerCollector")
			entry.gui = gui
		end
		-- Only while its screen is on and the card itself shows.
		if not gui or not gui.Enabled or not root.Visible then
			continue
		end
		local shimmer = entry.shimmer
		if shimmer then
			shimmer.Rotation = (now / R.ShimmerSeconds * 360) % 360
		end
		for i, star in entry.stars do
			local wave = 0.5 + 0.5 * math.sin((now / R.TwinkleSeconds + i * 0.37) * math.pi * 2)
			star.BackgroundTransparency = 0.15 + 0.85 * (1 - wave)
		end
		local breath = 0.5 + 0.5 * math.sin(now / R.GlowSeconds * math.pi * 2)
		local edge = entry.glowEdge
		if edge then
			edge.Transparency = R.GlowTransparency[2]
				+ (R.GlowTransparency[1] - R.GlowTransparency[2]) * breath
		end
		local wash = entry.glowWash
		if wash then
			wash.BackgroundTransparency = R.GlowWashTransparency[2]
				+ (R.GlowWashTransparency[1] - R.GlowWashTransparency[2]) * breath
		end
	end
	if empty and clock then
		clock:Disconnect()
		clock = nil
	end
end

local function watch(entry: Moving)
	moving[entry.root] = entry
	if not clock then
		clock = RunService.RenderStepped:Connect(step)
	end
end

local function layer(parent: Instance, name: string, inset: number, corner: UDim?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.BackgroundTransparency = 1
	frame.Position = UDim2.fromOffset(inset, inset)
	frame.Size = UDim2.new(1, -2 * inset, 1, -2 * inset)
	frame.ZIndex = 1
	if corner then
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(corner.Scale, math.max(0, corner.Offset - inset))
		round.Parent = frame
	end
	frame.Parent = parent
	return frame
end

--- Dress a card (`frame`: a card's face, such as MenuFrame.tile's `fill`) in a rarity. Its
--- layers sit over the card's own fill and under its contents (put contents at ZIndex 2 or
--- more, as the tile does). `tint` overrides the rarity's colour (a rank cue's tier colour:
--- CueThumb.cueColor). Returns the dressing: set(rarity, tint?) re-dresses it, destroy()
--- takes it off.
function CueThumb.dress(frame: GuiObject, rarity: string, tint: Color3?): Dressing
	local cornerObject = frame:FindFirstChildOfClass("UICorner")
	local corner = if cornerObject then cornerObject.CornerRadius else nil
	local root = layer(frame, "Rarity", 0, nil)

	local function clear()
		moving[root] = nil
		for _, child in root:GetChildren() do
			child:Destroy()
		end
	end

	local function set(name: string, override: Color3?)
		clear()
		local s = R.StrokePx
		local main = override or CueThumb.accentColor(name)
		local entry: Moving =
			{ root = root, gui = nil, shimmer = nil, stars = {}, glowEdge = nil, glowWash = nil }
		if name == "Mythic" then
			-- Deep space, the pastel shimmer turning over it, and twinkling stars.
			local space = layer(root, "Space", s, corner)
			space.BackgroundTransparency = 0
			space.BackgroundColor3 = rgb(K.MythicSpace)
			local sheen = layer(root, "Shimmer", s, corner)
			sheen.BackgroundTransparency = R.ShimmerTransparency
			sheen.BackgroundColor3 = WHITE
			local keys = {}
			local colours: { { number } } = K.MythicShimmer :: any
			for i, c in colours do
				table.insert(keys, ColorSequenceKeypoint.new((i - 1) / #colours, rgb(c)))
			end
			table.insert(keys, ColorSequenceKeypoint.new(1, rgb(colours[1])))
			local gradient = Instance.new("UIGradient")
			gradient.Color = ColorSequence.new(keys)
			gradient.Parent = sheen
			entry.shimmer = gradient
			for i = 1, math.min(R.Stars, #STAR_SPOTS) do
				local spot = STAR_SPOTS[i]
				local star = Instance.new("Frame")
				star.Name = "Star"
				star.BorderSizePixel = 0
				star.BackgroundColor3 = WHITE
				star.AnchorPoint = Vector2.new(0.5, 0.5)
				star.Position = UDim2.fromScale(spot[1], spot[2])
				star.Size = UDim2.fromOffset(R.StarPx, R.StarPx)
				star.ZIndex = 1
				local roundStar = Instance.new("UICorner")
				roundStar.CornerRadius = UDim.new(0.5, 0)
				roundStar.Parent = star
				star.Parent = root
				table.insert(entry.stars, star)
			end
		elseif name == "Secret" then
			-- The dark fill, and a red glow breathing at its bottom and round its edge.
			local dark = layer(root, "Dark", s, corner)
			dark.BackgroundTransparency = 0
			dark.BackgroundColor3 = CueThumb.rarityColor("Secret")
			local wash = layer(root, "Glow", s, corner)
			wash.BackgroundTransparency = R.GlowWashTransparency[2]
			wash.BackgroundColor3 = rgb(K.SecretGlow)
			local fade = Instance.new("UIGradient")
			fade.Rotation = 90
			fade.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(R.TintFromShare, 1),
				NumberSequenceKeypoint.new(1, 0),
			})
			fade.Parent = wash
			entry.glowWash = wash
		else
			-- A wash of the colour rising from the card's bottom.
			local wash = layer(root, "Wash", s, corner)
			wash.BackgroundTransparency = 0
			wash.BackgroundColor3 = main
			local fade = Instance.new("UIGradient")
			fade.Rotation = 90
			fade.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(R.TintFromShare, 1),
				NumberSequenceKeypoint.new(1, R.TintTransparency),
			})
			fade.Parent = wash
		end
		-- The edge inside the card's own outline, in the colour.
		local rim = layer(root, "Edge", s, corner)
		local edge = Instance.new("UIStroke")
		edge.Color = if name == "Mythic" then CueThumb.rarityColor("Mythic") else main
		edge.Thickness = s
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Parent = rim
		if name == "Secret" then
			entry.glowEdge = edge
		end
		-- The strip across the bottom.
		local strip = Instance.new("Frame")
		strip.Name = "Strip"
		strip.BorderSizePixel = 0
		strip.BackgroundColor3 = if name == "Mythic" then WHITE else main
		strip.AnchorPoint = Vector2.new(0.5, 1)
		strip.Position = UDim2.new(0.5, 0, 1, -(s + 2))
		strip.Size = UDim2.fromScale(1 - 2 * R.StripInsetShare, R.StripShare)
		strip.ZIndex = 1
		local roundStrip = Instance.new("UICorner")
		roundStrip.CornerRadius = UDim.new(0.5, 0)
		roundStrip.Parent = strip
		if name == "Mythic" then
			local sheen = Instance.new("UIGradient")
			sheen.Color = (entry.shimmer :: UIGradient).Color
			sheen.Parent = strip
		end
		strip.Parent = root
		if entry.shimmer or entry.glowEdge then
			watch(entry)
		end
	end

	root.Destroying:Connect(function()
		moving[root] = nil
	end)
	set(rarity, tint)
	return {
		root = root,
		set = set,
		destroy = function()
			clear()
			root:Destroy()
		end,
	}
end

return CueThumb
