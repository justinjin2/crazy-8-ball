--!strict
-- MenuTheme: a lively menu's own look over the house frame (Config.UI.Menu.Themes; MenuFrame.new's
-- `theme`). Only a menu that names a theme gets one: every other menu's frame is untouched.
--
-- "HauntedNight" (the Halloween event menu, designer's pick 2026-10-29): the panel's band and the
-- sheet turn deep purple (the sheet fading darker toward the bottom), the header's 8-balls and
-- the sheet's dots go faint lilac, the sheet's edge turns orange with an orange glow inside it
-- and a soft orange halo round the panel; in the header band, behind the title and the pills, a
-- soft glowing moon, a few faint stars drifting and twinkling, and a few small bats crossing with
-- their wings beating. Everything sits inside the panel's card, so it unrolls and folds with it
-- (the sky is clipped to the card, the glow to the sheet).
--
-- Motion: `idle` is one UIAnim loop (the shared per-frame step; no connection of its own), which
-- MenuFrame starts when the panel has landed and stops on close; at most LowFps steps a second
-- and the Low counts with Lower effects; Reduce Motion holds everything still at rest. Where
-- things are is MenuThemeMath (tested in Lune). Cost: 1 moon, 8 stars, 3 bats, 2 glows (Lower
-- effects 4 stars, 1 bat); four small textures (192, 96 x 48, 32, 96 px).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MenuThemeMath = require(Shared:WaitForChild("MenuThemeMath"))
local Quality = require(script.Parent.Quality)
local UIAnim = require(script.Parent.UIAnim)

local THEMES: { [string]: any } = (Config.UI.Menu :: any).Themes or {}
local K = Config.UI.Kit

local MenuTheme = {}

export type Theme = {
	config: any,
	sky: Frame, -- the card's box, clipping the band's pieces
	moon: ImageLabel?,
	stars: { ImageLabel },
	starTints: { Color3 },
	bats: { ImageLabel },
	glow: ImageLabel?, -- inside the sheet's edge
	halo: ImageLabel?, -- round the panel
	width: number, -- the panel's width (px)
	band: number, -- the band's height over the sheet (px)
	row: number, -- the header row's height (px)
	rowTop: number, -- its top (px)
	still: boolean, -- the last step drew the resting look (Reduce Motion)
}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function picture(parent: Instance, name: string, image: string, z: number): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Image = image
	label.ScaleType = Enum.ScaleType.Stretch
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.ZIndex = z
	label.Parent = parent
	return label
end

--- Whether `key` names a theme (Config.UI.Menu.Themes).
function MenuTheme.exists(key: string?): boolean
	return type(key) == "string" and type(THEMES[key]) == "table"
end

--- Dress a lively menu card (HudParts.menuCard made lively) in theme `key`; nil (and the card
--- untouched) for no such theme.
function MenuTheme.apply(card: Frame, key: string?): Theme?
	if not MenuTheme.exists(key) then
		return nil
	end
	local config = THEMES[key :: string]
	local images = config.Images
	local fill = card:FindFirstChild("Fill") :: Frame?
	local sheet = fill and fill:FindFirstChild("Sheet") :: Frame?
	if fill == nil or sheet == nil then
		return nil
	end
	-- The panel's band and the sheet: purple.
	local bandGradient = fill:FindFirstChildOfClass("UIGradient")
	if bandGradient then
		bandGradient.Color = ColorSequence.new(rgb(config.Band[1]), rgb(config.Band[2]))
	end
	local headerBalls = fill:FindFirstChild("Pattern")
	if headerBalls and headerBalls:IsA("ImageLabel") then
		headerBalls.ImageColor3 = rgb(config.HeaderTint)
		headerBalls.ImageTransparency = config.HeaderTransparency
		headerBalls.ZIndex = 0 -- under the sky
	end
	local sheetGradient = sheet:FindFirstChildOfClass("UIGradient")
	if sheetGradient then
		sheetGradient.Color = ColorSequence.new(rgb(config.Sheet[1]), rgb(config.Sheet[2]))
	end
	local edge = sheet:FindFirstChildOfClass("UIStroke")
	if edge then
		edge.Color = rgb(config.SheetEdge)
		edge.Thickness = config.SheetEdgePx
	end
	local dots = sheet:FindFirstChild("Pattern")
	if dots and dots:IsA("ImageLabel") then
		dots.ImageColor3 = rgb(config.DotsTint)
		dots.ImageTransparency = config.DotsTransparency
	end
	-- The orange glow inside the sheet's edge (over its dots, under the pages).
	local glow: ImageLabel? = nil
	if images.Edge ~= "" then
		local g = picture(sheet, "NightGlow", images.Edge, 2)
		local c = config.Edge.SliceCenter
		g.ScaleType = Enum.ScaleType.Slice
		g.SliceCenter = Rect.new(c[1], c[2], c[3], c[4])
		g.AnchorPoint = Vector2.zero
		g.Size = UDim2.fromScale(1, 1)
		g.ImageTransparency = config.Edge.Alpha[1]
		glow = g
	end
	-- The soft orange halo round the panel (behind the card, with its shadow).
	local halo: ImageLabel? = nil
	if K.Art.SoftGlow ~= "" then
		local H = config.Halo
		local h = picture(card, "NightHalo", K.Art.SoftGlow, -2) -- under the card's shadow
		h.ScaleType = Enum.ScaleType.Slice
		h.SliceCenter = Rect.new(127, 127, 129, 129)
		h.SliceScale = 2 * H.ReachPx / 128
		h.ImageColor3 = rgb(H.Tint)
		h.ImageTransparency = H.Alpha[1]
		h.AnchorPoint = Vector2.zero
		h.Position = UDim2.fromOffset(-H.ReachPx, -H.ReachPx)
		h.Size = UDim2.new(1, 2 * H.ReachPx, 1, 2 * H.ReachPx)
		halo = h
	end
	-- The sky: the card's box (it unrolls with it), the band's pieces clipped to it, over the
	-- band's 8-balls and under the sheet (which covers the sky's lower part).
	local sky = Instance.new("Frame")
	sky.Name = "NightSky"
	sky.BackgroundTransparency = 1
	sky.BorderSizePixel = 0
	sky.ClipsDescendants = true
	sky.Size = UDim2.fromScale(1, 1)
	sky.ZIndex = 1
	sky.Parent = fill
	local moon = if images.Moon ~= "" then picture(sky, "Moon", images.Moon, 1) else nil
	local stars: { ImageLabel } = {}
	local tints: { Color3 } = {}
	for _, hex in config.Stars.Tints :: { string } do
		table.insert(tints, Color3.fromHex(hex))
	end
	if images.Star ~= "" then
		for i = 1, math.max(config.Stars.Count, config.Stars.Low) do
			table.insert(stars, picture(sky, "Star" .. i, images.Star, 2))
		end
	end
	local bats: { ImageLabel } = {}
	if images.Bat ~= "" then
		for i = 1, math.max(config.Bats.Count, config.Bats.Low) do
			table.insert(bats, picture(sky, "Bat" .. i, images.Bat, 3))
		end
	end
	local theme: Theme = {
		config = config,
		sky = sky,
		moon = moon,
		stars = stars,
		starTints = tints,
		bats = bats,
		glow = glow,
		halo = halo,
		width = 1,
		band = 1,
		row = 1,
		rowTop = 0,
		still = false,
	}
	return theme
