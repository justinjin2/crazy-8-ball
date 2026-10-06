--!strict
-- HoleFill: solid ink in the holes of outlined letters (o, a, e, g, d, 0, 8, B...). Roblox's
-- text outline (UIStroke) reaches only a little way into a letter's hole, so a hole shows the
-- background inside a thin ink ring however thick the outline is (checked in Studio,
-- 2026-10-05). Under each outlined text this lays two ink copies of the same text, nudged left
-- and right by about a hole's half-width, and the text again on top: the copies' letters cover
-- the holes, and stay inside the outline everywhere else. The nudge is padding on each copy
-- (left d, right -d), not a position, so a self-sizing label keeps its size. Copies follow the
-- label's text, font, size, colour, fading and gradients. Tuning in Config.UI.Kit.HoleFill.
-- On test on the Free Reward page only (designer, 2026-10-05) while the font is still open.
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

local attached: { [Instance]: () -> () } = setmetatable({}, { __mode = "k" }) :: any

local function outlineOf(label: Instance): UIStroke?
	for _, child in label:GetChildren() do
		if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
			return child
		end
	end
	return nil
end

local function nudgePx(size: number): number
	return math.max(H.MinNudgePx, math.ceil(size * H.NudgeRatio))
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
	return copy
end

-- Mirror the label's gradients onto a copy: the face takes them whole; an ink copy takes
-- only their transparency and movement (a gradient's colour multiplies the text's).
local function mirrorGradients(
	label: Instance,
	copy: TextLabel,
	whole: boolean
): { RBXScriptConnection }
	local links = {}
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
	return links
end

local function attach(label: GuiObject, stroke: UIStroke)
	if attached[label] then
		return
	end
	local left = makeCopy(label, "HoleInkLeft")
	local right = makeCopy(label, "HoleInkRight")
	local face = makeCopy(label, "HoleFace")
	local leftPad = Instance.new("UIPadding")
	leftPad.Parent = left
	local rightPad = Instance.new("UIPadding")
	rightPad.Parent = right
	local links: { RBXScriptConnection } = {}
	for _, link in mirrorGradients(label, left, false) do
		table.insert(links, link)
	end
	for _, link in mirrorGradients(label, right, false) do
		table.insert(links, link)
	end
	for _, link in mirrorGradients(label, face, true) do
		table.insert(links, link)
	end

	local function nudge()
		local d = nudgePx((label :: any).TextSize)
		leftPad.PaddingLeft = UDim.new(0, -d)
		leftPad.PaddingRight = UDim.new(0, d)
		rightPad.PaddingLeft = UDim.new(0, d)
		rightPad.PaddingRight = UDim.new(0, -d)
	end
	local function ink()
		local fade = math.max((label :: any).TextTransparency, stroke.Transparency)
		for _, copy in { left, right } do
			copy.TextColor3 = stroke.Color
			copy.TextTransparency = fade
			copy.Visible = stroke.Enabled
		end
	end
	local function look()
		face.TextColor3 = (label :: any).TextColor3
		face.TextTransparency = (label :: any).TextTransparency
		ink()
	end
	nudge()
	look()
	left.Parent = label
	right.Parent = label
	face.Parent = label

	table.insert(
		links,
		label.Changed:Connect(function(property: string)
			if SHARED_SET[property] then
				local value = (label :: any)[property]
				for _, copy in { left, right, face } do
					(copy :: any)[property] = value
				end
				if property == "TextSize" then
					nudge()
				end
			elseif property == "TextColor3" or property == "TextTransparency" then
				look()
			end
		end)
	)
	table.insert(links, stroke.Changed:Connect(ink))
	local limit = label:FindFirstChildOfClass("UITextSizeConstraint")
	if limit then
		table.insert(
			links,
			limit.Changed:Connect(function()
				for _, copy in { left, right, face } do
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
		attached[label] = nil
		for _, link in links do
			link:Disconnect()
		end
		left:Destroy()
		right:Destroy()
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
	attached[label] = detach
end

local function consider(object: Instance)
	local label = if object:IsA("UIStroke") then object.Parent else object
	if label == nil or attached[label] then
		return
	end
	if not (label:IsA("TextLabel") or label:IsA("TextButton")) then
		return
	end
	local stroke = outlineOf(label)
	if stroke then
		attach(label :: GuiObject, stroke)
	end
end

--- Fill the letter holes of every outlined text under `root`, now and as texts are added.
function HoleFill.watch(root: Instance)
	for _, object in root:GetDescendants() do
		consider(object)
	end
	root.DescendantAdded:Connect(consider)
end

return HoleFill
