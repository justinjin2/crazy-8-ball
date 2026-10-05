--!strict
-- RewardsParts: what the Rewards menu's pages (RewardsDaily, RewardsPlaytime, RewardsCodes),
-- its flying rewards (RewardsFlyer), the Free Reward page and the rank claim share:
--   * a reward read from either shape the server sends ({ money, blocks, spins?, lucky? } with
--     `blocks` a list of { kind, count } (RewardState, RewardRequest) or a map kind -> count
--     (Config.Daily rows, Ranks)), and its words ("$250", "2 Mystery Lucky Blocks", "a Rare
--     Lucky Block + 2 Ult Spins", "+$500 and a Mystery Lucky Block"); `spins` and `lucky` are
--     ult spins and Lucky Spins (docs/prompts/ULTIMATES_PROMPT.md section 10);
--   * a reward's pictures (the cash stack, each lucky block as its turning 3D icon (BlockIcon)
--     with "x2", the ult spin and the Lucky Spin icons with "+2"), a white tile card like
--     MenuFrame.tile's, a progress bar, a footer line of two parts, a tab's red dot;
--   * { phone, full } pairs at a layout's t (Config.UI.Menu.Frame's convention) and times.
-- Every word is from Strings; every size from Config.UI.Rewards and Config.UI.Kit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local BlockIcon = require(script.Parent.BlockIcon)
local HudParts = require(script.Parent.HudParts)

local R = Config.UI.Rewards
local K = Config.UI.Kit
local CARD = Config.UI.Menu.Card
local ICONS: { [string]: string } = K.Icons :: any
local BLOCK_ORDER: { string } = Config.LuckyBlocks.Order
local BLOCK_NAMES: { [string]: string } = Strings.LuckyBlocks.Names :: any
local W = Strings.Menus.Rewards
local BLOCK_MANY: { [string]: string } = W.BlockMany :: any
local BLOCK_A: { [string]: string } = W.BlockA :: any
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local color = HudParts.color

export type BlockCount = { kind: string, count: number }
export type Reward = { money: number, blocks: { BlockCount }, spins: number, lucky: number }

