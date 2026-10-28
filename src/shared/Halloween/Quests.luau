--!strict
-- Quests: the Halloween event's daily quest boards (Config.Halloween.Quests). Pure.
--
-- Board N opens with Event.boardOpensAt(N); older boards stay open. A quest's progress is the
-- save's Q["<board>.<slot>"]; a finished quest is claimed once (Claimed) for Rewards[slot] Candy.
--
-- Routing (hw-core's reading of PLAN's "in order, oldest unfinished first"): every event counts
-- once, toward the oldest open board whose quest of that kind is unfinished; an amount (balls,
-- seconds) fills that quest and the rest flows on to the next open quest of the same kind. So a
-- late joiner cannot clear several boards with one win, and a hard quest (the King) never
-- blocks the other quests of later boards.
--
-- Hooks: a quest whose hook is off is replaced by its Alt (the King or the lobby pickups
-- switched off in Config.HalloweenMap, or no ability signal from UltService).
local Config = require(script.Parent.Parent.Config)

local Q = Config.Halloween.Quests

local Quests = {}

export type Hooks = {
	king: boolean, -- the Pumpkin King is on (HalloweenMap.Enabled and .Boss.Enabled)
	pickups: boolean, -- lobby Candy is on (HalloweenMap.Enabled and .Candy.Enabled)
	ult: boolean, -- UltService.Used can be heard
}

export type Quest = {
	board: number,
	slot: number,
	key: string, -- "<board>.<slot>"
	kind: string,
	need: number,
	icon: string,
	reward: number,
}

export type Routed = { key: string, added: number, done: boolean }

-- The hook a kind needs, or nil when it needs none.
local HOOK_OF: { [string]: string } = {
	King = "king",
	Pickups = "pickups",
	UltMatches = "ult",
}

function Quests.key(board: number, slot: number): string
	return ("%d.%d"):format(board, slot)
end

function Quests.count(): number
	return #Q.Boards
end

-- Board `n`'s four quests with the Alts swapped in for hooks that are off (nil past the last).
function Quests.board(n: number, hooks: Hooks): { Quest }?
	local rows = Q.Boards[n]
	if rows == nil then
		return nil
	end
	local list: { Quest } = {}
	for slot, row in rows do
		local kind, need = row.Kind, row.Need
		local hook = HOOK_OF[kind]
		if hook ~= nil and (hooks :: any)[hook] ~= true and row.Alt ~= nil then
			kind, need = row.Alt.Kind, row.Alt.Need
		end
		table.insert(list, {
			board = n,
			slot = slot,
			key = Quests.key(n, slot),
			kind = kind,
			need = need,
			icon = if kind == row.Kind then row.Icon else Quests.iconOf(kind, row.Icon),
			reward = Q.Rewards[slot] or 0,
		})
	end
	return list
end

-- The icon for an Alt's kind (the kind's usual icon; `fallback` for one without).
local ICONS: { [string]: string } = {
	Matches = "Match",
	Wins = "Win",
	Balls = "Ball",
	NiceShots = "Nice",
	TeamMatches = "Team",
	TeamWins = "Team",
	UltMatches = "Ult",
	King = "King",
	Pickups = "Candy",
	Active = "Clock",
}
function Quests.iconOf(kind: string, fallback: string): string
	return ICONS[kind] or fallback
end

-- A quest's progress in the save (0 when none), never above its need.
function Quests.progress(q: { [string]: number }, quest: Quest): number
	local value = q[quest.key]
	if type(value) ~= "number" then
		return 0
	end
	return math.min(value, quest.need)
end

function Quests.done(q: { [string]: number }, quest: Quest): boolean
	return Quests.progress(q, quest) >= quest.need
end

-- Counts `amount` of `kind` in `q` (the save's Q, changed in place) across boards 1..`open`:
-- the oldest unfinished quest of that kind first, the rest flowing on. Returns what changed.
function Quests.route(
	q: { [string]: number },
	open: number,
	hooks: Hooks,
	kind: string,
	amount: number
): { Routed }
	local changed: { Routed } = {}
	local left = if type(amount) == "number" and amount == amount then math.floor(amount) else 0
	if left <= 0 then
		return changed
	end
	for n = 1, math.min(open, Quests.count()) do
		local list: { Quest } = Quests.board(n, hooks) or {}
		for _, quest in list do
			if left <= 0 then
				return changed
			end
			if quest.kind == kind then
				local have = Quests.progress(q, quest)
				if have < quest.need then
					local add = math.min(quest.need - have, left)
					q[quest.key] = have + add
					left -= add
					table.insert(changed, {
						key = quest.key,
						added = add,
						done = have + add >= quest.need,
					})
				end
			end
		end
	end
	return changed
end

-- The quest behind `key` on an open board (nil for a key that is not one).
function Quests.find(key: string, open: number, hooks: Hooks): Quest?
	local board, slot = string.match(key, "^(%d+)%.(%d+)$")
	local n, s = tonumber(board), tonumber(slot)
	if n == nil or s == nil or n < 1 or n > math.min(open, Quests.count()) then
		return nil
	end
	local list = Quests.board(n, hooks)
	return if list then list[s] else nil
end

-- Every finished, unclaimed quest on boards 1..`open`, in board order.
function Quests.claimable(
	q: { [string]: number },
	claimed: { [string]: boolean },
	open: number,
	hooks: Hooks
): { Quest }
	local list: { Quest } = {}
	for n = 1, math.min(open, Quests.count()) do
		local list: { Quest } = Quests.board(n, hooks) or {}
		for _, quest in list do
			if claimed[quest.key] ~= true and Quests.done(q, quest) then
				table.insert(list, quest)
			end
		end
	end
	return list
end

return Quests
