--!strict
-- What a shot and a match pay, in money (GDD section 12; designer, 2026-09-27). Pure: no
-- Instances, no Roblox APIs, no clocks, no randomness, and nothing that depends on the order
-- a hash table happens to iterate in. The server pays from these (src/server/Economy.luau)
-- off its own authoritative shot; the client only animates what the server sends.
--
-- Which balls count for the shooter: nothing at all on a foul shot. Otherwise every object
-- ball on the break; every object ball on the legal pot that picks the colors (the table was
-- open for the shooter and the shot leaves them a group); after that only the shooter's
-- group; the 8 only when it wins the game for the shooter. Solo plays both groups, so every
-- object ball counts there. A shot that sinks the 8 early on an open table leaves no group
-- and so pays nothing, as the match's bonus stings (Rules/MatchEngine `Engine.awards`).
-- Each counting ball also pays a nice-shot bonus (Rules/NiceShot), except on the break
-- (the client never shows NICE SHOT! there either).
local Config = require(script.Parent.Parent.Config)
local Judge = require(script.Parent.Parent.Rules.ShotJudge)
local NiceShot = require(script.Parent.Parent.Rules.NiceShot)

local E = Config.Economy

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
	team: number, -- the shooter's team
	winner: number?,
	reason: string?, -- "LegalEight" = the 8 won it
	solo: boolean,
	soloEarnedToday: number, -- money earned in solo this UTC day before the shot
	multiplier: number, -- Config.Difficulty.MoneyMultiplier for the table
}

export type ShotPay = {
	grants: { Grant },
	total: number,
	balls: number, -- how many "Ball" grants
	nice: number, -- how many nice-shot grants
	soloEarned: number, -- how much of `total` counts toward the solo daily counter
}

local Money = {}

--- Rounds half up to a whole amount. Every payout goes through this.
function Money.round(x: number): number
	return math.floor(x + 0.5)
end

--- The UTC day number a unix time falls in (the solo daily counter resets when it changes).
function Money.utcDay(unixSeconds: number): number
	return math.floor(unixSeconds / 86400)
end

-- Whether ball `ball` dropping on this shot counts for the shooter.
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
	return input.solo or input.groupsBefore[input.team] == nil or group == mine
end

--- What one shot pays its shooter, grant by grant in the order the balls dropped.
function Money.shotPay(input: ShotInput): ShotPay
	local grants: { Grant } = {}
	local total, balls, nice = 0, 0, 0
	local multiplier = input.multiplier
	-- Solo: the share of normal pay while under the daily cap, then the flat after-cap pay.
	local function amount(base: number): number
		if input.solo then
			return math.max(1, Money.round(base * multiplier * E.SoloShare))
		end
		return math.max(1, Money.round(base * multiplier))
	end
	local function capped(): boolean
		return input.solo and input.soloEarnedToday + total >= E.SoloDailyCap
	end
	for _, drop in input.drops do
		if counts(input, drop.ball) then
			local ev = input.events[drop.index]
			local pocket = if ev and ev.type == "pocket" then ev.other else nil
			local pay = if capped() then E.SoloAfterCapPay else amount(E.BallPay)
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
				then nil
				else NiceShot.kind(input.events, drop.ball, drop.index, input.pockets)
			if kind and not capped() then
				local bonus = amount(E.NiceShotPay[kind])
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
		soloEarned = if input.solo then total else 0,
	}
end

--- The end-of-match bonus. `outcome` is "Win", "Loss" or "Draw"; `opponent` "Player" or
--- "PC". The player who forfeited or left gets nothing, and nobody is paid for a match that
--- was not real (ended under the one-minute mark).
function Money.matchBonus(
	outcome: string,
	opponent: string,
	real: boolean,
	forfeited: boolean,
	multiplier: number
): number
	if forfeited or not real then
		return 0
	end
	local base = if outcome == "Win" then E.WinBonus elseif outcome == "Loss" then E.LossBonus else 0
	if opponent == "PC" then
		base *= E.PcShare
	end
	return Money.round(base * multiplier)
end

return Money
