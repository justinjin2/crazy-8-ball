--!strict
-- RewardsParts: what the Rewards menu's pages (RewardsDaily, RewardsPlaytime, RewardsCodes),
-- its flying rewards (RewardsFlyer) and the reminders (Reminders) share:
--   * a reward read from either shape the server sends ({ money, cases, spins?, lucky? } with
--     `cases` a list of { id, count } (RewardState, RewardRequest) or a map id -> count
--     (MatchSummary's nextReward, Daily.nextReward)), and its words ("$250", "2 Standard
--     Cases", "Epic Case + 2 Ult Spins", "+$500 and a Standard Case"); `spins` and `lucky` are
--     ult spins and Lucky Spins (docs/prompts/ULTIMATES_PROMPT.md section 10);
--   * a reward's pictures (the cash stack, each case's chest with "x2", the ult spin and the
--     Lucky Spin icons with "+2"), a white tile card like
--     MenuFrame.tile's, a progress bar, a footer line of two parts, a tab's red dot;
--   * { phone, full } pairs at a layout's t (Config.UI.Menu.Frame's convention) and times.
-- Every word is from Strings; every size from Config.UI.Rewards and Config.UI.Kit.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)

local R = Config.UI.Rewards
local K = Config.UI.Kit
local CARD = Config.UI.Menu.Card
local ICONS: { [string]: string } = K.Icons :: any
local CASE_ORDER: { string } = Config.Cases.Order
local CASE_NAMES: { [string]: string } = Strings.Items.Cases :: any
local W = Strings.Menus.Rewards
local CASE_MANY: { [string]: string } = W.CaseMany :: any
local CASE_A: { [string]: string } = W.CaseA :: any
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local color = HudParts.color

export type CaseCount = { id: string, count: number }
export type Reward = { money: number, cases: { CaseCount }, spins: number, lucky: number }

