--!strict
-- RewardsParts: what the reward screens share (the Free Reward menu's sections, its flying
-- rewards RewardsFlyer, the codes box RewardsCodes, the rank claim, the ult screen's codes):
--   * a reward read from either shape the server sends ({ money, blocks, spins?, lucky? } with
--     `blocks` a list of { kind, count } (RewardState, RewardRequest) or a map kind -> count
--     (Config.Daily rows, Ranks)), and its words ("$250", "2 Mystery Lucky Blocks", "a Rare
--     Lucky Block + 2 Ult Spins", "+$500 and a Mystery Lucky Block"); `spins` and `lucky` are
--     ult spins and Lucky Spins (docs/prompts/ULTIMATES_PROMPT.md section 10);
--   * a reward's pictures as a list (the cash stack, each lucky block, each cue, the ult spin
--     and the Lucky Spin with "+2"), for the flyer;
--   * { phone, full } pairs at a layout's t (Config.UI.Menu.Frame's convention) and times.
-- Every word is from Strings.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))

local BLOCK_ORDER: { string } = Config.LuckyBlocks.Order
local KINDS: { [string]: any } = Config.LuckyBlocks.Kinds :: any
local TIERS: { string } = Config.BlockOdds.Climb.Tiers :: any
local BLOCK_NAMES: { [string]: string } = Strings.LuckyBlocks.Names :: any
local W = Strings.Menus.Rewards
local BLOCK_MANY: { [string]: string } = W.BlockMany :: any
local BLOCK_A: { [string]: string } = W.BlockA :: any

export type BlockCount = { kind: string, count: number }
export type Reward = {
	money: number,
	blocks: { BlockCount },
	spins: number,
	lucky: number,
	cues: { string }?, -- cue ids (economy v5: the first week's day 7, the Chroma Cue)
}

-- One picture of a reward: an icon key and how many ("x2" shows above 1), or `label` instead
-- (an ult spin's "+1", shown at any count). A lucky block is key "Block" with its `kind`, a cue
-- key "Cue" with its `cue` id (drawn by CueThumb).
export type Picture = { key: string, count: number, label: string?, kind: string?, cue: string? }

-- The left column's tiles that ult spins fly into, the first that shows: the Ults button, else
-- Free Reward (a column without the Ults button).
local SPIN_TILES = { "Ults", "FreeReward" }

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
	if type(value.cues) == "table" then
		local cues: { string } = {}
		for _, id in ipairs(value.cues) do
			if type(id) == "string" then
				table.insert(cues, id)
			end
		end
		out.cues = if #cues > 0 then cues else nil
	end
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

-- A reward's cues by name, one part each ("Chroma Cue").
local function addCueParts(parts: { string }, reward: Reward)
	local names: { [string]: string } = Strings.Items.Cues :: any
	local cues: { string } = reward.cues or {}
	for _, id in cues do
		table.insert(parts, names[id] or id)
	end
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

-- The tier a block of `kind` is worth at least (economy v5: every block climbs from its name):
-- its climb's start (a Mystery block: Standard), else the lowest rarity its own odds give (the
-- Grand Opening and Starter blocks: Rare); nil for an unknown kind.
local function floorOf(kind: string): string?
	local row = KINDS[kind]
	if row == nil then
		return nil
	elseif type(row.Climb) == "string" then
		return row.Climb
	end
	local list: any = (Config.BlockOdds.List :: any)[row.Odds or kind]
	local odds = if type(list) == "table" then list.Odds else nil
	if type(odds) == "table" then
		for _, rarity in Config.BlockOdds.Rarities do
			if (odds[rarity] or 0) > 0 then
				return if rarity == "Common" then TIERS[1] else rarity
			end
		end
	end
	return nil
end

--- The most valuable block in a reward: the highest floor (floorOf), ties to the latest in
--- Config.LuckyBlocks.Order (an unknown kind counts as the least), or nil when it has none.
function RewardsParts.bestBlock(reward: Reward): BlockCount?
	local best: BlockCount? = nil
	local bestAt = -1
	for _, entry in reward.blocks do
		local floor = floorOf(entry.kind)
		local tier = if floor then table.find(TIERS, floor) or 0 else 0
		local at = tier * 100 + (table.find(BLOCK_ORDER, entry.kind) or 0)
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
	addCueParts(parts, reward)
	addSpinParts(parts, reward)
	return joinPlus(parts)
end

--- What a reward adds, each part with its plus: "+$10,000, +1 Lucky 8 Block", "+3 Mystery
--- Lucky Blocks" (`blocksOnly` leaves the money out).
function RewardsParts.gains(reward: Reward, blocksOnly: boolean?): string
	local parts: { string } = {}
	if reward.money > 0 and not blocksOnly then
		table.insert(parts, W.Gain:format(Format.money(reward.money)))
	end
	for _, entry in reward.blocks do
		local words = if entry.count <= 1
			then W.OneBlock:format(RewardsParts.blockName(entry.kind))
			else RewardsParts.blockWords(entry)
		table.insert(parts, W.Gain:format(words))
	end
	local cues: { string } = {}
	addCueParts(cues, reward)
	for _, name in cues do
		table.insert(parts, W.Gain:format(name))
	end
	if not blocksOnly then
		local spins: { string } = {}
		addSpinParts(spins, reward)
		for _, part in spins do
			table.insert(parts, W.Gain:format(part))
		end
	end
	return table.concat(parts, W.GainJoin)
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
	addCueParts(parts, reward)
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

--- A reward's pictures: the cash stack for money, then each lucky block (key "Block" with its
--- kind), each cue (key "Cue" with its id), then the ult spin icon ("+2") and the Lucky Spin
--- icon ("+1").
function RewardsParts.pictures(reward: Reward): { Picture }
	local list: { Picture } = {}
	if reward.money > 0 then
		table.insert(list, { key = "CashStack", count = 1 })
	end
	for _, entry in reward.blocks do
		table.insert(list, { key = "Block", kind = entry.kind, count = entry.count })
	end
	local cues: { string } = reward.cues or {}
	for _, id in cues do
		table.insert(list, { key = "Cue", cue = id, count = 1 })
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

return RewardsParts
