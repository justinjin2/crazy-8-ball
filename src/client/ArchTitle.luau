--!strict
-- ArchTitle: title words set letter by letter on a gentle arch, each letter its own small
-- group of real text layers (the lively Shop's "GRAND OPENING" and its subtitle, after 13b's
-- painted title; styles in Config.UI.Kit.ArchTitle). From the bottom up a letter has:
--   * a rim (optional): the letter with a wide stroke in the rim colour, a glow round the word,
--   * the outline: the letter (and its copy moved down by the depth) with a thick ink stroke,
--     so the outlines of neighbouring letters merge into one shape,
--   * the depth (optional): the letter moved down in a darker colour (the 3D extrusion),
--   * the face: the letter in the style's gradient or plain colour.
-- Each layer is its own frame holding every letter's copy, so a whole layer draws before the
-- next (menus use Sibling ZIndex, which orders siblings only) and a letter's face never hides
-- under its neighbour's outline. The words are real text (translatable); each letter is
-- measured and placed, so the word keeps its natural spacing. Letters opt out of HoleFill
-- (they draw their own outline and lip). Text never moves slowly: a letter pops (UIScale) and
-- may rock (Rotation), both smooth.
--
-- ArchTitle.new(parent, text, style, size, tints?) returns { root, letters, width, height }:
-- `root` is a frame sized to the whole title (the caller places it); `letters[i]` holds the
-- letter's holders, one per layer, all centred on it (pop them together); spaces have none.
-- `tints[i]` gives the i-th character (spaces counted) a plain face colour of its own (with a
-- ByWord style, a word takes its first character's tint).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local K = Config.UI.Kit

local ArchTitle = {}

export type Title = {
	root: Frame,
	letters: { { Frame } },
	width: number,
	height: number,
}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function fontOf(S: any): Font
	if S.Font then
		return Font.new(
			"rbxasset://fonts/families/" .. S.Font.Family .. ".json",
			(Enum.FontWeight :: any)[S.Font.Weight]
		)
	end
	return Font.fromEnum((Enum.Font :: any)[K.Font])
end

-- A character's advance at `size` in `face` (cached: titles reuse their letters).
local widthCache: { [string]: number } = {}
local function charWidth(char: string, size: number, face: Font): number
	local key = face.Family .. "|" .. face.Weight.Name .. "|" .. size .. "|" .. char
	local cached = widthCache[key]
	if cached then
		return cached
	end
	local params = Instance.new("GetTextBoundsParams")
	params.Text = char
	params.Font = face
	params.Size = size
	params.Width = 10000
	local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
	local width = if ok then bounds.X else size * 0.6
	widthCache[key] = width
	return width
end

local function layer(
	parent: Instance,
	name: string,
	char: string,
	size: number,
	face: Font,
	tint: Color3,
	dy: number
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.FontFace = face
	label.Text = char
	label.TextSize = size
	label.TextScaled = false
	label.TextColor3 = tint
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.5, dy)
	label.Size = UDim2.fromScale(1, 1)
	label:SetAttribute("NoHoleFill", true)
	label.Parent = parent
	return label
end

local function stroke(label: TextLabel, tint: Color3, thickness: number, transparency: number?)
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Color = tint
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.Parent = label
end

--- Build `text` in `style` (a Config.UI.Kit.ArchTitle key) at `size` px under `parent`.
function ArchTitle.new(
	parent: Instance,
	text: string,
	style: string,
	size: number,
	tints: { [number]: Color3 }?
): Title
	local styles: any = K.ArchTitle
	local S: any = styles[style] or styles.Gold
	if S.Base then
		-- A variant: its own fields over its base style's.
		S = setmetatable(table.clone(S), { __index = styles[S.Base] })
	end
	local face = fontOf(S)
	local outline = math.max(1.5, size * S.OutlineShare)
	local rim = if S.Rim then outline + math.max(1, size * S.RimShare) else 0
	local depth = if S.Extrude then math.max(1, size * S.ExtrudeShare) else 0
	local tracking = size * S.TrackingShare

	-- The units placed on the arch: each letter, or each word with the space after it for a
	-- style set ByWord (small text, where a word keeps its kerning better than its letters).
	-- `first[i]` is the unit's first character's index, for `tints`.
	local chars: { string } = {}
	local first: { number } = {}
	if S.ByWord then
		local index = 1
		for found, spaces in string.gmatch(text, "([^ ]+)( *)") do
			local word: string = found :: any
			local gap: string = spaces :: any
			table.insert(chars, word)
			table.insert(first, index)
			index += utf8.len(word) :: number
			if gap ~= "" then
				table.insert(chars, gap)
				table.insert(first, index)
				index += #gap
			end
		end
	else
		for _, code in utf8.codes(text) do
			table.insert(chars, utf8.char(code))
			table.insert(first, #chars)
		end
	end
	local widths: { number } = {}
	local total = 0
	for i, char in chars do
		widths[i] = charWidth(char, size, face)
		total += widths[i] + (if i < #chars then tracking else 0)
	end

	-- The arch: a circle through the word's ends, its middle `sag` higher.
	local sag = math.max(0.5, total * S.SagShare)
	local radius = (total * total) / (8 * sag) + sag / 2
	local pad = math.max(rim, outline) + 2
	local boxH = size * 1.25
	local width = math.ceil(total + 2 * pad + size * 0.2)
	local height = math.ceil(boxH + sag + 2 * pad + depth)

	local root = Instance.new("Frame")
	root.Name = "ArchTitle"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromOffset(width, height)
	root.Parent = parent

	local gradient: ColorSequence? = nil
	if S.Face then
		local keys = {}
		for _, k in S.Face do
			table.insert(keys, ColorSequenceKeypoint.new(k.At, rgb(k.Color)))
		end
		gradient = ColorSequence.new(keys)
	end
	local plain = if S.FaceColor then rgb(S.FaceColor) else Color3.new(1, 1, 1)

	-- One frame per layer, in drawing order (later siblings draw on top).
	local names = { "Rims", "Outlines", "Depths", "Faces" }
	local layers: { [string]: Frame } = {}
	for index, name in names do
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.BackgroundTransparency = 1
		frame.Size = UDim2.fromScale(1, 1)
		frame.ZIndex = index
		frame.Parent = root
		layers[name] = frame
	end

	-- The outline (and rim) under the face and under the depth, so the depth is outlined too.
	local drops: { number } = if depth > 0 then { 0, depth } else { 0 }
	local letters: { { Frame } } = {}
	local at = -total / 2 -- arc length from the middle to this letter's left edge
	for i, char in chars do
		local w = widths[i]
		local mid = at + w / 2
		at += w + tracking
		if string.match(char, "^ *$") == nil then
			local angle = mid / radius
			-- On the circle: the middle letter on top, the others lower toward the ends.
			local x = width / 2 + radius * math.sin(angle)
			local y = pad + boxH / 2 + (radius - radius * math.cos(angle))
			local holders: { Frame } = {}
			local function holder(name: string): Frame
				local made = Instance.new("Frame")
				made.Name = "Letter" .. i
				made.BackgroundTransparency = 1
				made.AnchorPoint = Vector2.new(0.5, 0.5)
				made.Size = UDim2.fromOffset(w + 2 * pad, boxH)
				made.Position = UDim2.fromOffset(x, y)
				made.Rotation = math.deg(angle)
				made.Parent = layers[name]
				table.insert(holders, made)
				return made
			end

			if S.Rim then
				local rims = holder("Rims")
				local rimTint = rgb(S.Rim)
				for _, dy in drops do
					stroke(
						layer(rims, "Rim", char, size, face, rimTint, dy),
						rimTint,
						rim,
						S.RimTransparency
					)
				end
			end
			local outlines = holder("Outlines")
			local ink = rgb(S.Outline)
			for _, dy in drops do
				stroke(layer(outlines, "Outline", char, size, face, ink, dy), ink, outline)
			end
			if S.Extrude then
				layer(holder("Depths"), "Depth", char, size, face, rgb(S.Extrude), depth)
			end
			local own = tints and tints[first[i]]
			local top = layer(holder("Faces"), "Face", char, size, face, own or plain, 0)
			if gradient and not own then
				local shade = Instance.new("UIGradient")
				shade.Rotation = 90
				shade.Color = gradient
				shade.Parent = top
			end
			table.insert(letters, holders)
		end
	end
	return { root = root, letters = letters, width = width, height = height }
end

return ArchTitle