end

--- Place the moon and every piece at rest for a panel `width` px wide whose sheet starts
--- `sheetTop` px down, its header row `rowHeight` px tall from `rowTop` (MenuFrame.layout).
function MenuTheme.layout(
	theme: Theme,
	width: number,
	sheetTop: number,
	rowTop: number,
	rowHeight: number
)
	theme.width = math.max(1, width)
	theme.band = math.max(1, sheetTop)
	theme.row = math.max(1, rowHeight)
	theme.rowTop = rowTop
	local M = theme.config.Moon
	local moon = theme.moon
	if moon then
		local px = math.floor(rowHeight * M.OfHeader + 0.5)
		moon.Position = UDim2.fromOffset(
			math.floor(width * M.X + 0.5),
			math.floor(rowTop + rowHeight * M.Y + 0.5)
		)
		moon.Size = UDim2.fromOffset(px, px)
	end
	MenuTheme.step(theme, 0, Quality.isLow(), true)
end

--- One step at `clock` seconds: `low` with Lower effects, `still` with Reduce Motion (the
--- resting look, drawn once until motion comes back).
function MenuTheme.step(theme: Theme, clock: number, low: boolean, still: boolean)
	local config = theme.config
	local row, band, width = theme.row, theme.band, theme.width
	local moon = theme.moon
	if moon then
		moon.ImageTransparency =
			MenuThemeMath.breath(config.Moon.Alpha, config.Moon.Seconds, clock, still)
	end
	local glow = theme.glow
	if glow then
		glow.ImageTransparency =
			MenuThemeMath.breath(config.Edge.Alpha, config.Edge.Seconds, clock, still)
	end
	local halo = theme.halo
	if halo then
		halo.ImageTransparency =
			MenuThemeMath.breath(config.Halo.Alpha, config.Halo.Seconds, clock, still)
	end
	local starCount = MenuThemeMath.count(config.Stars, low)
	for i, label in theme.stars do
		local on = i <= starCount
		if label.Visible ~= on then
			label.Visible = on
		end
		if on then
			local s = MenuThemeMath.star(config, i, clock, still)
			local px = math.max(2, math.floor(s.size * row + 0.5))
			label.Position = UDim2.fromOffset(s.x * width, s.y * band)
			label.Size = UDim2.fromOffset(px, px)
			label.ImageTransparency = s.transparency
			local tint = theme.starTints[s.tint]
			if tint and label.ImageColor3 ~= tint then
				label.ImageColor3 = tint
			end
		end
	end
	local batCount = MenuThemeMath.count(config.Bats, low)
	for i, label in theme.bats do
		local on = i <= batCount
		if label.Visible ~= on then
			label.Visible = on
		end
		if on then
			local b = MenuThemeMath.bat(config, i, clock, still)
			local w = b.width * row
			label.Position = UDim2.fromOffset(b.x * width, b.y * band)
			label.Size = UDim2.fromOffset(w, w / 2 * b.flap)
			label.Rotation = b.rotation
		end
	end
	theme.still = still
end

--- The theme's idle loop (stop it with the handle; MenuFrame keeps it until the close).
function MenuTheme.idle(theme: Theme): UIAnim.Handle
	local lastStep = -math.huge
	return UIAnim.loop(theme.sky, function(clock: number)
		local low = Quality.isLow()
		local still = UIAnim.reduced()
		if still and theme.still then
			return -- already at rest
		end
		if low and clock - lastStep < 1 / theme.config.LowFps then
			return
		end
		lastStep = clock
		MenuTheme.step(theme, clock, low, still)
	end)
end

return MenuTheme
