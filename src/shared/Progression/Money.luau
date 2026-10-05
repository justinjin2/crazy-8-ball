--!strict
-- What a shot and a match pay, in money (GDD section 12; every number in Config.Economy, from
-- docs/ECONOMY.md section 3). Pure: no Instances, no Roblox APIs, no clocks, no randomness,
-- and nothing that depends on the order a hash table happens to iterate in. The server pays
-- from these (src/server/Economy.luau, Ranking) off its own authoritative shot; the client
-- only animates what the server sends.
--
-- Which balls count for the shooter's team: nothing at all on a foul shot. Otherwise every
-- object ball on the break; every object ball on the legal pot that picks the colors (the
-- table was open for the shooter and the shot leaves them a group); after that only the
-- team's group; the 8 only when it wins the game for the shooter. Solo plays both groups, so
-- every object ball counts there. A shot that sinks the 8 early on an open table leaves no
-- group and so pays nothing, as the match's bonus stings (Rules/MatchEngine `Engine.awards`).
-- Each counting ball also pays the shooter a nice-shot bonus (Rules/NiceShot), except on the
-- break (the client never shows NICE SHOT! there either) and in solo (ECONOMY 3.2).
--
-- The order every amount is worked out in (ECONOMY 3.5, then the caps of 3.2 and 3.6):
--   1. base x difficulty x (1 + boost) x anti-farm (boosts add, then multiply);
--   2. the opponent's share: solo SoloShare, PC past its daily cap PcAfterCapShare, else 1;
--   3. round half up, and never below $1;
--   4. a flat after-cap pay replaces all of it: the short-match cap (ShortAfterCapPay) and
--      solo past its daily cap (SoloAfterCapPay), a ball each and no nice-shot bonus.
-- The daily counters (solo, PC) count the money actually paid, boosts included, and include
-- what this shot paid so far: the ball that crosses a cap pays in full, what comes after it
-- (its own nice shot too) at the capped rate.
local Config = require(script.Parent.Parent.Config)
local Judge = require(script.Parent.Parent.Rules.ShotJudge)
local NiceShot = require(script.Parent.Parent.Rules.NiceShot)

local E = Config.Economy
local NICE_PAY: { [string]: number } = E.NiceShotPay :: any

export type Grant = {
	ball: number,
	pocket: number?, -- the pocket id it dropped in, for the flying cash
	amount: number,
	kind: string, -- "Ball", or the nice shot's kind: "Bank", "Kick", "Combo", "Carom"
	t: number, -- the shot time the ball dropped
}

export type ShotInput = {
	events: { any }, -- the simulation's ordered events (outcome.events)
	drops: { { ball: number, index: number, t: number } }, -- judgement.drops
	pockets: { any }, -- the table geometry's pockets (NiceShot tells cushions from jaws)
	foul: boolean,
	breakShot: boolean,
	groupsBefore: { [number]: string? }, -- team -> "solids"/"stripes" before the shot
	groupsAfter: { [number]: string? }, -- judgement.groups
	team: number, -- the shooter's team (a teammate's too: they share it)
	winner: number?,
	reason: string?, -- "LegalEight" = the 8 won it
	opponent: string, -- "Player", "PC" or "Solo"
	-- false: a teammate's pay for the team's shot (ECONOMY 3.3: every ball the team pots pays
	-- each teammate, nice shots only the shooter). The server calls shotPay once per teammate.
	isShooter: boolean?, -- default true
	soloEarnedToday: number?, -- solo money earned this UTC day before the shot
	pcEarnedToday: number?, -- PC money earned this UTC day before the shot
	-- The short-match cap is reached and the match is still under the one-minute mark
	-- (ECONOMY 3.6): ShortAfterCapPay a ball, no nice-shot bonus.
	shortCapped: boolean?,
	boost: number?, -- VIP + Money Party + Starter + group (Money.boost), default 0
	farmBalls: number?, -- the anti-farm ball-pay multiplier (Money.farmRow().Balls), default 1
	multiplier: number, -- the table's difficulty (Config.Difficulty.MoneyMultiplier)
}

export type ShotPay = {
	grants: { Grant },
	total: number,
	balls: number, -- how many "Ball" grants
	nice: number, -- how many nice-shot grants
	soloEarned: number, -- how much of `total` counts toward the solo daily counter
	pcEarned: number, -- how much of `total` counts toward the PC daily counter
}

