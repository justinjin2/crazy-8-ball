--!strict
-- The ult catalog (docs/prompts/ULTIMATES_PROMPT.md section 6): the 13 ults as data rows, read
-- from Config.Ults (Order, Catalog, Rarities) and Strings.Ults (names, descriptions). Pure: no
-- Instances, no Roblox APIs, no clocks, no randomness, and every list is walked in
-- Config.Ults.Order or Config.Ults.Rarities, never hash order.
--
-- A new ult is a Config row plus a Strings name and description, never new code here. A row
-- with Built = false is a placeholder: it can only be rolled or equipped with the developer
-- flag (`devAll`, Config.Ults.DevAllUlts or `/ultsall on`). Every function answers safely for
-- an unknown id or a value that is not a string (nil, false, 0 or "").
local Config = require(script.Parent.Parent.Config)
local Strings = require(script.Parent.Parent.Strings)

local U = Config.Ults

type Row = {
	Rarity: string,
	Built: boolean,
	Effect: string?,
	Worth: number,
	MaxBalls: number?,
	Pick: string?,
	Area: boolean?,
	Redo: boolean?,
	Turn: boolean?,
	Sneak: boolean?,
}
local ROWS: { [string]: Row } = U.Catalog :: any
local NAMES: { [string]: string } = Strings.Ults.Names :: any
local DESCRIPTIONS: { [string]: string } = Strings.Ults.Descriptions :: any

export type Ult = {
	Id: string,
	Rarity: string, -- one of Config.Ults.Rarities
	Built: boolean, -- false: a placeholder (cutscene only, "Coming soon")
	Effect: string?, -- the module in src/shared/Ults/Effects for a built ult
	Worth: number, -- the power ladder's target, in balls per use
	MaxBalls: number?, -- the most balls one use may take (the top rarities)
	-- The aim-phase pick it needs before the shot: "OwnBall" (Heat Seeker) or "Portals".
	Pick: string?,
	-- An area ability (the skill rule, ABILITIES_PROMPT 5.7): it also acts on the opponent's
	-- balls, at Config.Ults.Shared.OpponentFactor, and shows its reach while aiming.
	Area: boolean?,
	-- Rewind (7.6): a shot that drops none of the shooter's balls is undone and redone.
	Redo: boolean?,
	-- Portals (7.9): it acts on every shot of the rest of the shooter's turn too.
	Turn: boolean?,
	-- Look Over There! (the rework): after arming, the Sneak phase (a ball dragged into a
	-- pocket) instead of an effect on the next shot.
	Sneak: boolean?,
}

local Catalog = {}

-- Ids in the catalog, for a quick lookup (built from the Order array).
local KNOWN: { [string]: boolean } = {}
for _, id in U.Order do
	if ROWS[id] ~= nil then
		KNOWN[id] = true
	end
end

-- Rarity -> its place on the ladder (Common = 1 ... Mythic = 6).
local RARITY_INDEX: { [string]: number } = {}
for index, rarity in U.Rarities do
	RARITY_INDEX[rarity] = index
end

--- True for an id in the catalog (listed in Config.Ults.Order with a row).
function Catalog.exists(id: any): boolean
	return type(id) == "string" and KNOWN[id] == true
end

--- An ult by id, as a new table (changing it changes nothing); nil for an unknown id.
function Catalog.get(id: any): Ult?
	if not Catalog.exists(id) then
		return nil
	end
	local row = ROWS[id]
	return {
		Id = id,
		Rarity = row.Rarity,
		Built = row.Built == true,
		Effect = row.Effect,
		Worth = row.Worth,
		MaxBalls = row.MaxBalls,
		Pick = row.Pick,
		Area = row.Area == true,
		Redo = row.Redo == true,
		Turn = row.Turn == true,
		Sneak = row.Sneak == true,
	}
end

