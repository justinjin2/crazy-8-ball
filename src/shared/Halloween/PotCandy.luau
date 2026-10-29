--!strict
-- PotCandy: Candy per pocket (designer, 2026-10-29: Candy follows the money, pot by pot, and
-- flies to the Candy pill like the cash). Pure. Config.Halloween.Match:
--
--   PerPocketEnabled  the switch: false is the old settle-time Candy (CandyMath.base at settle)
--   PerPocket         Candy for each pot that paid the player money (a "Ball" grant)
--
-- A pot's Candy = PerPocket x the anti-farm factor money's ball pay uses (Money.farmRow().Balls)
-- x the Candy multiplier (CandyMath.multiplier: the Rush or Oct 31 x (1 + friends + group)).
-- The exact amounts add up over the match and each pot pays what the rounded running total
-- grew by, so the match's Candy is round(sum), never a rounding up on every pot (a +10% boost
-- on 3 is 3.3, not 4).
--
-- Who it pays (PotCandy.eligible): matches against people and disguised bots (they pay like
-- people: designer, 2026-10-29), never practice against PC (or the King), solo or a tutorial
-- bot. A pot money pays at the flat short-match rate (Settle.shortCapped) pays no Candy.
--
-- Replay-safe: a shot (its seq, unique in a match) pays once; a second call for the same seq
-- pays nothing. The caller keeps the State with the match's money tally and commits the next
-- State only once the save took the Candy.
local Config = require(script.Parent.Parent.Config)
local Money = require(script.Parent.Parent.Progression.Money)

local M = Config.Halloween.Match

local PotCandy = {}

-- One player's Candy so far in one match (kept with Economy's tally).
export type State = {
	exact: number, -- the exact Candy earned (before rounding)
	paid: number, -- the whole Candy paid (round(exact) as it was paid)
	seqs: { [number]: boolean }, -- the shots already paid
	x2: boolean, -- some of it came in a Rush or on Oct 31 (the end-of-match chip's "2x")
}

export type Shot = {
	pots: number, -- the shot's pots that paid the player money ("Ball" grants)
	farm: number?, -- Money.farmRow().Balls (1 when missing)
	multiplier: number, -- CandyMath.multiplier
	event: number?, -- the event's own part of it (Event.multiplier: 1 or 2), for x2
	seq: number?, -- the shot's seq (nil: no replay guard)
}

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function whole(x: any): number
	return if finite(x) then math.max(0, math.floor(x)) else 0
end

--- A fresh State for a player's match.
function PotCandy.new(): State
	return { exact = 0, paid = 0, seqs = {}, x2 = false }
end

--- Whether Candy is paid per pocket now (both switches on). False: the old settle-time Candy.
function PotCandy.on(): boolean
	return M.Enabled == true and M.PerPocketEnabled == true
end

--- Whether a match against `opponent` (Settle.opponentKind: "Player", "PC", "Solo") with a bot
--- of `botKind` (Settle.botKind: "Tutorial", "Disguised", "Pc" or nil) pays Candy per pocket.
function PotCandy.eligible(opponent: string?, botKind: string?): boolean
	return opponent == "Player" and (botKind == nil or botKind == "Disguised")
end

--- The Candy of each of a shot's pots, and the State after it (the caller keeps it only once
--- the save took the Candy). A shot already paid (its seq) or with no pots pays nothing and
--- leaves the State as it was.
function PotCandy.shot(state: State, shot: Shot): ({ number }, State)
	local amounts: { number } = {}
	local pots = whole(shot.pots)
	local seq = shot.seq
	if pots < 1 or (seq ~= nil and state.seqs[seq] == true) then
		return amounts, state
	end
	local farm = if shot.farm == nil then 1 elseif finite(shot.farm) then shot.farm else 0
	local multiplier = if finite(shot.multiplier) then shot.multiplier else 0
	local each = math.max(0, M.PerPocket * math.max(0, farm) * math.max(0, multiplier))
	local exact, paid = state.exact, state.paid
	for _ = 1, pots do
		exact += each
		local total = Money.round(exact)
		table.insert(amounts, math.max(0, total - paid))
		paid = math.max(paid, total)
	end
	local seqs = table.clone(state.seqs)
	if seq ~= nil then
		seqs[seq] = true
	end
	local event = if finite(shot.event) then shot.event :: number else 1
	return amounts,
		{
			exact = exact,
			paid = paid,
			seqs = seqs,
			x2 = state.x2 or (event > 1 and paid > state.paid),
		}
end

--- The sum of a list of pot amounts.
function PotCandy.sum(amounts: { number }): number
	local total = 0
	for _, n in amounts do
		total += whole(n)
	end
	return total
end

-- What a settled match does with Candy and quests while Candy is paid per pocket.
export type Settled = {
	real: boolean, -- past the one-minute mark (or a bot match that always counts)
	opponent: string?, -- Settle.opponentKind
	botKind: string?, -- Settle.botKind
	candy: number, -- the Candy its pots paid the player (State.paid)
}

export type SettleDecision = {
	how: string, -- the HwMatch event's field: "Paid", "Disguised", "Short", "Tutorial" or "PC"
	quests: boolean, -- count the match for the quests (Matches, Wins, Balls, ...)
	log: number, -- the one HwCandy "Match" event's value (0: no event)
	toast: number, -- the end-of-match Candy chip (0: none)
}

--- At settle, per pocket: no Candy is added (the pots paid it); the match's total is logged
--- once (HwCandy "Match") and shown once (the end-of-match chip), and a real match against
--- people or a disguised bot counts for the quests. A short match logs and shows its pots'
--- Candy too but counts for no quest; a tutorial or PC match pays none and counts none (the
--- King's quests are CandyService's, on "PC").
function PotCandy.settle(f: Settled): SettleDecision
	local candy = whole(f.candy)
	local how
	if f.botKind == "Tutorial" then
		how = "Tutorial"
	elseif not PotCandy.eligible(f.opponent, f.botKind) then
		how = "PC"
	elseif not f.real then
		how = "Short"
	elseif f.botKind == "Disguised" then
		how = "Disguised" -- (its own name, so their share can be measured)
	else
		how = "Paid"
	end
	local counts = how == "Paid" or how == "Disguised"
	local paysCandy = counts or how == "Short"
	return {
		how = how,
		quests = counts,
		log = if paysCandy then candy else 0,
		toast = if paysCandy then candy else 0,
	}
end

return PotCandy