-- One picture of a reward: an icon key and how many ("x2" shows above 1), or `label` instead
-- (an ult spin's "+1", shown at any count).
export type Picture = { key: string, count: number, label: string? }

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

--- A reward from anything the server sends: { money, cases, spins?, lucky? } where `cases` is a
--- list of { id, count } (kept in its order) or a map of id -> count (in Config.Cases.Order,
--- then any other ids by name). Anything missing or malformed reads as nothing.
function RewardsParts.reward(value: any): Reward
	local out: Reward = { money = 0, cases = {}, spins = 0, lucky = 0 }
	if type(value) ~= "table" then
		return out
	end
	out.money = whole(value.money)
	out.spins = whole(value.spins)
	out.lucky = whole(value.lucky)
	local cases = value.cases
	if type(cases) ~= "table" then
		return out
	end
	if #cases > 0 then
		for _, entry in ipairs(cases) do
			if type(entry) == "table" and type(entry.id) == "string" and whole(entry.count) > 0 then
				table.insert(out.cases, { id = entry.id, count = whole(entry.count) })
			end
		end
		return out
	end
	local seen: { [string]: boolean } = {}
	for _, id in CASE_ORDER do
		seen[id] = true
		local count = whole(cases[id])
		if count > 0 then
			table.insert(out.cases, { id = id, count = count })
		end
	end
	local others: { string } = {}
	for id, count in cases do
		if type(id) == "string" and not seen[id] and whole(count) > 0 then
			table.insert(others, id)
		end
	end
	table.sort(others)
	for _, id in others do
		table.insert(out.cases, { id = id, count = whole(cases[id]) })
	end
	return out
end

--- Whether a reward gives nothing at all (no money, cases, ult spins or Lucky Spins).
function RewardsParts.isEmpty(reward: Reward): boolean
	return reward.money <= 0 and #reward.cases == 0 and reward.spins <= 0 and reward.lucky <= 0
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

-- A reward's spins and Lucky Spins as parts of its words, after its money and cases.
local function addSpinParts(parts: { string }, reward: Reward)
	if reward.spins > 0 then
		table.insert(parts, RewardsParts.spinWords(reward.spins))
	end
	if reward.lucky > 0 then
		table.insert(parts, RewardsParts.luckyWords(reward.lucky))
	end
end

--- A case's name: "Rare Case".
function RewardsParts.caseName(id: string): string
	return CASE_NAMES[id] or id
end

--- A case entry on its own: "Rare Case", or "2 Standard Cases".
function RewardsParts.caseWords(entry: CaseCount): string
	if entry.count <= 1 then
		return RewardsParts.caseName(entry.id)
	end
	local many = CASE_MANY[entry.id]
	if many then
		return many:format(entry.count)
	end
	return W.CaseManyOther:format(entry.count, RewardsParts.caseName(entry.id))
end

--- A case entry inside a sentence: "a Rare Case", or "2 Standard Cases".
function RewardsParts.caseInSentence(entry: CaseCount): string
	if entry.count <= 1 then
		return CASE_A[entry.id] or RewardsParts.caseName(entry.id)
	end
	return RewardsParts.caseWords(entry)
end

--- The most valuable case in a reward: the latest in Config.Cases.Order (an unknown id counts
--- as the least), or nil when it has none.
function RewardsParts.bestCase(reward: Reward): CaseCount?
	local best: CaseCount? = nil
	local bestAt = -1
	for _, entry in reward.cases do
		local at = table.find(CASE_ORDER, entry.id) or 0
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

--- A tile's words: "$250", "Rare Case", "2 Standard Cases", "Epic Case + Legendary Case",
--- "Epic Case + 2 Ult Spins".
function RewardsParts.words(reward: Reward): string
	local parts: { string } = {}
	if reward.money > 0 then
		table.insert(parts, Format.money(reward.money))
	end
	for _, entry in reward.cases do
		table.insert(parts, RewardsParts.caseWords(entry))
	end
	addSpinParts(parts, reward)
	return joinPlus(parts)
end

--- What a claim gave, as a sentence's end: "+$500 and a Standard Case", "2 Standard Cases",
--- "3 Ult Spins".
function RewardsParts.summary(reward: Reward): string
	local parts: { string } = {}
	if reward.money > 0 then
		table.insert(parts, Format.moneyDelta(reward.money))
	end
	for _, entry in reward.cases do
		table.insert(parts, RewardsParts.caseInSentence(entry))
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

--- The four-week bonus's words for the week line: "a Legendary Case" (Config.Daily.WeekBonus).
function RewardsParts.bonusWords(): string
	local row: any = Config.Daily.WeekBonus
	local bonus = RewardsParts.reward({
		money = if type(row) == "table" then row.Money else 0,
		cases = if type(row) == "table" then row.Cases else nil,
	})
	local best = RewardsParts.bestCase(bonus)
	if best then
		return RewardsParts.caseInSentence(best)
	end
	return Format.money(bonus.money)
end

--- A reward's pictures: the cash stack for money, then each case's chest, then the ult spin
--- icon ("+2") and the Lucky Spin icon ("+1").
function RewardsParts.pictures(reward: Reward): { Picture }
	local list: { Picture } = {}
	if reward.money > 0 then
		table.insert(list, { key = "CashStack", count = 1 })
	end
	for _, entry in reward.cases do
		local key = "Case" .. entry.id
		if type(ICONS[key]) ~= "string" or ICONS[key] == "" then
			key = "Case"
		end
		table.insert(list, { key = key, count = entry.count })
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

export type Pictures = {
	root: Frame, -- place it (AnchorPoint 0.5, 0.5); its size is set by layout
	slots: { { image: ImageLabel, count: TextLabel } },
	pictures: { Picture },
	fade: number,
	z: number,
}

local function slot(self: Pictures, index: number)
	local found = self.slots[index]
	if found then
		return found
	end
	local image = HudParts.icon(self.root, "Case", "Picture" .. index)
	image.ZIndex = self.z + index -- a later picture sits over the one before
	local count = HudParts.text(self.root, "Count" .. index, CARD.CountTextPx, "")
	count.AutoLocalize = false -- "x2"
	count.TextWrapped = false
	count.AnchorPoint = Vector2.new(1, 1)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.ZIndex = self.z + 8
	local made = { image = image, count = count }
	self.slots[index] = made
	return made
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
		s.image.Image = ICONS[picture.key] or ""
		s.image.Visible = true
		local label = picture.label
			or (if picture.count > 1 then W.CaseCount:format(picture.count) else "")
		s.count.Text = label
		s.count.Visible = label ~= ""
	end
	for index = #self.pictures + 1, #self.slots do
		self.slots[index].image.Visible = false
		self.slots[index].count.Visible = false
	end
end

--- Fade the pictures (0 solid): a claimed or later tile.
function RewardsParts.fadePictures(self: Pictures, fade: number)
	self.fade = fade
	for _, s in self.slots do
		s.image.ImageTransparency = fade
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
		s.image.Position = UDim2.fromOffset(x, 0)
		s.image.Size = UDim2.fromOffset(px, px)
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
