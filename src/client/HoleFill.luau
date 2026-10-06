--!strict
-- HoleFill: solid ink in the holes of outlined letters (o, a, e, g, d, p, 0, 8, B...), and a
-- thick ink lip under them (the "drop"). Roblox's text outline (UIStroke) reaches only a
-- little way into a letter's hole, so a hole shows the background inside a thin ink ring,
-- and how much depends on the hole's size (checked in Studio, 2026-10-05). Under each
-- outlined text this lays two ink copies of the same text, nudged left and right by the
-- outline's thickness, and the text again on top: each hole closes from both sides, and a
-- copy never reaches past the outline (an outline is the letter grown by its thickness every
-- way), so the letters keep their shape. The nudge is padding on each copy (left d, right
-- -d), not a position, so a self-sizing label keeps its size.
-- The drop (designer, 2026-10-06, after a reference): one more ink copy with the label's own
-- outline, moved down a share of the outline's thickness, so every letter sits on a dark lip.
-- Both are sized from the outline, not TextSize: a scaled text's TextSize is only its
-- largest size (a nameplate's is 100 for 34 px letters, and its copies stuck out past the
-- outline), while the kit sets the outline from the size the text is drawn at.
-- Every outlined text in PlayerGui gets the lip (Main); the fill only shows from
-- FillMinOutlinePx up, as small text's 1 px outline closes too little of a hole to look
-- even (designer, 2026-10-06). Copies follow the label's text, font, size, colour, outline,
-- fading and gradients; rich text colours are inked in the copies. Tuning in
-- Config.UI.Kit.HoleFill.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local H = Config.UI.Kit.HoleFill

local HoleFill = {}

-- What every copy takes from the label as it changes.
local SHARED = {
	"Text",
	"RichText",
	"FontFace",
	"TextSize",
	"TextScaled",
	"TextWrapped",
	"TextXAlignment",
	"TextYAlignment",
	"LineHeight",
	"MaxVisibleGraphemes",
	"TextTruncate",
	"TextDirection",
	"AutoLocalize",
	"ZIndex",
}
local SHARED_SET: { [string]: boolean } = {}
for _, name in SHARED do
	SHARED_SET[name] = true
end

type State = {
	label: GuiObject,
	stroke: UIStroke,
	inks: { TextLabel }, -- ink copies (the hole fill, then the drop)
	face: TextLabel,
	links: { RBXScriptConnection },
	drop: TextLabel?,
	dropPad: UIPadding?,
	refresh: () -> (),
}

local states: { [Instance]: State } = setmetatable({}, { __mode = "k" }) :: any
-- Our own copies, so the drop's outline is never taken for a text to fill.
local copies: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function outlineOf(label: Instance): UIStroke?
	for _, child in label:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
			return child
		end
	end
	return nil
end

local function nudgePx(stroke: UIStroke): number
	return math.max(1, math.floor(stroke.Thickness + 0.5))
end

-- In pixels, not rounded: a fraction of a pixel shows on a high-DPI screen (a phone, a Mac).
local function dropPx(stroke: UIStroke): number
	return math.max(H.Drop.MinPx, stroke.Thickness * H.Drop.OutlineShare)
end

-- The label's text for an ink copy: rich text colours become the ink, or the copies would
-- show them round the face's letters.
local function inkText(label: GuiObject, stroke: UIStroke): string
	local text = (label :: any).Text :: string
	if not (label :: any).RichText then
		return text
	end
	local hex = "#" .. stroke.Color:ToHex()
	text = string.gsub(text, '(<font[^>]-color%s*=%s*)"[^"]*"', '%1"' .. hex .. '"')
	text = string.gsub(text, "(<font[^>]-color%s*=%s*)'[^']*'", "%1'" .. hex .. "'")
	return text
end

local function makeCopy(label: GuiObject, name: string): TextLabel
	local copy = Instance.new("TextLabel")
	copy.Name = name
	copy.BackgroundTransparency = 1
	copy.BorderSizePixel = 0
	copy.Size = UDim2.fromScale(1, 1)
	copy.Active = false
	copy.Selectable = false
	for _, property in SHARED do
		(copy :: any)[property] = (label :: any)[property]
	end
	local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if limit then
		limit:Clone().Parent = copy
	end
	copies[copy] = true
	return copy
end

-- Mirror the label's gradients onto a copy: the face takes them whole; an ink copy takes
-- only their transparency and movement (a gradient's colour multiplies the text's).
local function mirrorGradients(
	label: Instance,
	copy: TextLabel,
	whole: boolean,
	links: { RBXScriptConnection }
)
	for _, gradient in label:GetChildren() do
		if gradient:IsA("UIGradient") then
			local twin = gradient:Clone()
			if not whole then
				twin.Color = ColorSequence.new(Color3.new(1, 1, 1))
			end
			twin.Parent = copy
			table.insert(
				links,
				gradient.Changed:Connect(function(property: string)
					if property == "Color" and not whole then
						return
					end
					if property ~= "Parent" and property ~= "Name" then
						pcall(function()
							(twin :: any)[property] = (gradient :: any)[property]
						end)
					end
				end)
			)
		end
	end
end

-- Put the face back on top of every ink copy (siblings draw in child order).
local function raiseFace(state: State)
	state.face.Parent = nil
	state.face.Parent = state.label
end