-- One picture of a reward: an icon key and how many ("x2" shows above 1), or `label` instead
-- (an ult spin's "+1", shown at any count). A lucky block is key "Block" with its `kind`
-- (drawn as its 3D icon, BlockIcon).
export type Picture = { key: string, count: number, label: string?, kind: string? }

-- The left column's tiles that ult spins fly into, the first that exists: the Ults button, else
-- Rewards (a column without the Ults button yet).
local SPIN_TILES = { "Ults", "Rewards" }

local RewardsParts = {}

--------------------------------------------------------------------------------------------
-- Numbers and sizes
--------------------------------------------------------------------------------------------

local function round(n: number): number
	return math.floor(n + 0.5)
end

-- A whole, finite, non-negative number, else 0.
local function whole(x: any): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge or x < 0 then
		return 0
	end
	return math.floor(x)
end

RewardsParts.round = round
RewardsParts.whole = whole
RewardsParts.SpinTiles = SPIN_TILES

--- A { phone, full } pair at t (0 a phone-sized panel, 1 a full one), in whole pixels.
function RewardsParts.span(pair: { number }, t: number): number
	return round(pair[1] + (pair[2] - pair[1]) * t)
end

--- How wide `text` is at `size` in the kit's font.
function RewardsParts.textWidth(text: string, size: number): number
	return TextService:GetTextSize(text, size, FONT, Vector2.new(4000, 400)).X
end

--- Seconds as a clock: "5:12:03" from an hour, else "4:12".
function RewardsParts.clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= 3600 then
		return Strings.Menus.TimeHours:format(s // 3600, (s % 3600) // 60, s % 60)
	end
	return Strings.Menus.TimeMinutes:format(s // 60, s % 60)
end

--------------------------------------------------------------------------------------------
-- Rewards and their words
--------------------------------------------------------------------------------------------

--- A reward from anything the server sends: { money, blocks, spins?, lucky? } where `blocks`
--- is a list of { kind, count } (kept in its order) or a map of kind -> count (in
--- Config.LuckyBlocks.Order, then any other kinds by name). Anything missing or malformed
--- reads as nothing.
function RewardsParts.reward(value: any): Reward
	local out: Reward = { money = 0, blocks = {}, spins = 0, lucky = 0 }
	if type(value) ~= "table" then
		return out
	end
	out.money = whole(value.money)
	out.spins = whole(value.spins)
	out.lucky = whole(value.lucky)
	local blocks = value.blocks
	if type(blocks) ~= "table" then
		return out
	end
	if #blocks > 0 then
		for _, entry in ipairs(blocks) do
			if
				type(entry) == "table"
				and type(entry.kind) == "string"
				and whole(entry.count) > 0
			then
				table.insert(out.blocks, { kind = entry.kind, count = whole(entry.count) })
			end
		end
		return out
	end
	local seen: { [string]: boolean } = {}
	for _, kind in BLOCK_ORDER do
		seen[kind] = true
		local count = whole(blocks[kind])
		if count > 0 then
			table.insert(out.blocks, { kind = kind, count = count })
		end
	end
	local others: { string } = {}
	for kind, count in blocks do
		if type(kind) == "string" and not seen[kind] and whole(count) > 0 then
			table.insert(others, kind)
		end
	end
	table.sort(others)
	for _, kind in others do
		table.insert(out.blocks, { kind = kind, count = whole(blocks[kind]) })
	end
	return out
end

--- Whether a reward gives nothing at all (no money, blocks, ult spins or Lucky Spins).
function RewardsParts.isEmpty(reward: Reward): boolean
	return reward.money <= 0 and #reward.blocks == 0 and reward.spins <= 0 and reward.lucky <= 0
end

--- Ult spins' words: "1 Ult Spin", "3 Ult Spins" ("" for none).
function RewardsParts.spinWords(count: number): string
	if count <= 0 then
		return ""
	end
	return if count == 1 then W.SpinOne else W.SpinMany:format(count)
end

--- Lucky Spins' words: "1 Lucky Spin", "3 Lucky Spins" ("" for none).
function RewardsParts.luckyWords(count: number): string
	if count <= 0 then
		return ""
	end
	return if count == 1 then W.LuckyOne else W.LuckyMany:format(count)
end

-- A reward's spins and Lucky Spins as parts of its words, after its money and blocks.
local function addSpinParts(parts: { string }, reward: Reward)
	if reward.spins > 0 then
		table.insert(parts, RewardsParts.spinWords(reward.spins))
	end
	if reward.lucky > 0 then
		table.insert(parts, RewardsParts.luckyWords(reward.lucky))
	end
end

--- A lucky block's name: "Rare Lucky Block".
function RewardsParts.blockName(kind: string): string
	return BLOCK_NAMES[kind] or kind
end

--- A block entry on its own: "Rare Lucky Block", or "2 Mystery Lucky Blocks".
function RewardsParts.blockWords(entry: BlockCount): string
	if entry.count <= 1 then
		return RewardsParts.blockName(entry.kind)
	end
	local many = BLOCK_MANY[entry.kind]
	if many then
		return many:format(entry.count)
	end
	return W.BlockManyOther:format(entry.count, RewardsParts.blockName(entry.kind))
end

--- A block entry inside a sentence: "a Rare Lucky Block", or "2 Mystery Lucky Blocks".
function RewardsParts.blockInSentence(entry: BlockCount): string
	if entry.count <= 1 then
		return BLOCK_A[entry.kind] or RewardsParts.blockName(entry.kind)
	end
	return RewardsParts.blockWords(entry)
end

--- The most valuable block in a reward: the latest in Config.LuckyBlocks.Order (an unknown
--- kind counts as the least), or nil when it has none.
function RewardsParts.bestBlock(reward: Reward): BlockCount?
	local best: BlockCount? = nil
	local bestAt = -1
	for _, entry in reward.blocks do
		local at = table.find(BLOCK_ORDER, entry.kind) or 0
		if at > bestAt then
			best, bestAt = entry, at
		end
	end
	return best
end

-- Folds parts into one line with a two-part pattern: a + b + c.
local function joinPlus(parts: { string }): string
	local text = parts[1] or ""
	for i = 2, #parts do
		text = W.Plus:format(text, parts[i])
	end
	return text
end

--- A tile's words: "$250", "Rare Lucky Block", "2 Mystery Lucky Blocks", "$500 + Rare Lucky
--- Block", "Epic Lucky Block + 2 Ult Spins".
function RewardsParts.words(reward: Reward): string
	local parts: { string } = {}
	if reward.money > 0 then
		table.insert(parts, Format.money(reward.money))
	end
	for _, entry in reward.blocks do
		table.insert(parts, RewardsParts.blockWords(entry))
	end
	addSpinParts(parts, reward)
	return joinPlus(parts)
end

--- What a claim gave, as a sentence's end: "+$500 and a Mystery Lucky Block", "2 Mystery
--- Lucky Blocks", "3 Ult Spins".
function RewardsParts.summary(reward: Reward): string
	local parts: { string } = {}
	if reward.money > 0 then
		table.insert(parts, Format.moneyDelta(reward.money))
	end
	for _, entry in reward.blocks do
		table.insert(parts, RewardsParts.blockInSentence(entry))
	end
	addSpinParts(parts, reward)
	if #parts <= 1 then
		return parts[1] or ""
	end
	local text = parts[1]
	for i = 2, #parts - 1 do
		text = W.List:format(text, parts[i])
	end
	return W.And:format(text, parts[#parts])
end

--- The four-week bonus's words for the week line: "a Legendary Lucky Block"
--- (Config.Daily.WeekBonus).
function RewardsParts.bonusWords(): string
	local row: any = Config.Daily.WeekBonus
	local bonus = RewardsParts.reward({
		money = if type(row) == "table" then row.Money else 0,
		blocks = if type(row) == "table" then row.Blocks else nil,
	})
	local best = RewardsParts.bestBlock(bonus)
	if best then
		return RewardsParts.blockInSentence(best)
	end
	return Format.money(bonus.money)
end

--- A reward's pictures: the cash stack for money, then each lucky block (key "Block" with its
--- kind), then the ult spin icon ("+2") and the Lucky Spin icon ("+1").
function RewardsParts.pictures(reward: Reward): { Picture }
	local list: { Picture } = {}
	if reward.money > 0 then
		table.insert(list, { key = "CashStack", count = 1 })
	end
	for _, entry in reward.blocks do
		table.insert(list, { key = "Block", kind = entry.kind, count = entry.count })
	end
	if reward.spins > 0 then
		table.insert(
			list,
			{ key = "UltSpin", count = reward.spins, label = W.SpinChip:format(reward.spins) }
		)
	end
	if reward.lucky > 0 then
		table.insert(
			list,
			{ key = "Lucky", count = reward.lucky, label = W.SpinChip:format(reward.lucky) }
		)
	end
	return list
end

--------------------------------------------------------------------------------------------
-- A reward's pictures, side by side
--------------------------------------------------------------------------------------------

-- One slot: a kit icon (image) or a lucky block's 3D icon (block, in holder), and its count.
type Slot = { holder: Frame, image: ImageLabel, block: BlockIcon.Icon?, count: TextLabel }

export type Pictures = {
	root: Frame, -- place it (AnchorPoint 0.5, 0.5); its size is set by layout
	slots: { Slot },
	pictures: { Picture },
	fade: number,
	z: number,
}

local function slot(self: Pictures, index: number): Slot
	local found = self.slots[index]
	if found then
		return found
	end
	local holder = HudParts.frame(self.root, "Picture" .. index)
	holder.ZIndex = self.z + index -- a later picture sits over the one before
	local image = HudParts.icon(holder, "CashStack", "Image")
	image.Size = UDim2.fromScale(1, 1)
	image.ZIndex = self.z + index
	local count = HudParts.text(self.root, "Count" .. index, CARD.CountTextPx, "")
	count.AutoLocalize = false -- "x2"
	count.TextWrapped = false
	count.AnchorPoint = Vector2.new(1, 1)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.ZIndex = self.z + 8
	local made: Slot = { holder = holder, image = image, block = nil, count = count }
	self.slots[index] = made
	return made
end

-- A slot shows a block's 3D icon (still, so a page of tiles costs nothing) or a kit icon.
local function showPicture(s: Slot, picture: Picture, z: number)
	if picture.key == "Block" then
		local kind = picture.kind or ""
		if s.block and s.block.kind ~= kind then
			s.block:destroy()
			s.block = nil
		end
		if not s.block then
			local icon = BlockIcon.new(s.holder, kind, true)
			icon.root.ZIndex = z
			icon.viewport.ZIndex = z
			if icon.fallback then
				icon.fallback.ZIndex = z
			end
			s.block = icon
		end
		s.image.Visible = false
	else
		if s.block then
			s.block:destroy()
			s.block = nil
		end
		s.image.Image = ICONS[picture.key] or ""
		s.image.Visible = true
	end
	s.holder.Visible = true
end

--- Pictures of a reward in `parent` (at ZIndex `z` and up to z + 8).
function RewardsParts.newPictures(parent: Instance, name: string, z: number): Pictures
	local root = HudParts.frame(parent, name)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.ZIndex = z
	return { root = root, slots = {}, pictures = {}, fade = 0, z = z }
end

--- Show a reward (call layoutPictures after).
function RewardsParts.setPictures(self: Pictures, reward: Reward)
	self.pictures = RewardsParts.pictures(reward)
	for index, picture in self.pictures do
		local s = slot(self, index)
		showPicture(s, picture, self.z + index)
		local label = picture.label
			or (if picture.count > 1 then W.BlockCount:format(picture.count) else "")
		s.count.Text = label
		s.count.Visible = label ~= ""
	end
	for index = #self.pictures + 1, #self.slots do
		self.slots[index].holder.Visible = false
		self.slots[index].count.Visible = false
	end
	RewardsParts.fadePictures(self, self.fade)
end

--- Fade the pictures (0 solid): a claimed or later tile.
function RewardsParts.fadePictures(self: Pictures, fade: number)
	self.fade = fade
	for _, s in self.slots do
		s.image.ImageTransparency = fade
		local block = s.block
		if block then
			block.viewport.ImageTransparency = fade
			if block.fallback then
				block.fallback.ImageTransparency = fade
			end
		end
		HudParts.setTextTransparency(s.count, fade)
	end
end

--- Lay the pictures out `size` pixels tall in at most `maxWidth`, overlapping a little when
--- there are several; returns the width used.
function RewardsParts.layoutPictures(
	self: Pictures,
	size: number,
	maxWidth: number,
	countPx: number
): number
	local n = math.max(1, #self.pictures)
	local overlap = R.IconOverlapShare
	-- n pictures overlapping by `overlap` of one take (n - (n - 1) * overlap) of their size.
	local across = n - (n - 1) * overlap
	local px = math.max(1, math.floor(math.min(size, maxWidth / across)))
	local width = round(px * across)
	self.root.Size = UDim2.fromOffset(width, px)
	for index, s in self.slots do
		local x = round((index - 1) * px * (1 - overlap))
		s.holder.Position = UDim2.fromOffset(x, 0)
		s.holder.Size = UDim2.fromOffset(px, px)
		HudParts.setTextSize(s.count, countPx)
		s.count.Position = UDim2.fromOffset(x + px + 2, px + 2)
		s.count.Size = UDim2.fromOffset(px, countPx + 4)
	end
	self.root.Visible = #self.pictures > 0
	return width
end

--------------------------------------------------------------------------------------------
-- A white tile card, a progress bar, a footer line, a tab's red dot
--------------------------------------------------------------------------------------------

export type Card = { root: Frame, fill: Frame, edge: UIStroke }

--- A white card like MenuFrame.tile's face (a pale edge, the white-to-pale-blue fade), filling
--- `parent`, drawn at ZIndex `z`.
function RewardsParts.card(parent: Instance, name: string, z: number): Card
	local fill = HudParts.frame(parent, name)
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = HudParts.tone("White")
	fill.ZIndex = z
	HudParts.corner(fill, CARD.CornerPx)
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = color(CARD.EdgeColor)
	edge.Thickness = CARD.StrokePx
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = fill
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Color = ColorSequence.new(HudParts.tone("White"), color(K.PanelFade))
	fade.Parent = fill
	return { root = fill, fill = fill, edge = edge }
end

--- The card's edge: pale, or `tone` (a Kit colour) at `thickness`.
function RewardsParts.setEdge(card: Card, toneName: string?, thickness: number?)
	card.edge.Color = if toneName then HudParts.tone(toneName) else color(CARD.EdgeColor)
	card.edge.Thickness = thickness or CARD.StrokePx
end

export type Bar = { root: Frame, fill: Frame }

--- A progress bar: a pale track with an ink outline and a rounded fill.
function RewardsParts.bar(parent: Instance, name: string, z: number): Bar
	local track = HudParts.pill(parent, name, color(K.PanelFade))
	track.ZIndex = z
	track.ClipsDescendants = false
	local fill = HudParts.frame(track, "Fill")
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = HudParts.tone("Blue")
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = z + 1
	HudParts.corner(fill, K.PillCornerPx)
	return { root = track, fill = fill }
end

--- Fill a bar to `progress` (0..1) in a Kit colour.
function RewardsParts.setBar(bar: Bar, progress: number, toneName: string)
	local p = math.clamp(progress, 0, 1)
	bar.fill.Size = UDim2.fromScale(p, 1)
	bar.fill.Visible = p > 0
	bar.fill.BackgroundColor3 = HudParts.tone(toneName)
end

export type Footer = { left: TextLabel, right: TextLabel }

--- A line of two parts at the bottom of a page (ink, no outline): the left one left-aligned,
--- the right one right-aligned (one alone is centred); they stack when they do not fit side
--- by side.
function RewardsParts.footer(parent: Instance, name: string, z: number): Footer
	local left = HudParts.note(parent, name .. "Left", 16, "")
	left.TextWrapped = false
	left.TextXAlignment = Enum.TextXAlignment.Left
	left.ZIndex = z
	local right = HudParts.note(parent, name .. "Right", 16, "")
	right.TextWrapped = false
	right.TextXAlignment = Enum.TextXAlignment.Right
	right.ZIndex = z
	return { left = left, right = right }
end

--- Lay a footer out along the bottom of a `width` x `height` page at `textPx`; returns the
--- height it takes (0 when both parts are empty).
function RewardsParts.layoutFooter(
	footer: Footer,
	width: number,
	height: number,
	textPx: number
): number
	local lineH = textPx + 6
	local leftText, rightText = footer.left.Text, footer.right.Text
	HudParts.setTextSize(footer.left, textPx)
	HudParts.setTextSize(footer.right, textPx)
	footer.left.Visible = leftText ~= ""
	footer.right.Visible = rightText ~= ""
	if leftText == "" and rightText == "" then
		return 0
	end
	local lw = if leftText ~= "" then math.ceil(RewardsParts.textWidth(leftText, textPx)) + 6 else 0
	local rw = if rightText ~= ""
		then math.ceil(RewardsParts.textWidth(rightText, textPx)) + 6
		else 0
	local gap = 12
	if leftText == "" or rightText == "" or lw + gap + rw <= width then
		footer.left.Position = UDim2.fromOffset(0, height - lineH)
		footer.left.Size = UDim2.fromOffset(
			if rightText == "" then width else math.max(1, width - rw - gap),
			lineH
		)
		footer.right.Position =
			UDim2.fromOffset(if leftText == "" then 0 else width - rw, height - lineH)
		footer.right.Size = UDim2.fromOffset(if leftText == "" then width else rw, lineH)
		-- One part alone sits in the middle; two share the line, left and right.
		footer.left.TextXAlignment = if rightText == ""
			then Enum.TextXAlignment.Center
			else Enum.TextXAlignment.Left
		footer.right.TextXAlignment = if leftText == ""
			then Enum.TextXAlignment.Center
			else Enum.TextXAlignment.Right
		return lineH
	end
	-- Too long side by side (a long translation): one over the other, both centred.
	footer.left.TextXAlignment = Enum.TextXAlignment.Center
	footer.right.TextXAlignment = Enum.TextXAlignment.Center
	footer.left.Position = UDim2.fromOffset(0, height - 2 * lineH)
	footer.left.Size = UDim2.fromOffset(width, lineH)
	footer.right.Position = UDim2.fromOffset(0, height - lineH)
	footer.right.Size = UDim2.fromOffset(width, lineH)
	return 2 * lineH
end

--- A small red dot with "!" at the top-right corner of a tab's button (hidden until shown).
function RewardsParts.tabDot(button: GuiObject): Frame
	local dot = HudParts.pill(button, "RewardDot", HudParts.tone("Red"))
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.new(1, -4, 0, 4)
	dot.Size = UDim2.fromOffset(R.TabDotPx, R.TabDotPx)
	dot.ZIndex = 20
	dot.Visible = false
	local mark = HudParts.text(dot, "Mark", R.TabDotTextPx, Strings.Menus.DotReady)
	mark.TextWrapped = false
	mark.Size = UDim2.fromScale(1, 1)
	mark.ZIndex = 21
	return dot
end

return RewardsParts
