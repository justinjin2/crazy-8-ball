--!strict
-- Daily rewards (ECONOMY sections 10 and 18): the login streak, the playtime gifts and the
-- promo codes. Pure: no Instances, no Roblox APIs, no clocks (the caller passes the UTC day or
-- the unix time), no randomness, and every loop walks an array (the streak and playtime lists,
-- Config.Cases.Order), never a keyed table, so nothing depends on hash order.
--
-- The server (src/server/Rewards.luau) owns the save and calls these inside ONE save mutation
-- that also grants the reward; the client only shows the states. Who changes what:
--   * claimLogin and setStreakDay never change the Login table they are given: they return a
--     new one, which the caller stores (save.Login = newLogin).
--   * claimPlaytime and redeem mark the claim in the table they are given (save.Daily,
--     save.Codes), so the mark and the reward can never drift apart. Call them on the live
--     save inside the mutation, never on a read-only copy.
--
-- A reward is always { money = n, cases = { [caseId] = count } } (money 0 and cases empty when
-- there is none); Daily.caseList lists its cases in Config.Cases.Order.
local Config = require(script.Parent.Parent.Config)

local D = Config.Daily
local CASE_ORDER: { string } = Config.Cases.Order

local SECONDS_PER_DAY = 86400

export type Reward = { money: number, cases: { [string]: number } }

-- The save's login streak (SaveSchema v2): the last claimed UTC day (0 none), the streak day
-- that claim was (1..7, 0 none) and its week of the cycle (1..WeeksForBonus, 0 none).
export type Login = { LastDay: number, StreakDay: number, Week: number }

export type LoginState = {
	canClaim: boolean,
	claimedToday: boolean,
	day: number, -- the streak day today's claim is (or was, once claimed): 1..7
	week: number, -- its week of the cycle: 1..WeeksForBonus
	reward: Reward, -- what that claim gives, the week bonus included
	bonus: boolean, -- the claim includes Config.Daily.WeekBonus (day 7 of the last week)
}

export type NextReward = {
	day: number,
	week: number,
	reward: Reward,
	bonus: boolean,
	tomorrow: boolean, -- false: today's claim is still waiting; true: it comes tomorrow
}

export type Gift = {
	index: number,
	minutes: number,
	reward: Reward,
	ready: boolean, -- claimable now: the time is reached and it is not claimed yet
	claimed: boolean,
	progress: number, -- 0..1 of the minutes played today
}

export type CaseCount = { id: string, count: number }

-- A Config reward row: Money and/or Cases, plus Minutes (playtime) or Expires (codes).
type RewardRow = {
	Money: number?,
	Cases: { [string]: number }?,
	Minutes: number?,
	Expires: number?,
}

-- Config's rows are table literals of mixed shapes; read them through one row type.
local STREAK: { RewardRow } = D.Streak :: any
local PLAYTIME: { RewardRow } = D.Playtime :: any
local WEEK_BONUS: RewardRow = D.WeekBonus :: any
local CODES: { [string]: RewardRow } = D.Codes :: any
local DAYS = #STREAK
local WEEKS: number = D.WeeksForBonus

-- The longest text normalizeCode looks at. The text comes from a client, and trimming is a
-- pattern match that gets slow on very long runs of spaces, so anything far longer than a code
-- is refused before any pattern runs.
local RAW_CODE_MAX = D.CodeMaxLength * 4

local Daily = {}

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------

-- A finite number, else 0 (a bad save or a bad caller never crashes anything here).
local function num(x: any): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return 0
	end
	return x
end

local function whole(x: any): number
	return math.floor(num(x))
end

-- A new reward from a Config row. Only Money and Cases are read, so a reward can never carry
-- anything else (codes must never give what is sold for Robux, ECONOMY 18).
local function rewardOf(row: RewardRow?): Reward
	local reward: Reward = { money = 0, cases = {} }
	if row == nil then
		return reward
	end
	reward.money = math.max(0, whole(row.Money))
	local cases = row.Cases
	if cases ~= nil then
		for _, caseId in CASE_ORDER do
			local count = whole(cases[caseId])
			if count > 0 then
				reward.cases[caseId] = count
			end
		end
	end
	return reward
end

local function merge(a: Reward, b: Reward): Reward
	local out: Reward = { money = a.money + b.money, cases = {} }
	for _, caseId in CASE_ORDER do
		local count = (a.cases[caseId] or 0) + (b.cases[caseId] or 0)
		if count > 0 then
			out.cases[caseId] = count
		end
	end
	return out
end