-- The end of a real match, for one player (Money.matchBonus).
export type BonusContext = {
	outcome: string, -- "Win", "Loss" or "Draw"
	opponent: string, -- "Player" or "PC"; anything else (solo) has no bonus
	real: boolean, -- the match ran past the one-minute mark
	forfeited: boolean, -- this player surrendered or left
	multiplier: number?, -- the table's difficulty, default 1
	gap: number?, -- Ranks.gapFactor for this player; the win bonus only (default 1)
	boost: number?, -- VIP + Money Party + Starter + group (Money.boost), default 0
	farm: number?, -- the anti-farm bonus multiplier (Money.farmRow().Bonus), default 1
	pcCapped: boolean?, -- the PC daily cap was reached before this bonus
}

-- One row of Config.Economy.SameOpponent (Money.farmRow).
export type FarmRow = {
	UpTo: number?,
	Xp: number,
	Bonus: number,
	Balls: number,
	Drop: boolean,
}

local Money = {}

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- A multiplier or boost: nil is `default`; anything not a finite number >= 0 is 0.
local function factor(value: any, default: number): number
	if value == nil then
		return default
	end
	if not finite(value) or value < 0 then
		return 0
	end
	return value
end

--- Rounds half up to a whole amount. Every payout goes through this.
function Money.round(x: number): number
	return math.floor(x + 0.5)
end

--- The UTC day number a unix time falls in (the daily counters reset when it changes).
function Money.utcDay(unixSeconds: number): number
	return math.floor(unixSeconds / 86400)
end

-- Which money boosts are on for one player (Money.boost).
export type Boosts = {
	vip: boolean?, -- owns VIP (the pass or the welcome offer)
	party: boolean?, -- a Money Party is on in the server
	starter: boolean?, -- inside the Starter Pack's hour of 2x money
	group: boolean?, -- a member of the game's group
	plus: boolean?, -- a Roblox Plus (Premium) subscriber (GUI lane, 2026-10-03)
}

--- The money boost (ECONOMY 3.5): VIP 1.0, Money Party 1.0, the Starter hour 1.0 and the
--- group 0.1 add (and Roblox Plus, PlusBoost), and the pay is then x (1 + boost). VIP during the
--- Starter hour is x3.
function Money.boost(on: Boosts): number
	local flags: any = if type(on) == "table" then on else {}
	return (if flags.vip == true then E.VipBoost else 0)
		+ (if flags.party == true then E.PartyBoost else 0)
		+ (if flags.starter == true then E.StarterBoost else 0)
		+ (if flags.group == true then E.GroupBoost else 0)
		+ (if flags.plus == true then E.PlusBoost or 0 else 0)
end