local function addDrop(state: State)
	if state.drop then
		return
	end
	local label = state.label
	local drop = makeCopy(label, "DropInk")
	local pad = Instance.new("UIPadding")
	pad.Parent = drop
	local edge = state.stroke:Clone()
	for _, child in edge:GetChildren() do
		child:Destroy()
	end
	edge.Parent = drop
	mirrorGradients(label, drop, false, state.links)
	state.drop = drop
	state.dropPad = pad
	table.insert(state.inks, drop)
	-- The drop's outline follows the label's.
	table.insert(
		state.links,
		state.stroke.Changed:Connect(function(property: string)
			if property ~= "Parent" and property ~= "Name" then
				pcall(function()
					(edge :: any)[property] = (state.stroke :: any)[property]
				end)
			end
		end)
	)
	state.refresh()
	drop.Parent = label
	raiseFace(state)
end

local function attach(label: GuiObject, stroke: UIStroke): State
	local left = makeCopy(label, "HoleInkLeft")
	local right = makeCopy(label, "HoleInkRight")
	local face = makeCopy(label, "HoleFace")
	local leftPad = Instance.new("UIPadding")
	leftPad.Parent = left
	local rightPad = Instance.new("UIPadding")
	rightPad.Parent = right
	local links: { RBXScriptConnection } = {}
	mirrorGradients(label, left, false, links)
	mirrorGradients(label, right, false, links)
	mirrorGradients(label, face, true, links)

	local state: State
	local function place()
		local d = nudgePx(stroke)
		leftPad.PaddingLeft = UDim.new(0, -d)
		leftPad.PaddingRight = UDim.new(0, d)
		rightPad.PaddingLeft = UDim.new(0, d)
		rightPad.PaddingRight = UDim.new(0, -d)
		local pad = state.dropPad
		if pad then
			-- A share of the label's height, as a padding's pixels are whole. A label not
			-- laid out yet (in a billboard still switched off) has no height: whole pixels
			-- until it does, or the share would push the lip a whole line down.
			local down = dropPx(stroke)
			local height = label.AbsoluteSize.Y
			if height >= 1 then
				pad.PaddingTop = UDim.new(down / height, 0)
				pad.PaddingBottom = UDim.new(-down / height, 0)
			else
				pad.PaddingTop = UDim.new(0, math.floor(down + 0.5))
				pad.PaddingBottom = UDim.new(0, -math.floor(down + 0.5))
			end
		end
	end
	local function ink()
		local fade = math.max((label :: any).TextTransparency, stroke.Transparency)
		local text = inkText(label, stroke)
		local fill = stroke.Thickness >= H.FillMinOutlinePx
		for _, copy in state.inks do
			copy.Text = text
			copy.TextColor3 = stroke.Color
			copy.TextTransparency = fade
			copy.Visible = stroke.Enabled and (fill or copy == state.drop)
		end
	end
	local function refresh()
		face.TextColor3 = (label :: any).TextColor3
		face.TextTransparency = (label :: any).TextTransparency
		ink()
		place()
	end
	state = {
		label = label,
		stroke = stroke,
		inks = { left, right },
		face = face,
		links = links,
		refresh = refresh,
	}
	refresh()
	left.Parent = label
	right.Parent = label
	face.Parent = label

	table.insert(
		links,
		label.Changed:Connect(function(property: string)
			if SHARED_SET[property] then
				local value = (label :: any)[property]
				for _, copy in { face, table.unpack(state.inks) } do
					(copy :: any)[property] = value
				end
				if property == "Text" or property == "RichText" then
					ink()
				elseif property == "TextSize" then
					refresh()
				end
			elseif property == "TextColor3" or property == "TextTransparency" then
				refresh()
			end
		end)
	)
	table.insert(links, stroke.Changed:Connect(refresh))
	table.insert(
		links,
		label:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			if state.dropPad then
				place()
			end
		end)
	)
	local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if limit then
		table.insert(
			links,
			limit.Changed:Connect(function()
				for _, copy in { face, table.unpack(state.inks) } do
					local twin = copy:FindFirstChildOfClass("UITextSizeConstraint")
					if twin then
						twin.MaxTextSize = limit.MaxTextSize
						twin.MinTextSize = limit.MinTextSize
					end
				end
			end)
		)
	end

	local function detach()
		states[label] = nil
		for _, link in links do
			link:Disconnect()
		end
		for _, copy in state.inks do
			copy:Destroy()
		end
		face:Destroy()
	end
	-- An outline taken off (a note's) takes the fill with it.
	table.insert(
		links,
		stroke.AncestryChanged:Connect(function()
			if stroke.Parent ~= label then
				detach()
			end
		end)
	)
	table.insert(links, label.Destroying:Connect(detach))
	states[label] = state
	return state
end

local function consider(object: Instance, withDrop: boolean)
	local label = if object:IsA("UIStroke") then object.Parent else object
	if label == nil or copies[label] then
		return
	end
	if not (label:IsA("TextLabel") or label:IsA("TextButton")) then
		return
	end
	local state = states[label]
	if state == nil then
		local stroke = outlineOf(label)
		if stroke == nil then
			return
		end
		state = attach(label :: GuiObject, stroke)
	end
	if withDrop then
		addDrop(state :: State)
	end
end

--- Fill the letter holes of every outlined text under `root`, now and as texts are added.
--- `withDrop` also gives them the thick ink lip underneath. Watches over the same text share
--- one fill.
function HoleFill.watch(root: Instance, withDrop: boolean?)
	local drop = withDrop == true
	for _, object in root:GetDescendants() do
		consider(object, drop)
	end
	root.DescendantAdded:Connect(function(object: Instance)
		consider(object, drop)
	end)
end

return HoleFill
