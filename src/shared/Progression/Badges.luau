--!strict
-- Badges: which Roblox badges a player has earned (hw-sys lane, designer 2026-10-28; the rows are
-- Config.Badges.List, the text Strings.Badges, the award queue src/server/Badges.luau). Pure: no
-- clock, no Instances; the same rules decide a live award and the back-pay from an old save.
--
-- Rule kinds (one per row):
--   stat = <Stats key>, atLeast = n       Stats.<key> >= n
--   peak = <tier>                         PeakDivision reached that tier's division I
--   seenRarity = <rarity>                 a Block cue of that rarity ever owned
--   seenGroup = <group>                   any cue of that Catalog group ever owned
--   seenCount = n                         n distinct cues ever owned (Classic, group Default, not counted)
--   seenCue = <id>                        that cue ever owned
--   always = true                         Welcome
--   halloween = "KingWins" | "Candy", atLeast = n   the Halloween save field (Candy = Earned + Bought)
--   event = <name>                        only from a live hook (fromMatch, the server's own)
-- "Ever owned" is Index.Seen or held now (Inventory.everOwned), so a sold cue still counts.
local Config = require(script.Parent.Parent.Config)
local Catalog = require(script.Parent.Catalog)
local Inventory = require(script.Parent.Inventory)
local Ranks = require(script.Parent.Ranks)
local SaveSchema = require(script.Parent.SaveSchema)

local Badges = {}

export type Row = { Key: string, BadgeId: number, Rule: { [string]: any }? }

export type MatchFacts = {
	outcome: string?, -- "Win" | "Loss" | "Draw"
	real: boolean?, -- Settle.isReal: people (or a disguised bot) on the other side
	teamSize: number?,
	opponents: { number }?, -- the other team's user ids (Economy.opponentIds: never a bot)
	forfeitTeam: number?, -- Settle.forfeitTeam: a surrender, timeouts, a team that left, an early 8
	userId: number?,
}

local EVENTS =
	{ TeamMatch = true, UltUsed = true, InGroup = true, OwnerHere = true, BeatOwner = true }
local HALLOWEEN = { KingWins = true, Candy = true }
local KINDS = {
	"stat",
	"peak",
	"seenRarity",
	"seenGroup",
	"seenCount",
	"seenCue",
	"always",
	"halloween",
	"event",
}

local function number(v: any): number
	return if type(v) == "number" and v == v then v else 0
end

local function sub(save: any, key: string): { [string]: any }
	local t = if type(save) == "table" then save[key] else nil
	return if type(t) == "table" then t else {}
end

-- The rule's kind: the one KINDS key it has (nil when none or several).
local function kindOf(rule: { [string]: any }): string?
	local found: string? = nil
	for _, kind in KINDS do
		if rule[kind] ~= nil then
			if found then
				return nil
			end
			found = kind
		end
	end
	return found
end

local function halloweenValue(save: any, which: string): number
	local h = sub(save, "Halloween")
	if which == "KingWins" then
		return number(h.KingWins)
	end
	return number(h.Earned) + number(h.Bought)
end

--- Whether `save` meets `rule` (an event rule never does: only a live hook awards it).
function Badges.passes(rule: { [string]: any }?, save: any): boolean
	if type(rule) ~= "table" then
		return false
	end
	local kind = kindOf(rule)
	if kind == "stat" then
		return number(sub(save, "Stats")[rule.stat]) >= rule.atLeast
	elseif kind == "peak" then
		local index = Ranks.indexOf(rule.peak, 1)
		return index ~= nil
			and index > 0
			and number(if type(save) == "table" then save.PeakDivision else 0) >= index
	elseif kind == "seenRarity" then
		for _, cue in Catalog.list() do
			if
				cue.Group == "Block"
				and cue.Rarity == rule.seenRarity
				and Inventory.everOwned(save, cue.Id)
			then
				return true
			end
		end
		return false
	elseif kind == "seenGroup" then
		for _, cue in Catalog.list() do
			if cue.Group == rule.seenGroup and Inventory.everOwned(save, cue.Id) then
				return true
			end
		end
		return false
	elseif kind == "seenCount" then
		local n = 0
		for _, cue in Catalog.list() do
			if cue.Group ~= "Default" and Inventory.everOwned(save, cue.Id) then
				n += 1
				if n >= rule.seenCount then
					return true
				end
			end
		end
		return false
	elseif kind == "seenCue" then
		return Catalog.get(rule.seenCue) ~= nil and Inventory.everOwned(save, rule.seenCue)
	elseif kind == "always" then
		return rule.always == true
	elseif kind == "halloween" then
		return halloweenValue(save, rule.halloween) >= rule.atLeast
	end
	return false
end

--- The keys whose save rules pass, in list order (event rows never: see fromMatch).
function Badges.fromSave(save: any, list: { Row }): { string }
	local out = {}
	for _, row in list do
		if Badges.passes(row.Rule, save) then
			table.insert(out, row.Key)
		end
	end
	return out
end

--- The match events a settled match earns this player: "TeamMatch" (a real 2v2 or 3v3) and
--- "BeatOwner" (a real win over `ownerId` that no forfeit decided, never for the owner).
--- Bots never appear in `opponents`, so a PC or solo game cannot fake it.
function Badges.fromMatch(facts: MatchFacts, ownerId: number): { string }
	local out = {}
	local real = facts.real == true
	if real and number(facts.teamSize) >= 2 then
		table.insert(out, "TeamMatch")
	end
	if
		facts.outcome == "Win"
		and real
		and type(facts.opponents) == "table"
		and table.find(facts.opponents, ownerId) ~= nil
		and facts.forfeitTeam == nil
		and facts.userId ~= ownerId
	then
		table.insert(out, "BeatOwner")
	end
	return out
end

--- The keys of the rows that `event` awards, in list order.
function Badges.forEvent(list: { Row }, event: string): { string }
	local out = {}
	for _, row in list do
		if type(row.Rule) == "table" and row.Rule.event == event then
			table.insert(out, row.Key)
		end
	end
	return out
end

--- `keys` without the ones the save already holds, unknown or inert (BadgeId 0) rows and
--- paused rows, in the order given.
function Badges.pending(
	keys: { string },
	save: any,
	list: { Row },
	paused: { [string]: boolean }?
): { string }
	local byKey: { [string]: Row } = {}
	for _, row in list do
		byKey[row.Key] = row
	end
	local owned = sub(save, "Badges")
	local out = {}
	for _, key in keys do
		local row = byKey[key]
		if row and row.BadgeId ~= 0 and owned[key] ~= true and not (paused and paused[key]) then
			table.insert(out, key)
		end
	end
	return out
end

local function whole(n: any): boolean
	return type(n) == "number" and n == n and n >= 1 and n == math.floor(n) and n < math.huge
end

--- Every problem with the registry (empty when it is sound): a duplicate key or id, a rule of
--- no known kind or naming an unknown stat, tier, rarity, group or cue, a bad halloween value or
--- atLeast, missing or too-long text, a row with an id but no rule, more rows than a save
--- holds, and (when `expectedCount` is given) a different number of rows.
function Badges.check(
	list: { Row },
	strings: { [string]: any },
	catalog: any,
	expectedCount: number?
): { string }
	local problems = {}
	local function bad(fmt: string, ...: any)
		table.insert(problems, fmt:format(...))
	end
	local stats = SaveSchema.template().Stats
	local rarities, groups = {}, {}
	for _, cue in catalog.list() do
		groups[cue.Group] = true
		if cue.Group == "Block" then
			rarities[cue.Rarity] = true
		end
	end
	local keys, ids = {}, {}
	for i, row in list do
		local key = row.Key
		if type(key) ~= "string" or key == "" or #key > Config.Save.MaxIdLength then
			bad("row %d: bad key", i)
			continue
		end
		if keys[key] then
			bad("%s: duplicate key", key)
		end
		keys[key] = true
		if
			type(row.BadgeId) ~= "number"
			or row.BadgeId < 0
			or row.BadgeId ~= math.floor(row.BadgeId)
		then
			bad("%s: bad BadgeId", key)
		elseif row.BadgeId ~= 0 then
			if ids[row.BadgeId] then
				bad("%s: duplicate BadgeId %d (also %s)", key, row.BadgeId, ids[row.BadgeId])
			end
			ids[row.BadgeId] = key
		end
		local text = strings[key]
		if
			type(text) ~= "table"
			or type(text.Name) ~= "string"
			or text.Name == ""
			or #text.Name > 50
		then
			bad("%s: missing or too-long name", key)
		end
		if
			type(text) ~= "table"
			or type(text.Description) ~= "string"
			or text.Description == ""
			or #text.Description > 1000
		then
			bad("%s: missing or too-long description", key)
		end
		local rule = row.Rule
		if rule == nil then
			if row.BadgeId ~= 0 then
				bad("%s: has an id but no rule", key)
			end
			continue
		end
		local kind = if type(rule) == "table" then kindOf(rule) else nil
		if kind == nil then
			bad("%s: unknown rule kind", key)
		elseif kind == "stat" then
			if stats[rule.stat] == nil then
				bad("%s: unknown stat %s", key, tostring(rule.stat))
			end
			if not whole(rule.atLeast) then
				bad("%s: atLeast must be a whole number of at least 1", key)
			end
		elseif kind == "peak" then
			local index = if type(rule.peak) == "string" then Ranks.indexOf(rule.peak, 1) else nil
			if index == nil or index == 0 then
				bad("%s: unknown tier %s", key, tostring(rule.peak))
			end
		elseif kind == "seenRarity" then
			if not rarities[rule.seenRarity] then
				bad("%s: unknown rarity %s", key, tostring(rule.seenRarity))
			end
		elseif kind == "seenGroup" then
			if not groups[rule.seenGroup] then
				bad("%s: unknown group %s", key, tostring(rule.seenGroup))
			end
		elseif kind == "seenCount" then
			if not whole(rule.seenCount) then
				bad("%s: seenCount must be a whole number of at least 1", key)
			end
		elseif kind == "seenCue" then
			if catalog.get(rule.seenCue) == nil then
				bad("%s: unknown cue %s", key, tostring(rule.seenCue))
			end
		elseif kind == "always" then
			if rule.always ~= true then
				bad("%s: always must be true", key)
			end
		elseif kind == "halloween" then
			if not HALLOWEEN[rule.halloween] then
				bad(
					"%s: halloween must be KingWins or Candy, not %s",
					key,
					tostring(rule.halloween)
				)
			end
			if not whole(rule.atLeast) then
				bad("%s: atLeast must be a whole number of at least 1", key)
			end
		elseif kind == "event" then
			if not EVENTS[rule.event] then
				bad("%s: unknown event %s", key, tostring(rule.event))
			end
		end
	end
	if #list > Config.Save.MaxBadgeEntries then
		bad("%d rows, more than a save holds (%d)", #list, Config.Save.MaxBadgeEntries)
	end
	if expectedCount and #list ~= expectedCount then
		bad("%d rows, expected %d", #list, expectedCount)
	end
	return problems
end

return Badges
