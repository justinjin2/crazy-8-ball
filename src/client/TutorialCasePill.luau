--!strict
-- TutorialCasePill: the match's Rare Case timer beside the Inventory tile in the real server
-- (docs/prompts/TUTORIAL_PROMPT.md step 7; designer, 2026-10-03: "a pill next to Inventory").
-- The case's chest and "58:12", counting down; at 0 it says "Ready!" and breathes until the
-- tutorial's "Your case is ready!" nudge is answered. It sits just right of the tile the
-- column registers with TutorialAnchors ("Inventory") and hides while the tile does.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)
local HudParts = require(script.Parent.HudParts)
local RewardChips = require(script.Parent.RewardChips)
local TutorialAnchors = require(script.Parent.TutorialAnchors)

local N = Config.Tutorial.Nudges

local TutorialCasePill = {}
TutorialCasePill.__index = TutorialCasePill

export type Pill = typeof(setmetatable(
	{} :: { root: Frame, words: TextLabel, clock: number },
	TutorialCasePill
))

--- The pill in `gui` (the tutorial's ScreenGui, which ignores the top bar), hidden.
function TutorialCasePill.new(gui: ScreenGui): Pill
	local root = HudParts.card(gui, "CasePill", N.PillHeightPx // 2)
	root.AnchorPoint = Vector2.new(0, 0.5)
	root.Size = UDim2.fromOffset(N.PillWidthPx, N.PillHeightPx)
	root.BackgroundColor3 = HudParts.tone("White")
	root.BackgroundTransparency = 0
	root.ZIndex = 4
	root.Visible = false
	local icon = HudParts.icon(root, RewardChips.caseIcon("Rare"), "Case")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 4, 0.5, 0)
	icon.Size = UDim2.fromOffset(N.PillHeightPx - 6, N.PillHeightPx - 6)
	icon.ZIndex = 5
	local words = HudParts.text(root, "Time", N.PillTextPx, "")
	words.AutoLocalize = false
	words.TextWrapped = false
	words.Position = UDim2.fromOffset(N.PillHeightPx, 0)
	words.Size = UDim2.new(1, -N.PillHeightPx - 6, 1, 0)
	words.ZIndex = 5
	return setmetatable({ root = root, words = words, clock = 0 }, TutorialCasePill)
end

--- Every frame: shown beside Inventory with the time left to `readyAt` (server unix time), or
--- hidden (nil, or Inventory is not on screen).
function TutorialCasePill.update(self: Pill, readyAt: number?, dt: number)
	local tile = TutorialAnchors.get("Inventory")
	if readyAt == nil or tile == nil or not TutorialAnchors.showing("Inventory") then
		self.root.Visible = false
		return
	end
	-- Every ScreenGui's AbsolutePosition starts under Roblox's top bar; this one's top is the
	-- screen's (see TutorialOverlay.guiTarget).
	local inset = game:GetService("GuiService"):GetGuiInset()
	local at = tile.AbsolutePosition + inset
	self.root.Position =
		UDim2.fromOffset(at.X + tile.AbsoluteSize.X + N.PillGapPx, at.Y + tile.AbsoluteSize.Y / 2)
	local left = math.max(0, math.floor(readyAt - workspace:GetServerTimeNow()))
	self.clock += dt
	if left > 0 then
		self.words.Text = ("%d:%02d"):format(left // 60, left % 60)
		self.words.TextColor3 = HudParts.tone("White")
		self.root.BackgroundTransparency = 0
	else
		self.words.Text = Strings.Tutorial.CasePillReady
		self.words.TextColor3 = HudParts.tone("Gold")
		-- "Ready!" breathes.
		local wave = (math.sin(self.clock * 2 * math.pi / N.PillPulseSeconds) + 1) / 2
		self.root.BackgroundTransparency = 0.25 * wave
	end
	self.root.Visible = true
end

return TutorialCasePill
