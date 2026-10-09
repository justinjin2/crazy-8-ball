--!strict
-- RankClaimBlock: the claim for rank rewards held until claimed in Rank (designer, 2026-10-03;
-- docs/prompts/TUTORIAL_PROMPT.md, "Rule changes for everyone"). While the roadmap (Rank) is
-- open and something waits (the player attribute RankPending), a small card stands over the
-- roadmap's foot: "Rewards ready!", a chip per reward (the money, each lucky block, the ult
-- spins, each cue, the chat tag) and CLAIM. CLAIM asks the server (the RankClaim remote); its
-- answer closes the roadmap and the rewards fly to where they live: the money to the money
-- HUD, the blocks to the hotbar, the cues to Inventory, the spins to Abilities
-- (RewardsFlyer, as the Rewards menu's claims fly). The chat tag is simply on from then.
--
-- A stand-in in the kit's style: the GUI lane may restyle or move it (keep the CLAIM call and
-- the TutorialAnchors line). What is pending is worked out here from the attributes
-- RankClaimed and PeakDivision (Tutorial/RankClaim, the server's own rule); the server pays
-- only what its save says.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local Ranks = require(Shared:WaitForChild("Progression"):WaitForChild("Ranks"))
local RankClaim = require(Shared:WaitForChild("Tutorial"):WaitForChild("RankClaim"))
local ChatTags = require(script.Parent.ChatTags)
local CueThumb = require(script.Parent.CueThumb)
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local RewardChips = require(script.Parent.RewardChips)
local RewardsFlyer = require(script.Parent.RewardsFlyer)
local TutorialAnchors = require(script.Parent.TutorialAnchors)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local B = Config.Tutorial.RankClaim.Block
local ROADMAP = Config.UI.Progress.Roadmap
local BLOCK_ORDER: { string } = Config.LuckyBlocks.Order
local Copy = Strings.RankClaim
local player = Players.LocalPlayer

local RankClaimBlock = {}
RankClaimBlock.__index = RankClaimBlock

-- What is held now, from the attributes the server keeps current.
local function pendingNow(): RankClaim.Pending
	local claimed = player:GetAttribute("RankClaimed")
	local peak = player:GetAttribute("PeakDivision")
	return RankClaim.pending(
		if type(claimed) == "number" then claimed else nil,
		if type(peak) == "number" then peak else 0
	)
end

-- The chips for what is held: money, lucky blocks (the kinds' order), spins, cues, the tag.
local function specsOf(p: RankClaim.Pending): { RewardChips.Spec }
	local specs: { RewardChips.Spec } = {}
	if p.money > 0 then
		table.insert(
			specs,
			{ kind = "Money", text = Format.moneyDelta(p.money), tint = HudParts.tone("Green") }
		)
	end
	for _, kind in BLOCK_ORDER do
		local count = p.blocks[kind]
		if count and count > 0 then
			table.insert(
				specs,
				{ kind = "Block", id = kind, text = Strings.Progress.RewardCount:format(count) }
			)
		end
	end
	local spins = RewardChips.spinsSpec(p.spins)
	if spins then
		table.insert(specs, spins)
	end
	for _, id in p.cues do
		table.insert(specs, { kind = "Cue", id = id, text = CueThumb.cueName(id) })
	end
	local last = p.rows[#p.rows]
	if last then
		local tier = Ranks.at(last.index)
		local tag = ChatTags.tagFor(tier)
		if tag then
			table.insert(specs, {
				kind = "Tag",
				text = tag,
				rich = true,
				plain = Strings.Ranks.ChatTag:format(string.upper(Ranks.tierName(tier))),
			})
		end
	end
	return specs
end

--- The block over `roadmap` (Progression's; `isOpen`, and closed through `close`). `screen`
--- is the HUD's ScreenGui; `deps` the economy's shared table (money, column) the rewards fly
--- into.
function RankClaimBlock.new(screen: ScreenGui, deps: any, isOpen: () -> boolean, close: () -> ())
	local self: any = setmetatable({}, RankClaimBlock)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RankClaimBlock"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Over the roadmap's own ScreenGui.
	gui.DisplayOrder = screen.DisplayOrder + ROADMAP.DisplayOrderAbove + B.DisplayOrderAbove
	gui.Parent = screen.Parent
	local card = HudParts.card(gui, "Claim")
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -B.BottomGapPx)
	card.BackgroundColor3 = HudParts.tone("White")
	card.BackgroundTransparency = 0
	card.Visible = false
	local title = HudParts.text(card, "Title", B.TitlePx, Copy.Ready)
	title.Position = UDim2.fromOffset(0, B.PadPx)
	local chipsHolder = HudParts.frame(card, "Chips")
	chipsHolder.Size = UDim2.fromScale(1, 1)
	local button = HudParts.candy(card, Copy.Claim, function()
		self:claim()
	end, "Green")
	button.Name = "ClaimButton"
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -B.PadPx)
	button.Size = UDim2.fromOffset(B.ButtonWidthPx, B.ButtonPx)
	HudParts.setMinHit(button, 44)
	TutorialAnchors.set("RankClaim", button) -- the tutorial lane's hand (the Rank nudge)
	self.gui, self.card, self.title, self.chipsHolder, self.button =
		gui, card, title, chipsHolder, button
	self.isOpen, self.close = isOpen, close
	self.flyer = RewardsFlyer.new(screen, deps)
	self.chips = {} :: { RewardChips.Chip }
	self.key = "" -- the pending rows the chips were built for
	self.waiting = false -- a claim is on its way to the server
	Net.get("RankClaim").OnClientEvent:Connect(function(reply: any)
		self:onReply(reply)
	end)
	RunService.RenderStepped:Connect(function()
		self:update()
	end)
	-- Studio checks: press CLAIM (what the button does).
	GuiQA.add("rankClaim", function(): boolean
		self:claim()
		return true
	end)
	return self
end

-- Builds the chips for `p` and sizes the card round them.
function RankClaimBlock.build(self: any, p: RankClaim.Pending)
	for _, chip in self.chips do
		chip.root:Destroy()
	end
	self.chips = {}
	for _, spec in specsOf(p) do
		local chip = RewardChips.new(self.chipsHolder, spec, B.ChipHeightPx, B.ChipTextPx)
		chip.root.Visible = true
		table.insert(self.chips, chip)
	end
	local camera = workspace.CurrentCamera
	local view = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local width = math.min(B.WidthPx, view.X * B.MaxWidthShare)
	local inner = width - B.PadPx * 2
	local top = B.PadPx + B.TitlePx + B.GapPx
	local rowsHeight =
		RewardChips.flow(self.chips, width / 2, top, inner, B.ChipHeightPx, B.ChipGapPx, B.RowGapPx)
	self.title.Size = UDim2.new(1, 0, 0, B.TitlePx + 6)
	self.card.Size = UDim2.fromOffset(width, top + rowsHeight + B.GapPx + B.ButtonPx + B.PadPx)
end

-- Every frame: shown while the roadmap is open and something waits.
function RankClaimBlock.update(self: any)
	local show = self.isOpen() and player:GetAttribute("RankPending") == true
	if not show then
		if self.card.Visible then
			self.card.Visible = false
		end
		self.key = ""
		return
	end
	local p = pendingNow()
	local rows = {}
	for _, row in p.rows do
		table.insert(rows, row.index)
	end
	local key = table.concat(rows, ",")
	if key ~= self.key then
		self.key = key
		self:build(p)
	end
	HudParts.setEnabled(self.button, not self.waiting)
	if not self.card.Visible then
		UIAnim.popIn(self.card)
	end
end

--- CLAIM: ask the server (it pays from its own save and answers on the same remote).
function RankClaimBlock.claim(self: any)
	if self.waiting then
		return
	end
	self.waiting = true
	UISound.play("Click")
	Net.get("RankClaim"):FireServer()
	task.delay(B.ReplyTimeoutSeconds, function()
		self.waiting = false
	end)
end

-- The server's answer: the roadmap closes and what was paid flies to where it lives.
function RankClaimBlock.onReply(self: any, reply: any)
	self.waiting = false
	if type(reply) ~= "table" or reply.ok ~= true then
		return
	end
	local from = self.button.AbsolutePosition + self.button.AbsoluteSize / 2
	UISound.play("Claim")
	self.card.Visible = false
	self.close()
	local blocks: { [string]: number } = if type(reply.blocks) == "table"
		then table.clone(reply.blocks)
		else {}
	self.flyer:reward({ money = reply.money, blocks = blocks, spins = reply.spins }, from)
	local delay = B.ItemsAfterSeconds
	for _, id in (if type(reply.cues) == "table" then reply.cues else {}) :: { any } do
		if type(id) == "string" then
			self.flyer:flyPicture({ key = "Cue", count = 1 }, { "Inventory" }, from, delay)
			delay += B.StaggerSeconds
		end
	end
end

return RankClaimBlock
