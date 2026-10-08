--!strict
-- ShopLab: Studio-only mock-ups for the lively Shop's gate 2 (docs/prompts/SHOP_LIVELY_PROMPT.md
-- 7.2), shown through the GuiQA hook so they can be captured in Studio and set beside the
-- target picture (13b). Nothing here is used by the game.
--   PlayerScripts.GuiQA:Invoke("lab", "titles", size?)  the real-text GRAND OPENING title and
--                                     its subtitle on the card's navy
--   PlayerScripts.GuiQA:Invoke("lab", "odds")           the block's odds badge and pop-up, and
--                                     the always-visible chip row to compare
--   PlayerScripts.GuiQA:Invoke("lab", "stage", seconds?) Stage and the idle library on a few
--                                     real pieces (a step 6 check), the open at `seconds`
--   PlayerScripts.GuiQA:Invoke("lab")                  close
--   PlayerScripts.GuiQA:Invoke("quality", true)        Lower effects on (false: off)
--   PlayerScripts.GuiQA:Invoke("reduced", true)        act as if Reduce Motion were on
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local BlockOdds = require(Shared:WaitForChild("Progression"):WaitForChild("BlockOdds"))
local ArchTitle = require(script.Parent.ArchTitle)
local BlockIcon = require(script.Parent.BlockIcon)
local GrandOpeningCard = require(script.Parent.GrandOpeningCard)
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local Quality = require(script.Parent.Quality)
local Stage = require(script.Parent.Stage)
local UIAnim = require(script.Parent.UIAnim)

local COPY: { [string]: any } = (Strings.Menus.Shop :: any).Featured
local K = Config.UI.Kit

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local outcomes = GrandOpeningCard.outcomes

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

-- The title (the designer picked the kit font, Fredoka One, 2026-10-06), for the gate 2
-- comparison with 13b's painted title.
local function titles(size: number?)
	titleRow(screen(), "Gold", size or 40, 8)
end