--- What a retired ult id (taken out of the game, Config.Ults.Retired) becomes in a saved slot,
--- or nil for any other value.
function Catalog.retired(id: any): string?
	if type(id) ~= "string" then
		return nil
	end
	local to = (U.Retired :: { [string]: string })[id]
	return if to ~= nil and KNOWN[to] then to else nil
end

--- The ult's rarity; nil for an unknown id.
function Catalog.rarity(id: any): string?
	if not Catalog.exists(id) then
		return nil
	end
	return ROWS[id].Rarity
end

--- A rarity's place on the ladder: Common = 1 ... Mythic = 6 (Config.Ults.Rarities). 0 for
--- anything else, so an unknown rarity is never "at least" a real one.
function Catalog.rarityIndex(rarity: any): number
	if type(rarity) ~= "string" then
		return 0
	end
	return RARITY_INDEX[rarity] or 0
end

--- The ult's icon image (Config.Ults.Assets.Icons), or "" for an unknown id or one with none.
function Catalog.icon(id: any): string
	if not Catalog.exists(id) then
		return ""
	end
	return U.Assets.Icons[id] or ""
end

--- True when the ult has its effect (Built = true); false for a placeholder or unknown id.
function Catalog.built(id: any): boolean
	return Catalog.exists(id) and ROWS[id].Built == true
end

--- True when a player may roll or play with the ult: it is built, or it is anything in the
--- catalog and the developer flag `devAll` is exactly true.
function Catalog.usable(id: any, devAll: boolean?): boolean
	if not Catalog.exists(id) then
		return false
	end
	return ROWS[id].Built == true or devAll == true
end

--- Every ult id, in Config.Ults.Order (a new array).
function Catalog.list(): { string }
	local list: { string } = {}
	for _, id in U.Order do
		if KNOWN[id] then
			table.insert(list, id)
		end
	end
	return list
end

--- The ult ids of one rarity, in Config.Ults.Order (empty for an unknown rarity).
function Catalog.byRarity(rarity: any): { string }
	local list: { string } = {}
	for _, id in U.Order do
		if KNOWN[id] and ROWS[id].Rarity == rarity then
			table.insert(list, id)
		end
	end
	return list
end

--- The ult's player-facing name (Strings.Ults.Names). An unknown id gives "".
function Catalog.name(id: any): string
	if not Catalog.exists(id) then
		return ""
	end
	return NAMES[id] or id
end

--- The ult's one-line description (Strings.Ults.Descriptions). An unknown id gives "".
function Catalog.description(id: any): string
	if not Catalog.exists(id) then
		return ""
	end
	return DESCRIPTIONS[id] or ""
end

--- Problems with the catalog's data, empty when it is sound: every Order id has a row, a
--- known rarity, a name and a description; no id is listed twice; the default ult is built;
--- a built ult names its Effect. The tests call it; a new row that breaks a rule fails them.
function Catalog.validate(): { string }
	local problems: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, id in U.Order do
		local row = ROWS[id]
		if seen[id] then
			table.insert(problems, id .. " is listed twice in Order")
		end
		seen[id] = true
		if row == nil then
			table.insert(problems, id .. " has no Catalog row")
		else
			if RARITY_INDEX[row.Rarity] == nil then
				table.insert(
					problems,
					("%s has an unknown rarity %s"):format(id, tostring(row.Rarity))
				)
			end
			-- Rewind and Look Over There! need no physics effect: the redo and the sneak are
			-- the match engine's (row.Redo, row.Sneak).
			if row.Built and type(row.Effect) ~= "string" and not row.Redo and not row.Sneak then
				table.insert(problems, id .. " is built but names no Effect")
			end
			if type(NAMES[id]) ~= "string" or type(DESCRIPTIONS[id]) ~= "string" then
				table.insert(problems, id .. " has no name or description in Strings.Ults")
			end
		end
	end
	if not Catalog.built(U.Default) then
		table.insert(problems, "the default ult " .. tostring(U.Default) .. " is not built")
	end
	return problems
end

return Catalog
