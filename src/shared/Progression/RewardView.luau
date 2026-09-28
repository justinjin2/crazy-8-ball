--!strict
-- RewardView: what one player's Rewards menu shows right now, as plain data (the RewardState
-- payload, src/shared/Net.luau), and rewards as a remote carries them (ECONOMY sections 10 and
-- 18). Pure: no Instances, no Roblox APIs, no clocks (the caller passes the unix time), no
-- randomness, and every loop walks an array, so nothing depends on hash order.
--
-- src/server/Rewards.luau reads the save (its Login and Titles, and today's Daily from
-- PlayerData.dailyState), sends RewardView.build's payload, and answers each claim with
-- RewardView.reward.
local Config = require(script.Parent.Parent.Config)
local Daily = require(script.Parent.Daily)

local D = Config.Daily
local DAYS = #D.Streak
local SECONDS_PER_DAY = 86400

-- A reward as remotes carry it: money, and the cases as a list in Config.Cases.Order.
export type RewardOut = { money: number, cases: { Daily.CaseCount } }

export type LoginView = {
	canClaim: boolean,
	claimedToday: boolean,
	day: number, -- the streak day today's claim is (or was): 1..7
	week: number, -- its week of the cycle: 1..weeks
	bonus: boolean, -- today's claim includes the week bonus (day 28)
	reward: RewardOut,
}

-- One of the seven day tiles of the current week.
export type DayView = {
	day: number,
	reward: RewardOut,
	bonus: boolean, -- the week bonus is in this tile (day 7 of the last week)
	claimed: boolean, -- claimed in this streak (a check mark)
	today: boolean, -- today's tile (it glows with Claim while canClaim)
}

export type NextView = {
	day: number,
	week: number,
	reward: RewardOut,
	bonus: boolean,
	tomorrow: boolean, -- false: today's claim is still waiting; true: it comes tomorrow
}

export type GiftView = {
	index: number,
	minutes: number,
	reward: RewardOut,
	ready: boolean,
	claimed: boolean,
	progress: number, -- 0..1 of the minutes played today
}

export type Payload = {
	today: number,
	resetsAt: number,
	sentAt: number,
	weeks: number,
	login: LoginView,
	days: { DayView },
	next: NextView,
	playtime: { GiftView },
	playSeconds: number,
	titles: { string },
	ready: boolean,
}

local RewardView = {}

-- A finite number, else 0.
local function num(x: any): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return 0
	end
	return x
end

--- A Daily.Reward as a remote carries it: { money, cases = { { id, count } } } with the cases
--- in Config.Cases.Order (a list, so the client shows and flies them in a fixed order).
function RewardView.reward(reward: Daily.Reward): RewardOut
	return { money = math.max(0, math.floor(num(reward.money))), cases = Daily.caseList(reward) }
end

--- The save's Titles ({ [titleId] = true }) as a sorted list.
function RewardView.titles(titles: any): { string }
	local list: { string } = {}
	if type(titles) == "table" then
		for id, on in titles do
			if type(id) == "string" and on == true then
				table.insert(list, id)
			end
		end
	end
	table.sort(list)
	return list
end

--- Which playtime gifts are ready now, as a short key ("100": the first only), so the server
--- re-sends the state when a gift becomes ready and not on every playtime tick.
function RewardView.readyKey(daily: any): string
	local parts = {}
	for _, gift in Daily.playtimeState(daily) do
		table.insert(parts, if gift.ready then "1" else "0")
	end
	return table.concat(parts)
end

--- The RewardState payload for one player at unix time `now` (its shape is written in
--- Net.luau, RewardState). `login` is the save's Login, `daily` today's Daily (a fresh one on
--- a new day: PlayerData.dailyState), `titles` the save's Titles.
function RewardView.build(login: any, daily: any, titles: any, now: number): Payload
	local today = Daily.dayOf(num(now))
	local state = Daily.loginState(login, today)
	local nextReward = Daily.nextReward(login, today)

	local days: { DayView } = {}
	for day = 1, DAYS do
		local reward, bonus = Daily.streakReward(day, state.week)
		table.insert(days, {
			day = day,
			reward = RewardView.reward(reward),
			bonus = bonus,
			claimed = day < state.day or (day == state.day and state.claimedToday),
			today = day == state.day,
		})
	end

	local playtime: { GiftView } = {}
	local anyReady = state.canClaim
	for _, gift in Daily.playtimeState(daily) do
		anyReady = anyReady or gift.ready
		table.insert(playtime, {
			index = gift.index,
			minutes = gift.minutes,
			reward = RewardView.reward(gift.reward),
			ready = gift.ready,
			claimed = gift.claimed,
			progress = gift.progress,
		})
	end

	local seconds = if type(daily) == "table" then num(daily.PlaySeconds) else 0
	return {
		today = today,
		resetsAt = (today + 1) * SECONDS_PER_DAY,
		sentAt = math.floor(num(now)),
		weeks = D.WeeksForBonus,
		login = {
			canClaim = state.canClaim,
			claimedToday = state.claimedToday,
			day = state.day,
			week = state.week,
			bonus = state.bonus,
			reward = RewardView.reward(state.reward),
		},
		days = days,
		next = {
			day = nextReward.day,
			week = nextReward.week,
			reward = RewardView.reward(nextReward.reward),
			bonus = nextReward.bonus,
			tomorrow = nextReward.tomorrow,
		},
		playtime = playtime,
		playSeconds = math.max(0, math.floor(seconds)),
		titles = RewardView.titles(titles),
		ready = anyReady,
	}
end

return RewardView
