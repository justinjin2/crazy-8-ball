--!strict
-- Settle: the small choices the server makes when it pays a shot or a finished match
-- (src/server/Economy.luau and Ranking.luau; docs/ECONOMY.md sections 3.3, 3.6, 4.4, 4.5 and
-- 7.1), kept apart so Lune can test them. Pure: no Instances, no clocks, no randomness, and
-- every loop walks an array in the order it was given. The engine table read here is plain
-- data (Rules/MatchEngine), never an Instance.
--
-- Team matches (ECONOMY 3.3, overnight assumptions 2026-09-28):
-- - the anti-farm row uses the most-played account on the other side today;
-- - the gap uses the other side's average division, Unranked counting as Bronze I;
-- - a winner's free case needs at least one loser with enough real matches (the most
--   experienced loser counts), may drop while no loser has given FreeCasesPerOpponent cases
--   today, and counts against every loser's account.
local Config = require(script.Parent.Parent.Config)
local Cases = require(script.Parent.Cases)

local R = Config.Ranks
local E = Config.Economy

-- The results that end a game on the 8 against the shooter: a forfeit under the one-minute
-- mark (GDD section 13), an ordinary loss after it.
local EIGHT_LOSSES: { [string]: boolean } =
	{ EarlyEight = true, WrongPocket = true, FoulEight = true, EightOffTable = true }

-- One account on the losing side, for the winner's free case. `realMatches` nil: not known
-- (the account is not in this server and left nothing behind), which never allows a case.
export type Loser = { realMatches: number?, casesToday: number }

-- What the free-case rule needs about one player's settled match (Settle.freeCaseContext).
export type FreeCaseFacts = {
	real: boolean, -- past the one-minute mark
	solo: boolean,
	won: boolean,
	pc: boolean, -- against the computer: no account to farm, the loser rule is met
	winsBefore: number, -- Progress.Wins before this match
	winsTodayBefore: number, -- today's Daily.Wins before this match
	firstWinDue: boolean, -- the first win's Rare Case was never given (Progress.FirstWinCaseDue)
	farmAllows: boolean, -- the anti-farm row's FreeCase (Money.farmRow)
	losers: { Loser }, -- the other side's accounts (empty against PC)
}

export type BoostFlags = { rookie: boolean, vip: boolean, firstWin: boolean, streak: boolean }

local Settle = {}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- A whole number >= 0 (anything else is 0).
local function whole(value: any): number
	if not finite(value) or value < 0 then
		return 0
	end
	return math.floor(value)
end

--- Who a match is against, for the money and XP rules: "Solo" (a player practising alone,
--- `e.solo`), "PC" (the engine marks a match against the computer with `e.pc = true`; bots
--- are not built yet, so nothing sets it) or "Player".
function Settle.opponentKind(e: any): string
	if type(e) ~= "table" then
		return "Player"
	elseif e.solo ~= nil then
		return "Solo"
	elseif e.pc == true then
		return "PC"
	end
	return "Player"
end

--- Whether a match counts (GDD section 13): `seconds` of server time from the break reached
--- Config.Ranks.RealMatchSeconds.
function Settle.isReal(seconds: any): boolean
	return finite(seconds) and seconds >= R.RealMatchSeconds
end

--- The team that forfeited a finished match, or nil: the engine's own `forfeit` (a surrender
--- or running out of timeouts), else the side that emptied (everyone left) or, under the
--- one-minute mark, the side that lost on the 8 (an early 8 is a forfeit, GDD section 13).
function Settle.forfeitTeam(result: any, real: boolean): number?
	if type(result) ~= "table" then
		return nil
	end
	local forfeit = result.forfeit
	if type(forfeit) == "number" then
		return forfeit
	end
	local winner = result.winner
	if type(winner) ~= "number" then
		return nil
	end
	if result.reason == "EmptyTeam" or (not real and EIGHT_LOSSES[result.reason] == true) then
		return 3 - winner
	end
	return nil
