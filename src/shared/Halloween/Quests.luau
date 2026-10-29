--!strict
-- Quests: the Halloween event's daily quest boards (Config.Halloween.Quests). Pure.
--
-- Board N opens with Event.boardOpensAt(N). A quest's progress is the save's
-- Q["<board>.<slot>"]; a finished quest is claimed once (Claimed) for Rewards[slot] Candy.
--
-- Today's board only (designer, 2026-10-29): every event counts once, on today's board (the
-- newest open one, Event.boardIndex), toward its first unfinished quest of that kind; an amount
-- (balls, seconds) fills that quest and the rest flows on to the board's next quest of the same
-- kind. An older board never moves again, so once a newer board opens its finished, unclaimed
-- quests are paid by themselves (pastDue).
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

-- Counts `amount` of `kind` in `q` (the save's Q, changed in place) on board `today` only (none
-- before the first board or past the last): its first unfinished quest of that kind, the rest
-- flowing on to the next. Returns what changed.
function Quests.route(
	q: { [string]: number },
	today: number,
	hooks: Hooks,
	kind: string,
	amount: number
): { Routed }
	local changed: { Routed } = {}
	local left = if type(amount) == "number" and amount == amount then math.floor(amount) else 0
	if left <= 0 then
		return changed
	end
	local list: { Quest } = Quests.board(today, hooks) or {}
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
	return changed
end

-- The quest behind `key` on an open board (nil for a key that is not one). Only the quest's
-- own spelling ("1.4", never "01.4" or "1.04"): a claim is recorded under the key sent.
function Quests.find(key: string, open: number, hooks: Hooks): Quest?
	local board, slot = string.match(key, "^(%d+)%.(%d+)$")
	local n, s = tonumber(board), tonumber(slot)
	if n == nil or s == nil or n < 1 or n > math.min(open, Quests.count()) then
		return nil
	end
	if key ~= Quests.key(n, s) then
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
		local board: { Quest } = Quests.board(n, hooks) or {}
		for _, quest in board do
			if claimed[quest.key] ~= true and Quests.done(q, quest) then
				table.insert(list, quest)
			end
		end
	end
	return list
end

-- The quests of the boards before `today` that were finished and never claimed: paid by
-- themselves once a newer board opens (PlayerData.hwAutoClaim; they can never move again), by
-- the end's rule (endClaimable).
function Quests.pastDue(
	q: { [string]: number },
	claimed: { [string]: boolean },
	today: number,
	hooks: Hooks
): { Quest }
	return Quests.endClaimable(q, claimed, today - 1, hooks)
end

-- The end's claim (PlayerData.hwConvert): `claimable` with the hooks now, and also what was
-- finished as the event ran with the map lane's King and pickups on. A player converting on a
-- first join after the map switched them off (their quests read as Alts with higher needs)
-- keeps what they finished. Each quest once, in board order.
function Quests.endClaimable(
	q: { [string]: number },
	claimed: { [string]: boolean },
	open: number,
	hooks: Hooks
): { Quest }
	local mapOn: Hooks = { king = true, pickups = true, ult = hooks.ult }
	local now = Quests.claimable(q, claimed, open, hooks)
	local ran = Quests.claimable(q, claimed, open, mapOn)
	local seen: { [string]: boolean } = {}
	for _, quest in now do
		seen[quest.key] = true
	end
	for _, quest in ran do
		if not seen[quest.key] then
			seen[quest.key] = true
			table.insert(now, quest)
		end
	end
	table.sort(now, function(a: Quest, b: Quest): boolean
		return if a.board ~= b.board then a.board < b.board else a.slot < b.slot
	end)
	return now
end

return Quests
