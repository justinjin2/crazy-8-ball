--!strict
-- PlayerListView: the pure half of the player list (GUI lane, designer 2026-10-03, C7, D10).
-- A disguised bot's fixed "wins vs players" for its tier, a country code as its flag emoji, and
-- the list's order. Pure: no Instances, no clocks, no randomness (a bot's number comes from its
-- id), so every client shows the same. Lune-tested (tests/playerlist_test.luau).
local Config = require(script.Parent.Parent.Config)

local PlayerListView = {}

export type Row = {
	id: number,
	name: string,
	rankIndex: number,
	wins: number,
	you: boolean?,
}

--- A bot's believable wins vs players: a whole number in its tier's Config range, the same
--- every time for the same id (a hash of the id, never random).
function PlayerListView.botWins(tier: string, id: number): number
	local ranges = Config.UI.PlayerList.BotWins
	local range = ranges[tier] or ranges.Bronze
	local low, high = range[1], range[2]
	-- A small integer hash of the id (Knuth's multiplicative, kept in 32 bits).
	local n = math.abs(math.floor(id)) % 2147483647
	local h = (n * 2654435761) % 4294967296
	local share = (h % 10007) / 10006
	return low + math.floor((high - low) * share + 0.5)
end

--- The flag emoji of a two-letter country code ("US" -> regional indicators U S), or "" for
--- anything else.
function PlayerListView.flag(code: any): string
	if type(code) ~= "string" or not string.match(code, "^%a%a$") then
		return ""
	end
	local upper = string.upper(code)
	local base = 0x1F1E6 - string.byte("A")
	return utf8.char(base + string.byte(upper, 1), base + string.byte(upper, 2))
end

--- The list's order: you first, then by rank (highest first), then wins, then name, then id.
function PlayerListView.sort(rows: { Row })
	table.sort(rows, function(a: Row, b: Row): boolean
		if (a.you == true) ~= (b.you == true) then
			return a.you == true
		end
		if a.rankIndex ~= b.rankIndex then
			return a.rankIndex > b.rankIndex
		end
		if a.wins ~= b.wins then
			return a.wins > b.wins
		end
		local an, bn = string.lower(a.name), string.lower(b.name)
		if an ~= bn then
			return an < bn
		end
		return a.id < b.id
	end)
end

return PlayerListView
