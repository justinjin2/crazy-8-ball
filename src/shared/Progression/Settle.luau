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
-- - a winner's Case Drop needs at least one loser with enough real matches (the most
--   experienced loser counts), may drop while no loser has given FreeCasesPerOpponent drops
--   today, and counts against every loser's account.
local Config = require(script.Parent.Parent.Config)
local Cases = require(script.Parent.Cases)

local R = Config.Ranks
local E = Config.Economy

-- The results that end a game on the 8 against the shooter: a forfeit under the one-minute
-- mark (GDD section 13), an ordinary loss after it.
local EIGHT_LOSSES: { [string]: boolean } =
	{ EarlyEight = true, WrongPocket = true, FoulEight = true, EightOffTable = true }

-- One account on the losing side, for the winner's Case Drop. `realMatches` nil: not known
-- (the account is not in this server and left nothing behind), which never allows a case.
export type Loser = { realMatches: number?, casesToday: number }

-- What the Case Drop rule needs about one player's settled match (Settle.dropContext).
export type DropFacts = {
	real: boolean, -- past the one-minute mark
	solo: boolean,
	won: boolean,
	pc: boolean, -- against the computer or a bot: no account to farm, the loser rule is met
	pcLimited: boolean?, -- paid the PC rows (Play against PC): PcDropsPerDay drops a day
	pcDropsToday: number?, -- today's Daily.PcDrops before this match
	firstWinDue: boolean, -- the first win's Rare Case was never given (Progress.FirstWinCaseDue)
	farmAllows: boolean, -- the anti-farm row's FreeCase (Money.farmRow)
	losers: { Loser }, -- the other side's accounts (empty against PC)
}

export type BoostFlags = { streak: boolean }

-- Today's anti-farm count against one account (the save's Daily.Opponents entry).
export type OpponentDay = { Matches: number, Cases: number }

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

--- The kind of bot at a match (the Bots lane: a bot's seat carries `bot = { kind, ... }`):
--- "Pc" (Play against PC, Fill with PC: shown as PC), "Disguised" (looks like a person) or
--- "Tutorial" (the new player's first opponents), or nil with no bot.
function Settle.botKind(e: any): string?
	if type(e) ~= "table" or type(e.seats) ~= "table" then
		return nil
	end
	for _, s in e.seats do
		if type(s.bot) == "table" and type(s.bot.kind) == "string" then
			return s.bot.kind
		end
	end
	return nil
end

--- Whether seat `userId` of match `e` is a bot.
function Settle.isBot(e: any, userId: number): boolean
	if type(e) ~= "table" or type(e.seats) ~= "table" then
		return false
	end
	for _, s in e.seats do
		if s.userId == userId then
			return type(s.bot) == "table"
		end
	end
	return false
end

--- Who a match is against, for the money and XP rules: "Solo" (a player practising alone,
--- `e.solo`), "PC" (`e.pc = true`, or a PC bot) or "Player" (people, and disguised and
--- tutorial bots, which pay like people: the designer, 2026-10-02).
function Settle.opponentKind(e: any): string
	if type(e) ~= "table" then
		return "Player"
	elseif e.solo ~= nil then
		return "Solo"
	elseif e.pc == true or Settle.botKind(e) == "Pc" then
		return "PC"
	end
	return "Player"
end

--- Who a match PAYS like, for one player (ECONOMY 3.2): Settle.opponentKind, except that a
--- disguised bot pays the PC rows (the PC bonuses and daily cap, no Case Drop) once the player
--- has Config.Economy.DisguisedDailyWins disguised wins today (`disguisedWinsToday`). Hidden:
--- the XP and the stats still treat it as before (Settle.opponentKind, recordAs).
function Settle.moneyKind(e: any, disguisedWinsToday: number): string
	local kind = Settle.opponentKind(e)
	if
		kind == "Player"
		and Settle.botKind(e) == "Disguised"
		and whole(disguisedWinsToday) >= E.DisguisedDailyWins
	then
		return "PC"
	end
	return kind
end

--- A bot match that counts whatever the match time (the designer, 2026-10-02): every
--- tutorial game (its early 8 pays in full) and a disguised bot that left mid-match (its
--- forfeit pays the real player in full, even under the one-minute mark).
function Settle.botReal(e: any): boolean
	if type(e) ~= "table" or type(e.seats) ~= "table" then
		return false
	end
	for _, s in e.seats do
		local b = s.bot
		if
			type(b) == "table"
			and (b.kind == "Tutorial" or (b.kind == "Disguised" and b.vanished == true))
		then
			return true
		end
	end
	return false
end

--- How a match is recorded in the stats (PlayerData.recordMatch): a win against a disguised
--- bot is a PC win (never the most-wins board, not a real win); the tutorial's are real.
function Settle.recordAs(e: any, kind: string): string
	return if Settle.botKind(e) == "Disguised" then "PC" else kind
end

--- Whether a win can add to the win streak: against people only (no bot of any kind).
function Settle.streakCounts(e: any): boolean
	return Settle.opponentKind(e) == "Player" and Settle.botKind(e) == nil
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

--- Today's anti-farm count against one account (ECONOMY 3.6), from the save's per-day table
--- (Daily.Opponents, `tracked` entries in all): its own `entry` when the table keeps one;
--- zeros for an account not met today while the table has room; and, once the table is full
--- (Config.Economy.SameOpponentMaxEntries), the worst count for an account it does not track:
--- enough matches to put the next one on SameOpponent's last row, and FreeCasesPerOpponent
--- cases. Meeting many accounts in a day never switches the anti-farm off: a new account then
--- pays the floor and gives no free case.
function Settle.opponentDay(entry: OpponentDay?, tracked: number): OpponentDay
	if entry ~= nil then
		return { Matches = whole(entry.Matches), Cases = whole(entry.Cases) }
	elseif whole(tracked) < E.SameOpponentMaxEntries then
		return { Matches = 0, Cases = 0 }
	end
	-- The last row (no UpTo) starts right after the row before it ends: that row's UpTo
	-- matches already played put the next one on it (0 with one row).
	local rows: { { UpTo: number? } } = E.SameOpponent :: any
	local before = rows[#rows - 1]
	return {
		Matches = if before ~= nil then whole(before.UpTo) else 0,
		Cases = E.FreeCasesPerOpponent,
	}
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
--- 4.5): only the streak since 2026-10-02, on a win that makes it Boosts.StreakFrom or more
--- (`streakAfter`, Ranks.nextStreak's count after the match). `won` means a win that counts
--- (a real match).
function Settle.boosts(f: {
	won: boolean,
	streakAfter: number,
}): BoostFlags
	return {
		streak = f.won == true and whole(f.streakAfter) >= R.Boosts.StreakFrom,
	}
end

--- The Case Drop rule's context (Cases.dropFor) for one player's settled match. Against PC
--- there is no account: no drops from it yet, and the loser rule is met. Otherwise the most
--- experienced loser counts for FreeCaseLoserMinMatches (an unknown one counts 0) and the
--- loser who has given the most drops today counts for FreeCasesPerOpponent.
function Settle.dropContext(f: DropFacts): Cases.DropContext
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
		pcLimited = f.pcLimited == true,
		pcDropsToday = whole(f.pcDropsToday),
		farmAllows = f.pc or f.farmAllows == true,
		casesFromOpponentToday = casesToday,
		loserRealMatches = loserMatches,
		firstWinEver = f.firstWinDue == true,
	}
end

return Settle
