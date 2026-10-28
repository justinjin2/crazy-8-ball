--!strict
-- CandyMath: a real match's Candy at settle (Config.Halloween.Match; docs/halloween/PLAN.md).
-- Pure.
--
--   base  = PerBall x balls x farm.Balls + Finished x finished x farm.Bonus + Win x won x farm.Bonus
--   Candy = round(base x event multiplier x (1 + friends + group))
--
-- The friends and group parts are read only through Money (Money.friendBoost, the "Group" part
-- of Money.boostParts; the GUI lane's Config.Economy lines), so one switch turns the friend part
-- off for money and Candy together. Before those functions exist (or if one errors) the same
-- Config.Economy keys are read directly.
local Config = require(script.Parent.Parent.Config)
local Money = require(script.Parent.Parent.Progression.Money)

local C = Config.Halloween
local E: any = Config.Economy

local CandyMath = {}

export type MatchFacts = {
	balls: number, -- balls that counted for the player's side (Economy.tally)
	finished: number, -- 1: the player's side did not forfeit a real match; 0: it did
	won: number, -- 1 or 0
	farmBalls: number?, -- Money.farmRow().Balls, default 1
	farmBonus: number?, -- Money.farmRow().Bonus, default 1
}

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function whole(x: any): number
	return if finite(x) then math.max(0, math.floor(x)) else 0
end

local function factor(x: any): number
	if x == nil then
		return 1
	end
	return if finite(x) and x >= 0 then x else 0
end

-- The match's Candy before any multiplier.
function CandyMath.base(facts: MatchFacts): number
	local M = C.Match
	local finished = if whole(facts.finished) > 0 then 1 else 0
	local won = if whole(facts.won) > 0 then 1 else 0
	return M.PerBall * whole(facts.balls) * factor(facts.farmBalls)
		+ M.Finished * finished * factor(facts.farmBonus)
		+ M.Win * won * factor(facts.farmBonus)
end

export type Settled = {
	real: boolean, -- past the one-minute mark (or a bot match that always counts)
	payKind: string, -- Settle.moneyKind: "Player", "PC", ...
	botKind: string?, -- Settle.botKind: "Tutorial", "Disguised", "Pc" or nil
}

-- How a settled match pays Candy: "Paid" for a real match against people (the tutorial's bot
-- counts: PLAN "Candy still counts from the first match"), else "Short" (not real), "Disguised"
-- (a disguised bot, never paid so a "+0" never outs it) or "PC".
function CandyMath.how(f: Settled): string
	if not f.real then
		return "Short"
	elseif f.botKind == "Disguised" then
		return "Disguised"
	elseif f.payKind ~= "Player" then
		return "PC"
	end
	return "Paid"
end

-- `finished` for CandyMath.base: 1 unless the player's side forfeited the (real) match. The
-- winner of a real forfeit (a surrender, out of timeouts, the other side emptied after the
-- one-minute mark) gets it; the side that forfeited keeps only its balls.
function CandyMath.finished(forfeited: boolean?): number
	return if forfeited == true then 0 else 1
end

-- The friend part for `friends` in the server (uncapped count; Money caps it).
function CandyMath.friendsAdd(friends: number): number
	local fn = (Money :: any).friendBoost
	if type(fn) == "function" then
		local ok, value = pcall(fn, friends)
		if ok and finite(value) and value >= 0 then
			return value
		end
	end
	if E.FriendBoostEnabled ~= true or not finite(E.FriendBoost) then
		return 0
	end
	local cap = if finite(E.FriendBoostMaxFriends) then E.FriendBoostMaxFriends else 0
	return E.FriendBoost * math.min(whole(friends), cap)
end

-- The group part for a member of the game's group (0 for anyone else).
function CandyMath.groupAdd(inGroup: boolean): number
	if not inGroup then
		return 0
	end
	local fn = (Money :: any).boostParts
	if type(fn) == "function" then
		local ok, parts = pcall(fn, { group = true })
		if ok and type(parts) == "table" then
			for _, part in parts do
				if type(part) == "table" and part.kind == "Group" and finite(part.add) then
					return part.add
				end
			end
			return 0
		end
	end
	return if finite(E.GroupBoost) then E.GroupBoost else 0
end

-- The whole multiplier: the event's (1 or 2) x (1 + friends + group).
function CandyMath.multiplier(event: number, friends: number, inGroup: boolean): number
	return event * (1 + CandyMath.friendsAdd(friends) + CandyMath.groupAdd(inGroup))
end

-- `amount` boosted by `multiplier`, rounded half up (a whole amount).
function CandyMath.apply(amount: number, multiplier: number): number
	return Money.round(amount * multiplier)
end

-- A match's Candy: the base times the multiplier, rounded.
function CandyMath.match(facts: MatchFacts, multiplier: number): number
	return CandyMath.apply(CandyMath.base(facts), multiplier)
end

-- The boost as the pill shows it: +40% for 0.4 (the multiplier above 1, without the event's).
function CandyMath.percent(friends: number, inGroup: boolean): number
	return Money.round(100 * (CandyMath.friendsAdd(friends) + CandyMath.groupAdd(inGroup)))
end

return CandyMath
