--!strict
-- CueCardLab: a Studio-only board of every cue card look (docs/prompts/CUES_LIVELY_PROMPT.md,
-- concept 1), so each look can be checked against the approved concept page without owning
-- the cues. Through the MCP:
--   PlayerScripts.GuiQA:Invoke("cueCards", width?, which?)  the board: cards `width` px wide
--       (150 by default); which = "rarities" (every rarity, with pills), "tiers" (the ten
--       Ranked cards), "big" (four big cards, YOU GOT size) or "all" (default)
--   PlayerScripts.GuiQA:Invoke("cueCards", "off")            take it away
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local InventoryCard = require(script.Parent.InventoryCard)
local InventoryCues = require(script.Parent.InventoryCues)

local CueCardLab = {}

local UNITS = Config.UI.CueCard.Units

-- One card each: the cue, and its pills as the Cues grid would show them.
type Sample = { id: string, count: string?, new: boolean?, equipped: boolean?, locked: boolean? }

local RARITIES: { Sample } = {
	{ id = "ArcticCue", count = "x4" },
	{ id = "HeritageCue" },
	{ id = "GildedCue", new = true },
	{ id = "FlareCue", count = "x2" },
	{ id = "FrostbiteCue" },
	{ id = "NeonCue", count = "x3", equipped = true },
	{ id = "MagmaCue" },
	{ id = "PrismCue", new = true },
	{ id = "PhoenixCue", count = "x5" },
	{ id = "ChromaCue" },
	{ id = "CelestialDragonCue" },
	{ id = "KitsuneCue", count = "x2" },
	{ id = "EclipseCue" },
	{ id = "FireworkCue", equipped = true },
	{ id = "BetaCue", count = "#412" },
	{ id = "VipCue" },
	{ id = "StarterCue" },
	{ id = "Classic" },
	{ id = "ApexCue", locked = true },
}

local TIERS: { Sample } = {
	{ id = "ReyesCue" },
	{ id = "GrandmasterCue" },
	{ id = "MasterCue" },
	{ id = "VeteranCue" },
	{ id = "ExpertCue" },
	{ id = "DiamondCue" },
	{ id = "PlatinumCue" },
	{ id = "GoldCue" },
	{ id = "SilverCue" },
	{ id = "BronzeCue" },
}

local BIG: { Sample } = {
	{ id = "PhoenixCue" },
	{ id = "KitsuneCue" },
	{ id = "EclipseCue" },
	{ id = "ReyesCue" },
}

local gui: ScreenGui? = nil
local cards: { InventoryCard.Card } = {}

local function close()
	for _, card in cards do
		InventoryCard.destroy(card)
	end
	table.clear(cards)
	if gui then
		gui:Destroy()
		gui = nil
	end
end

-- The board: a white sheet (the Cues menu's) holding a wrapping grid of cards.
local function board(width: number, lists: { { Sample } })
	close()
	local made = Instance.new("ScreenGui")
	made.Name = "CueCardLab"
	made.IgnoreGuiInset = true
	made.ResetOnSpawn = false
	made.DisplayOrder = 510
	made.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	made.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = made
	local sheet = HudParts.frame(made, "Sheet")
	sheet.BackgroundTransparency = 0
	sheet.BackgroundColor3 = Color3.new(1, 1, 1)
	sheet.Size = UDim2.fromScale(1, 1)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ScrollBarThickness = 6
	scroll.Parent = sheet
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 16)
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.Parent = scroll
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(width, math.floor(width * UNITS[2] / UNITS[1] + 0.5))
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	local order = 0
	for _, list in lists do
		for _, sample in list do
			order += 1
			local card = InventoryCard.new(scroll, {
				name = sample.id,
				order = order,
				onPress = function() end,
			})
			InventoryCard.set(card, {
				cueId = sample.id,
				locked = sample.locked,
				count = sample.count,
				new = sample.new,
				equipped = sample.equipped,
				chance = InventoryCues.chanceText(sample.id),
			})
			table.insert(cards, card)
		end
	end
end

function CueCardLab.start()
	if not RunService:IsStudio() then
		return
	end
	GuiQA.add("cueCards", function(width: any, which: string?)
		if width == "off" or width == false then
			close()
			return true
		end
		local w = if type(width) == "number" then width else 150
		local lists = if which == "rarities"
			then { RARITIES }
			elseif which == "tiers" then { TIERS }
			elseif which == "big" then { BIG }
			else { RARITIES, TIERS }
		board(w, lists)
		return #cards
	end)
end

return CueCardLab