-- The block's odds: the block with its sky-blue "i" badge, the pop-up beside it, and under
-- them the always-visible chip row (the designer asked to see it to compare).
local function odds()
	local root = screen()
	local list = outcomes()
	local count = rgb(K.Numbers.Count)

	local block = HudParts.frame(root, "Block")
	block.Position = UDim2.fromOffset(60, 40)
	block.Size = UDim2.fromOffset(150, 150)
	BlockIcon.new(block, "GrandOpening")
	local badge = HudParts.pill(block, "OddsBadge", count)
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(0.9, 0.88)
	badge.Size = UDim2.fromOffset(36, 36)
	badge.ZIndex = 6
	local i = HudParts.text(badge, "Words", 26, COPY.OddsBadge)
	i.Size = UDim2.fromScale(1, 1)
	i.ZIndex = 7

	-- The pop-up: a kit card beside the block, a row per outcome in its colour.
	local rowH, width = 22, 250
	local card = HudParts.card(root, "OddsCard")
	card.Position = UDim2.fromOffset(230, 22)
	card.Size = UDim2.fromOffset(width, 44 + #list * rowH + 30)
	local heading = HudParts.text(card, "Title", 22, COPY.OddsTitle)
	heading.Position = UDim2.fromOffset(12, 8)
	heading.Size = UDim2.fromOffset(width - 24, 28)
	heading.ZIndex = 2
	local total = 0
	for index, row in list do
		local y = 40 + (index - 1) * rowH
		local name = HudParts.text(card, "Name" .. index, 17, row.name, row.tint)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextWrapped = false
		name.Position = UDim2.fromOffset(14, y)
		name.Size = UDim2.fromOffset(width - 100, rowH)
		name.ZIndex = 2
		local value = HudParts.text(card, "Percent" .. index, 17, row.display, count)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.TextWrapped = false
		value.Position = UDim2.fromOffset(width - 100, y)
		value.Size = UDim2.fromOffset(86, rowH)
		value.ZIndex = 2
		total += row.percent
	end
	local sum = HudParts.note(
		card,
		"Total",
		15,
		string.format(COPY.OddsTotal, BlockOdds.percentText(total))
	)
	sum.TextXAlignment = Enum.TextXAlignment.Right
	sum.Position = UDim2.fromOffset(14, 44 + #list * rowH)
	sum.Size = UDim2.fromOffset(width - 28, 22)
	sum.ZIndex = 2

	-- The always-visible chip row: one rarity-coloured chip per outcome, name over percent.
	local chipW, gap = 82, 6
	local left = 500
	for index, row in list do
		local col = (index - 1) % 2
		local line = (index - 1) // 2
		local chip = HudParts.pill(root, "Chip" .. index, row.tint)
		chip.Position = UDim2.fromOffset(left + col * (chipW + gap) + 40, 24 + line * 50)
		chip.Size = UDim2.fromOffset(chipW, 44)
		local corner = chip:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0, 10)
		end
		local name = HudParts.text(chip, "Name", 14, row.name)
		name.Position = UDim2.fromOffset(3, 2)
		name.Size = UDim2.new(1, -6, 0, 20)
		local value = HudParts.text(chip, "Percent", 18, row.display)
		value.Position = UDim2.fromOffset(3, 20)
		value.Size = UDim2.new(1, -6, 0, 22)
	end
end

-- Stage and the idle library on a few real pieces: a panel that unrolls, the block slamming in
-- with its burst, the crown dropping on, a floating ball, the Firework card's fireworks, the
-- header scroll and the block's masked sweep. `openSeconds` stretches the open (to watch it slowly).
local function stageCheck(openSeconds: number?)
	local root = screen()
	local I = Config.UI.GrandOpeningCard.Images
	local L = Config.UI.GrandOpeningCard.Loops
	local function pic(
		parent: Instance,
		name: string,
		image: string,
		x: number,
		y: number,
		w: number,
		h: number
	): ImageLabel
		local label = Instance.new("ImageLabel")
		label.Name = name
		label.BackgroundTransparency = 1
		label.Image = image
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromOffset(x, y)
		label.Size = UDim2.fromOffset(w, h)
		label.Parent = parent
		return label
	end
	local panel = HudParts.frame(root, "Panel")
	panel.BackgroundTransparency = 0
	panel.BackgroundColor3 = Color3.fromRGB(227, 241, 254)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(620, 300)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 20)
	corner.Parent = panel
	local header = Instance.new("ImageLabel")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Image = Config.Debug.MotionSpike.Pattern2x2
	header.ImageTransparency = 0.6
	header.Size = UDim2.new(1, 0, 0, 50)
	header.Parent = panel
	local plate = pic(panel, "Card", I.Plate, 310, 175, 600, 240)
	plate.ScaleType = Enum.ScaleType.Crop
	local glow = pic(plate, "Glow", I.BlockGlow, 120, 130, 260, 260)
	glow.ImageColor3 = Color3.fromRGB(255, 190, 60)
	local block = pic(plate, "Block", I.Block, 120, 135, 150, 148)
	local mask = pic(block, "Shine", I.BlockMask, 75, 74, 150, 148)
	local crown = pic(plate, "Crown", I.Crown, 128, 60, 90, 64)
	local ball = pic(plate, "Ball", I.BallFar, 520, 60, 70, 69)
	local fw = pic(plate, "Firework", Config.UI.Effects.Firework.Pink, 420, 140, 120, 120)
	fw.Visible = false
	local stage = Stage.new({
		OpenSeconds = 1.4,
		Steps = {
			{ Ids = { "Panel" }, Kind = "Unroll", At = 0 },
			{ Ids = { "Header" }, Kind = "Fade", At = 0.12, Length = 0.15 },
			{ Ids = { "Card" }, Kind = "Grow", At = 0.3 },
			{ Ids = { "Block" }, Kind = "Slam", At = 0.55, Length = 0.22, Burst = "Gold" },
			{ Ids = { "Crown" }, Kind = "Drop", At = 0.65, Length = 0.25 },
			{ Ids = { "Ball" }, Kind = "Pop", At = 0.8 },
		},
	}, plate)
	stage:add("Panel", panel)
	stage:add("Header", header, function()
		UIAnim.scrollTile(
			header,
			Config.Debug.MotionSpike.PatternPeriod,
			260,
			32,
			Vector2.new(-1, -1)
		)
	end)
	stage:add("Card", plate)
	stage:add("Block", block, function()
		UIAnim.glowPulse(glow, 0.05, 0.45, L.GlowPulseSeconds)
		UIAnim.maskedSweep(mask, L.BlockShineEvery, 0.7)
	end)
	stage:add("Crown", crown)
	stage:add("Ball", ball, function()
		UIAnim.float(ball, 214, Vector2.new(6, 9), 5)
		UIAnim.flipbook(
			fw,
			Config.UI.Effects.Firework,
			{ image = Config.UI.Effects.Firework.Pink, loop = true, fps = L.FireworkBurstFps }
		)
	end)
	stage:play(openSeconds)
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
		if kind == "odds" then
			odds()
			return true
		end
		if kind == "stage" then
			stageCheck(...)
			return true
		end
		close()
		return true
	end)
	-- Lower effects and a stand-in for Reduce Motion, for the step 9 checks.
	GuiQA.add("quality", function(low: boolean?)
		Quality.set(low == true)
		return Quality.isLow()
	end)
	GuiQA.add("loopCost", function(seconds: number?)
		return UIAnim.cost(seconds or 2)
	end)
	GuiQA.add("reduced", function(on: boolean?)
		UIAnim.testReducedMotion(on == true)
		return UIAnim.reduced()
	end)
end

return ShopLab
