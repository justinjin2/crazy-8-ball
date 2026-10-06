--!strict
-- ShopLab: Studio-only mock-ups for the lively Shop's gate 2 (docs/prompts/SHOP_LIVELY_PROMPT.md
-- 7.2), shown through the GuiQA hook so they can be captured in Studio and set beside the
-- target picture (13b). Nothing here is used by the game.
--   PlayerScripts.GuiQA:Invoke("lab", "titles", size?)  the real-text GRAND OPENING title and
--                                     its subtitle on the card's navy, in each title font
--   PlayerScripts.GuiQA:Invoke("lab")                  close
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local ArchTitle = require(script.Parent.ArchTitle)
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)

local COPY: { [string]: any } = (Strings.Menus.Shop :: any).Featured
local K = Config.UI.Kit

local ShopLab = {}

local gui: ScreenGui? = nil

local function close()
	if gui then
		gui:Destroy()
		gui = nil
	end
end

local function screen(): Frame
	close()
	local made = Instance.new("ScreenGui")
	made.Name = "ShopLab"
	made.IgnoreGuiInset = true
	made.ResetOnSpawn = false
	made.DisplayOrder = 510
	made.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	made.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = made
	local root = HudParts.frame(made, "Root")
	root.BackgroundTransparency = 0
	root.BackgroundColor3 = Color3.new(1, 1, 1) -- the gradient below gives the colour
	root.Size = UDim2.fromScale(1, 1)
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Color = ColorSequence.new(Color3.fromRGB(22, 36, 102), Color3.fromRGB(10, 16, 52))
	fade.Parent = root
	return root
end

-- One title row: the arched title in `style`, its arched subtitle under it (LIMITED in the
-- money yellow) and a star each side, centred at `top`. Returns the row's height.
local function titleRow(root: Frame, style: string, px: number, top: number): number
	local made = ArchTitle.new(root, COPY.Title, style, px)
	made.root.AnchorPoint = Vector2.new(0.5, 0)
	made.root.Position = UDim2.new(0.5, 0, 0, top)
	local yellow = K.Numbers.Money
	local before = string.split(COPY.Subtitle, "%s")[1]
	local from = utf8.len(before) :: number
	local tints: { [number]: Color3 } = {}
	for i = 1, utf8.len(COPY.Limited) :: number do
		tints[from + i] = Color3.fromRGB(yellow[1], yellow[2], yellow[3])
	end
	local sub = ArchTitle.new(
		root,
		string.format(COPY.Subtitle, COPY.Limited),
		"Subtitle",
		math.floor(px * 0.4),
		tints
	)
	sub.root.AnchorPoint = Vector2.new(0.5, 0)
	local subTop = top + made.height - math.floor(px * 0.3)
	sub.root.Position = UDim2.new(0.5, 0, 0, subTop)
	for side = -1, 1, 2 do
		local star = HudParts.icon(root, "Star", "Star")
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Size = UDim2.fromOffset(px * 0.95, px * 0.95)
		star.Position =
			UDim2.new(0.5, side * (made.width / 2 + px * 0.2), 0, top + made.height * 0.62)
		star.Rotation = side * 12
		star.ZIndex = 5
	end
	return subTop + sub.height - top
end

-- The title in each font, stacked (gate 2's A/B against 13b's painted title).
local function titles(size: number?)
	local root = screen()
	local px = size or 40
	local top = 8
	for _, style in { "Gold", "GoldNunito", "GoldLuckiest" } do
		top += titleRow(root, style, px, top) + 4
	end
end

function ShopLab.start()
	if not RunService:IsStudio() then
		return
	end
	GuiQA.add("lab", function(kind: string?, ...: any)
		if kind == "titles" then
			titles(...)
			return true
		end
		close()
		return true
	end)
end

return ShopLab