--- The UTC day number a unix time falls in (the daily rewards reset when it changes).
function Daily.dayOf(unix: number): number
	return math.floor(unix / SECONDS_PER_DAY)
end

--- A reward's cases as a list in Config.Cases.Order, for showing them.
function Daily.caseList(reward: Reward): { CaseCount }
	local list: { CaseCount } = {}
	for _, caseId in CASE_ORDER do
		local count = reward.cases[caseId]
		if count ~= nil and count > 0 then
			table.insert(list, { id = caseId, count = count })
		end
	end
	return list
end

---------------------------------------------------------------------------------------------
-- The login streak (ECONOMY 10)
---------------------------------------------------------------------------------------------

-- The save's streak, cleaned: (last claimed day, streak day 0..DAYS, week 0..WEEKS). A streak
-- day out of range means nothing claimed; a claimed day with a bad week sits in week 1.
local function readLogin(login: any): (number, number, number)
	if type(login) ~= "table" then
		return 0, 0, 0
	end
	local last = whole(login.LastDay)
	local day = whole(login.StreakDay)
	local week = whole(login.Week)
	if day < 1 or day > DAYS then
		return last, 0, 0
	end
	if week < 1 or week > WEEKS then
		week = 1
	end
	return last, day, week
end

-- The claim that follows (day, week) on the next UTC day. After the cycle's last day (day 7 of
-- week WEEKS, the one with the bonus) the cycle starts over at week 1.
local function following(day: number, week: number): (number, number)
	if day >= 1 and day < DAYS then
		return day + 1, week
	end
	if day == DAYS and week < WEEKS then
		return 1, week + 1
	end
	return 1, 1
end

--- What streak day `day` of week `week` gives (the seven tiles show these), and whether it
--- includes the week bonus: WeekBonus is added on the last day of the last week (day 28).
function Daily.streakReward(day: number, week: number): (Reward, boolean)
	local bonus = day == DAYS and week == WEEKS
	local reward = rewardOf(STREAK[day])
	if bonus then
		reward = merge(reward, rewardOf(WEEK_BONUS))
	end
	return reward, bonus
end

--- Where a player's streak stands on UTC day `today`. One claim per day; a claim the day after
--- the last one continues the streak, anything later starts again at day 1 of week 1.
function Daily.loginState(login: Login, today: number): LoginState
	local now = whole(today)
	local last, streakDay, week = readLogin(login)
	local day, claimedToday
	if streakDay > 0 and last >= now and last <= now + 1 then
		-- Claimed today. A LastDay of tomorrow means another server's clock was a moment ahead
		-- at midnight; it counts as today, so clock skew never gives a second claim.
		day, claimedToday = streakDay, true
	elseif streakDay > 0 and last == now - 1 then
		day, week = following(streakDay, week)
		claimedToday = false
	else
		-- Never claimed, a missed day, or a LastDay far in the future (a broken save).
		day, week, claimedToday = 1, 1, false
	end
	local reward, bonus = Daily.streakReward(day, week)
	return {
		canClaim = not claimedToday,
		claimedToday = claimedToday,
		day = day,
		week = week,
		reward = reward,
		bonus = bonus,
	}
end

--- Claims today's streak reward. Returns (true, the new Login to store, the reward) or
--- (false, an unchanged copy of the Login, nil) when today is already claimed. Never changes
--- the table it is given.
function Daily.claimLogin(login: Login, today: number): (boolean, Login, Reward?)
	local state = Daily.loginState(login, today)
	if not state.canClaim then
		local last, streakDay, week = readLogin(login)
		return false, { LastDay = last, StreakDay = streakDay, Week = week }, nil
	end
	return true, { LastDay = whole(today), StreakDay = state.day, Week = state.week }, state.reward
end