end

--- A team's outcome: "Win", "Loss", or "Draw" when nobody won.
function Settle.outcome(team: number, winner: number?): string
	if winner == nil then
		return "Draw"
	end
	return if team == winner then "Win" else "Loss"
end

--- The other side's division index for the gap (ECONOMY 4.4): the average of `indices`, each
--- Unranked (0, or anything below 1) counted as Bronze I (1) before averaging. nil when the
--- list is empty (an opponent with no rank known: Ranks.gapFactor then treats it as equal).
function Settle.opponentIndex(indices: { number }): number?
	local sum, n = 0, 0
	for _, index in indices do
		if finite(index) then
			sum += math.max(1, index)
			n += 1
		end
	end
	if n == 0 then
		return nil
	end
	return sum / n
end

--- This match's number against the same opponent today (ECONOMY 3.6), for Money.farmRow:
--- 1 + the most matches already played today against any one account on the other side (a
--- team match uses the most-played opponent). 1 with no accounts (PC, solo).
function Settle.matchNumber(matchesToday: { number }): number
	local most = 0
	for _, matches in matchesToday do
		most = math.max(most, whole(matches))
	end
	return most + 1
end

--- Whether balls potted now pay the short-match rate (ECONOMY 3.6): today's short-match money
--- has reached Config.Economy.ShortDailyCap and the match is still under the one-minute mark
--- (`sinceBreak` seconds from the break; nil before the break, which is under it).
function Settle.shortCapped(shortToday: number, sinceBreak: number?): boolean
	if whole(shortToday) < E.ShortDailyCap then
		return false
	end
	return not finite(sinceBreak) or (sinceBreak :: number) < R.RealMatchSeconds
end

--- The XP boosts that are on for one player's match (Ranks.MatchContext.boosts; ECONOMY 4.3,
--- 4.5): Rookie while fewer than Boosts.RookieMatches real matches were played before this one;
--- VIP; the first win of the UTC day on a win that gives XP (`farmXp` above 0) while it is
--- still unused; the streak on a win that makes it Boosts.StreakFrom or more (`streakAfter`,
--- Ranks.nextStreak's count after the match). `won` means a win that counts (a real match).
function Settle.boosts(f: {
	realMatches: number,
	vip: boolean,
	won: boolean,
	firstWinUsed: boolean,
	streakAfter: number,
	farmXp: number,
}): BoostFlags
	return {
		rookie = whole(f.realMatches) < R.Boosts.RookieMatches,
		vip = f.vip == true,
		firstWin = f.won == true and f.firstWinUsed ~= true and finite(f.farmXp) and f.farmXp > 0,
		streak = f.won == true and whole(f.streakAfter) >= R.Boosts.StreakFrom,
	}
end

--- The free-case rule's context (Cases.freeCase) for one player's settled match. Against PC
--- there is no account: no cases from it yet, and the loser rule is met. Otherwise the most
--- experienced loser counts for FreeCaseLoserMinMatches (an unknown one counts 0) and the
--- loser who has given the most cases today counts for FreeCasesPerOpponent.
function Settle.freeCaseContext(f: FreeCaseFacts): Cases.FreeCaseContext
	local casesToday, loserMatches = 0, 0
	if f.pc then
		loserMatches = math.huge
	else
		for _, loser in f.losers do
			casesToday = math.max(casesToday, whole(loser.casesToday))
			loserMatches = math.max(loserMatches, whole(loser.realMatches))
		end
	end
	return {
		real = f.real == true,
		solo = f.solo == true,
		won = f.won == true,
		winsBefore = whole(f.winsBefore),
		winsTodayBefore = whole(f.winsTodayBefore),
		farmAllows = f.pc or f.farmAllows == true,
		casesFromOpponentToday = casesToday,
		loserRealMatches = loserMatches,
		firstWinEver = f.firstWinDue == true,
	}
end

return Settle