--- The anti-farm row for the n-th match against the same opponent in one UTC day (ECONOMY
--- 3.6): the first row whose UpTo covers n, else the last (no UpTo). A copy.
function Money.farmRow(matchNumberToday: number): FarmRow
	local n = if finite(matchNumberToday) then matchNumberToday else 1
	local rows: { FarmRow } = E.SameOpponent :: any
	for _, row in rows do
		if row.UpTo == nil or n <= row.UpTo then
			return table.clone(row)
		end
	end
	return table.clone(rows[#rows])
end

-- Whether ball `ball` dropping on this shot counts for the shooter's team.
local function counts(input: ShotInput, ball: number): boolean
	if input.foul or ball == 0 then
		return false
	end
	if ball == 8 then
		return input.reason == "LegalEight" and input.winner == input.team
	end
	local group = Judge.group(ball)
	if group == nil then
		return false
	end
	if input.breakShot then
		return true
	end
	local mine = input.groupsAfter[input.team]
	if mine == nil then
		return false -- still open after the shot: an early 8, never a legal pot
	end
	return input.opponent == "Solo" or input.groupsBefore[input.team] == nil or group == mine
end

--- What one shot pays one player, grant by grant in the order the balls dropped (the order of
--- rules is at the top of this file).
function Money.shotPay(input: ShotInput): ShotPay
	local grants: { Grant } = {}
	local total, balls, nice = 0, 0, 0
	local solo = input.opponent == "Solo"
	local pc = input.opponent == "PC"
	local shooter = input.isShooter ~= false
	local shortCapped = input.shortCapped == true
	local soloToday = factor(input.soloEarnedToday, 0)
	local pcToday = factor(input.pcEarnedToday, 0)
	local scale = factor(input.multiplier, 1)
		* (1 + factor(input.boost, 0))
		* factor(input.farmBalls, 1)
	-- The flat after-cap pay in force right now, or nil (it pays no nice shots).
	local function flat(): number?
		if shortCapped then
			return E.ShortAfterCapPay
		elseif solo and soloToday + total >= E.SoloDailyCap then
			return E.SoloAfterCapPay
		end
		return nil
	end
	local function amount(base: number): number
		local share = if solo
			then E.SoloShare
			elseif pc and pcToday + total >= E.PcDailyCap then E.PcAfterCapShare
			else 1
		return math.max(1, Money.round(base * scale * share))
	end
	for _, drop in input.drops do
		if counts(input, drop.ball) then
			local ev = input.events[drop.index]
			local pocket = if ev and ev.type == "pocket" then ev.other else nil
			local pay = flat() or amount(E.BallPay)
			table.insert(grants, {
				ball = drop.ball,
				pocket = pocket,
				amount = pay,
				kind = "Ball",
				t = drop.t,
			})
			total += pay
			balls += 1
			local kind = if input.breakShot
					or not shooter
					or solo
				then nil
				else NiceShot.kind(input.events, drop.ball, drop.index, input.pockets)
			if kind and flat() == nil then
				local bonus = amount(NICE_PAY[kind])
				table.insert(grants, {
					ball = drop.ball,
					pocket = pocket,
					amount = bonus,
					kind = kind,
					t = drop.t,
				})
				total += bonus
				nice += 1
			end
		end
	end
	return {
		grants = grants,
		total = total,
		balls = balls,
		nice = nice,
		soloEarned = if solo then total else 0,
		pcEarned = if pc then total else 0,
	}
end

--- The end-of-match bonus (ECONOMY 3.1, 3.2, 3.6, 4.4). Win or loss bonus by opponent (people
--- WinBonus/LossBonus, PC PcWinBonus/PcLossBonus), x difficulty x (1 + boost) x anti-farm; the
--- win bonus also x the gap factor clamped to [WinBonusGapFloor, Config.Ranks.Gap.Max]; PC past
--- its daily cap x PcAfterCapShare. Rounded half up, never below $1. The player who forfeited
--- or left gets nothing, nobody is paid for a match that was not real (under the one-minute
--- mark), and a draw or solo pays nothing.
function Money.matchBonus(ctx: BonusContext): number
	local fields: any = if type(ctx) == "table" then ctx else {}
	if fields.forfeited == true or fields.real ~= true then
		return 0
	end
	local pc = fields.opponent == "PC"
	if not pc and fields.opponent ~= "Player" then
		return 0
	end
	local win = fields.outcome == "Win"
	local base = if win
		then (if pc then E.PcWinBonus else E.WinBonus)
		elseif fields.outcome == "Loss" then (if pc then E.PcLossBonus else E.LossBonus)
		else 0
	if base <= 0 then
		return 0
	end
	local gap = if win
		then math.clamp(factor(fields.gap, 1), E.WinBonusGapFloor, Config.Ranks.Gap.Max)
		else 1
	local share = if pc and fields.pcCapped == true then E.PcAfterCapShare else 1
	local amount = base
		* factor(fields.multiplier, 1)
		* (1 + factor(fields.boost, 0))
		* factor(fields.farm, 1)
		* gap
		* share
	return math.max(1, Money.round(amount))
end

--- The win-streak money (ECONOMY 3.1): +StreakBonus on a win that makes the streak StreakFrom
--- or more (Ranks.nextStreak's count after it), against people only. It is a match bonus, so
--- the difficulty, the boosts (3.5) and the anti-farm bonus multiplier apply to it. Call it
--- only for a win that counted (a real match); anything else pays 0.
function Money.streakBonus(
	streakAfter: number,
	opponent: string,
	multiplier: number?,
	boost: number?,
	farm: number?
): number
	if opponent ~= "Player" or not finite(streakAfter) or streakAfter < E.StreakFrom then
		return 0
	end
	local amount = E.StreakBonus * factor(multiplier, 1) * (1 + factor(boost, 0)) * factor(farm, 1)
	return math.max(1, Money.round(amount))
end

return Money