--- The /setday dev command: a new Login whose NEXT claim (today) is day `n` (1..7) of week
--- `week` (1..WeeksForBonus; default: the week today's claim is in now). Works even when
--- today is already claimed, so the tester can claim day n straight away.
function Daily.setStreakDay(login: Login, today: number, n: number, week: number?): Login
	local now = whole(today)
	local day = math.clamp(whole(n), 1, DAYS)
	local w = if week ~= nil
		then math.clamp(whole(week), 1, WEEKS)
		else Daily.loginState(login, now).week
	-- Store the claim just before the one wanted, dated yesterday.
	if day > 1 then
		return { LastDay = now - 1, StreakDay = day - 1, Week = w }
	end
	if w > 1 then
		return { LastDay = now - 1, StreakDay = DAYS, Week = w - 1 }
	end
	return { LastDay = 0, StreakDay = 0, Week = 0 }
end

--- What the next claim gives: today's while it is unclaimed, else tomorrow's (if the player
--- comes back tomorrow). The reminder "Come back tomorrow for your Rare Case" reads this.
function Daily.nextReward(login: Login, today: number): NextReward
	local state = Daily.loginState(login, today)
	if state.canClaim then
		return {
			day = state.day,
			week = state.week,
			reward = state.reward,
			bonus = state.bonus,
			tomorrow = false,
		}
	end
	local day, week = following(state.day, state.week)
	local reward, bonus = Daily.streakReward(day, week)
	return { day = day, week = week, reward = reward, bonus = bonus, tomorrow = true }
end

---------------------------------------------------------------------------------------------
-- Playtime gifts (ECONOMY 10): minutes played in the UTC day, each gift once a day
---------------------------------------------------------------------------------------------

-- The save's claimed-gift map, keyed "1", "2", "3" (string keys: a save may not hold a
-- sparse array).
local function claimedMap(daily: any): { [string]: boolean }
	if type(daily) == "table" and type(daily.PlaytimeClaimed) == "table" then
		return daily.PlaytimeClaimed
	end
	return {}
end

--- Every playtime gift in Config order with its progress, from the day's save
--- (Daily.PlaySeconds and Daily.PlaytimeClaimed).
function Daily.playtimeState(daily: any): { Gift }
	local seconds = math.max(0, num(if type(daily) == "table" then daily.PlaySeconds else 0))
	local claimed = claimedMap(daily)
	local list: { Gift } = {}
	for index, row in PLAYTIME do
		local minutes = math.max(0, whole(row.Minutes))
		local need = minutes * 60
		local done = claimed[tostring(index)] == true
		table.insert(list, {
			index = index,
			minutes = minutes,
			reward = rewardOf(row),
			ready = seconds >= need and not done,
			claimed = done,
			progress = if need <= 0 then 1 else math.min(1, seconds / need),
		})
	end
	return list
end

--- Claims playtime gift `index` (1..#Config.Daily.Playtime) and marks it in `daily` (the
--- save's own Daily table). Returns (true, reward) or (false, reason): "Unknown" (no such
--- gift), "Claimed" (already today), "NotReady" (not enough minutes yet).
function Daily.claimPlaytime(daily: any, index: any): (boolean, Reward | string)
	if type(index) ~= "number" or index ~= math.floor(index) or PLAYTIME[index] == nil then
		return false, "Unknown"
	end
	local gift = Daily.playtimeState(daily)[index]
	if gift.claimed then
		return false, "Claimed"
	end
	if not gift.ready or type(daily) ~= "table" then
		return false, "NotReady"
	end
	if type(daily.PlaytimeClaimed) ~= "table" then
		daily.PlaytimeClaimed = {}
	end
	daily.PlaytimeClaimed[tostring(index)] = true
	return true, gift.reward
end

---------------------------------------------------------------------------------------------
-- Promo codes (ECONOMY 18): case-insensitive, once per player, optional expiry
---------------------------------------------------------------------------------------------

--- Typed text as a code: trimmed, upper-case, letters and digits only, 1..CodeMaxLength long.
--- nil for anything else (spaces inside, symbols, empty, too long, not a string).
function Daily.normalizeCode(text: any): string?
	if type(text) ~= "string" or #text > RAW_CODE_MAX then
		return nil
	end
	local code = string.upper(string.match(text, "^%s*(.-)%s*$") or "")
	if #code == 0 or #code > D.CodeMaxLength or string.find(code, "^[A-Z0-9]+$") == nil then
		return nil
	end
	return code
end

--- Redeems typed text as a code at unix time `now` and marks it in `codesSave` (the save's
--- own Codes table). Returns (true, reward) or (false, reason): "Bad" (not a possible code),
--- "Unknown" (no such code), "Used" (this player already redeemed it), "Expired" (now is at
--- or after its Expires). Only codes in Config are ever written to the save.
function Daily.redeem(
	codesSave: { [string]: boolean },
	text: any,
	now: number
): (boolean, Reward | string)
	local code = Daily.normalizeCode(text)
	if code == nil then
		return false, "Bad"
	end
	local row = CODES[code]
	if row == nil then
		return false, "Unknown"
	end
	if codesSave[code] == true then
		return false, "Used"
	end
	if row.Expires ~= nil and num(now) >= row.Expires then
		return false, "Expired"
	end
	codesSave[code] = true
	return true, rewardOf(row)
end

return Daily
