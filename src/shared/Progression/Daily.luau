--!strict
-- Daily rewards (ECONOMY sections 10 and 18): the login streak, the playtime gifts and the
-- promo codes. Pure: no Instances, no Roblox APIs, no clocks (the caller passes the UTC day or
-- the unix time), no randomness, and every loop walks an array (the streak and playtime lists,
-- Config.LuckyBlocks.Order), never a keyed table, so nothing depends on hash order.
--
-- The server (src/server/Rewards.luau) owns the save and calls these inside ONE save mutation
-- that also grants the reward; the client only shows the states. Who changes what:
--   * claimLogin and setStreakDay never change the Login table they are given: they return a
--     new one, which the caller stores (save.Login = newLogin).
--   * claimPlaytime and redeem mark the claim in the table they are given (save.Daily,
--     save.Codes), so the mark and the reward can never drift apart. Call them on the live
--     save inside the mutation, never on a read-only copy.
--
-- A reward is always { money = n, blocks = { [kind] = count }, spins = n, lucky = n } (0 and
-- empty when there is none); Daily.blockList lists its lucky blocks in
-- Config.LuckyBlocks.Order. `spins` and `lucky` are ability spins and Lucky Spins. The
-- approved economy plan (2026-10-02, section 6; cases retired for blocks 2026-10-04).
local Config = require(script.Parent.Parent.Config)

local D = Config.Daily
local BLOCK_ORDER: { string } = Config.LuckyBlocks.Order

local SECONDS_PER_DAY = 86400

export type Reward = {
	money: number,
	blocks: { [string]: number }, -- lucky blocks by kind
	spins: number, -- ability spins
	lucky: number, -- Lucky Spins
}

-- The save's login loop (SaveSchema v6): the last claimed UTC day (0 none), the loop day that
-- claim was (1..7, 0 none), every day ever claimed (the 28-day track) and the UTC week whose
-- streak freeze was used (Daily.weekOf; 0 none).
export type Login = { LastDay: number, StreakDay: number, Total: number, FreezeWeek: number }

export type LoginState = {
	canClaim: boolean,
	claimedToday: boolean,
	day: number, -- the loop day today's claim is (or was, once claimed): 1..7
	total: number, -- days claimed counting today's claim (the 28-day track)
	week: number, -- the track's week today's claim is in: 1..TrackDays / 7
	reward: Reward, -- what that claim gives: the loop day, the track and VIP's spin
	bonus: boolean, -- the claim includes a 28-day track reward
	track: Reward?, -- that track reward
	frozen: boolean, -- the claim keeps the streak through this week's freeze
	freezeReady: boolean, -- this week's freeze is not used yet
}

export type Gift = {
	index: number,
	minutes: number,
	reward: Reward,
	ready: boolean, -- claimable now: the time is reached and it is not claimed yet
	claimed: boolean,
	progress: number, -- 0..1 of the minutes played today
}

export type BlockCount = { kind: string, count: number }

-- A Config reward row: Money, Blocks, Spins and/or LuckySpins, plus Minutes (playtime),
-- Day (the track) or Expires and Live (codes).
type RewardRow = {
	Money: number?,
	Blocks: { [string]: number }?,
	Spins: number?,
	LuckySpins: number?,
	Minutes: number?,
	Day: number?,
	Expires: number?,
	Live: boolean?,
}

-- Config's rows are table literals of mixed shapes; read them through one row type.
local STREAK: { RewardRow } = D.Streak :: any
local PLAYTIME: { RewardRow } = D.Playtime :: any
local TRACK: { RewardRow } = D.Track :: any
local CODES: { [string]: RewardRow } = D.Codes :: any
local DAYS = #STREAK
local TRACK_DAYS: number = D.TrackDays

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

-- A new reward from a Config row. Only Money, Blocks, Spins and LuckySpins are read, so a
-- reward can never carry anything else.
local function rewardOf(row: RewardRow?): Reward
	local reward: Reward = { money = 0, blocks = {}, spins = 0, lucky = 0 }
	if row == nil then
		return reward
	end
	reward.money = math.max(0, whole(row.Money))
	reward.spins = math.max(0, whole(row.Spins))
	reward.lucky = math.max(0, whole(row.LuckySpins))
	local blocks = row.Blocks
	if blocks ~= nil then
		for _, kind in BLOCK_ORDER do
			local count = whole(blocks[kind])
			if count > 0 then
				reward.blocks[kind] = count
			end
		end
	end
	return reward
end

local function merge(a: Reward, b: Reward): Reward
	local out: Reward = {
		money = a.money + b.money,
		blocks = {},
		spins = a.spins + b.spins,
		lucky = a.lucky + b.lucky,
	}
	for _, kind in BLOCK_ORDER do
		local count = (a.blocks[kind] or 0) + (b.blocks[kind] or 0)
		if count > 0 then
			out.blocks[kind] = count
		end
	end
	return out
end

--- The UTC day number a unix time falls in (the daily rewards reset when it changes).
function Daily.dayOf(unix: number): number
	return math.floor(unix / SECONDS_PER_DAY)
end

--- A reward's lucky blocks as a list in Config.LuckyBlocks.Order, for showing them.
function Daily.blockList(reward: Reward): { BlockCount }
	local list: { BlockCount } = {}
	for _, kind in BLOCK_ORDER do
		local count = reward.blocks[kind]
		if count ~= nil and count > 0 then
			table.insert(list, { kind = kind, count = count })
		end
	end
	return list
end

---------------------------------------------------------------------------------------------
-- The login loop, its weekly freeze and the 28-day track (plan section 6)
---------------------------------------------------------------------------------------------

--- The UTC week a UTC day falls in, weeks starting on Monday (day 0, 1970-01-01, a Thursday).
function Daily.weekOf(day: number): number
	return (whole(day) + 3) // 7
end

-- The save's loop, cleaned: (last claimed day, loop day 0..DAYS, total days, freeze week).
-- A loop day out of range means nothing claimed.
local function readLogin(login: any): (number, number, number, number)
	if type(login) ~= "table" then
		return 0, 0, 0, 0
	end
	local last = whole(login.LastDay)
	local day = whole(login.StreakDay)
	local total = math.max(0, whole(login.Total))
	local freeze = math.max(0, whole(login.FreezeWeek))
	if day < 1 or day > DAYS then
		day = 0
	end
	return last, day, total, freeze
end

-- The loop day after `day` (day 7 starts the loop over).
local function following(day: number): number
	return if day >= 1 and day < DAYS then day + 1 else 1
end

-- The track's place (1..TrackDays) and week (1..) of the `total`-th day claimed.
local function trackPlace(total: number): (number, number)
	local place = (math.max(1, total) - 1) % TRACK_DAYS + 1
	return place, (place - 1) // 7 + 1
end

--- The 28-day track's reward on the `total`-th day claimed, or nil (most days).
function Daily.trackReward(total: number): Reward?
	local place = trackPlace(total)
	for _, row in TRACK do
		if whole(row.Day) == place then
			return rewardOf(row)
		end
	end
	return nil
end

--- What loop day `day` gives (the seven tiles show these), with VIP's daily ability spin
--- (Config.Daily.VipSpins) when `vip`. The second answer is always false (the old week bonus
--- is the track now: Daily.trackReward).
function Daily.streakReward(day: number, vip: boolean?): (Reward, boolean)
	local reward = rewardOf(STREAK[day])
	if vip == true then
		reward.spins += math.max(0, whole(D.VipSpins))
	end
	return reward, false
end

-- Today's claim from the cleaned save: (loop day, claimed already, frozen).
local function todaysDay(login: any, now: number): (number, boolean, boolean)
	local last, streakDay, _, freeze = readLogin(login)
	if streakDay > 0 and last >= now and last <= now + 1 then
		-- Claimed today. A LastDay of tomorrow means another server's clock was a moment ahead
		-- at midnight; it counts as today, so clock skew never gives a second claim.
		return streakDay, true, false
	elseif streakDay > 0 and last == now - 1 then
		return following(streakDay), false, false
	elseif
		streakDay > 0
		and last == now - 2
		and whole(D.FreezePerWeek) > 0
		and freeze ~= Daily.weekOf(now)
	then
		-- One missed day, covered by this week's freeze.
		return following(streakDay), false, true
	end
	-- Never claimed, two or more missed days, or a LastDay far in the future (a broken save).
	return 1, false, false
end

--- Where a player's loop stands on UTC day `today` (`vip`: today's claim adds VIP's spin).
--- One claim per day; a claim the day after the last one continues the loop, so does one
--- two days after it while this week's freeze is unused; anything later starts at day 1.
function Daily.loginState(login: Login, today: number, vip: boolean?): LoginState
	local now = whole(today)
	local _, _, total, freeze = readLogin(login)
	local day, claimedToday, frozen = todaysDay(login, now)
	local count = if claimedToday then math.max(1, total) else total + 1
	local _, week = trackPlace(count)
	local reward = Daily.streakReward(day, vip)
	local track = Daily.trackReward(count)
	if track ~= nil then
		reward = merge(reward, track)
	end
	return {
		canClaim = not claimedToday,
		claimedToday = claimedToday,
		day = day,
		total = count,
		week = week,
		reward = reward,
		bonus = track ~= nil,
		track = track,
		frozen = frozen,
		freezeReady = whole(D.FreezePerWeek) > 0 and freeze ~= Daily.weekOf(now),
	}
end

--- Claims today's loop reward. Returns (true, the new Login to store, the reward) or
--- (false, an unchanged copy of the Login, nil) when today is already claimed. Never changes
--- the table it is given.
function Daily.claimLogin(login: Login, today: number, vip: boolean?): (boolean, Login, Reward?)
	local now = whole(today)
	local last, streakDay, total, freeze = readLogin(login)
	local state = Daily.loginState(login, now, vip)
	if not state.canClaim then
		return false,
			{ LastDay = last, StreakDay = streakDay, Total = total, FreezeWeek = freeze },
			nil
	end
	return true,
		{
			LastDay = now,
			StreakDay = state.day,
			Total = state.total,
			FreezeWeek = if state.frozen then Daily.weekOf(now) else freeze,
		},
		state.reward
end

--- The /setday dev command: a new Login whose NEXT claim (today) is loop day `n` (1..7) and,
--- when `week` is given (1..TrackDays / 7), the track's day (week - 1) * 7 + n. Works even
--- when today is already claimed, so the tester can claim day n straight away.
function Daily.setStreakDay(login: Login, today: number, n: number, week: number?): Login
	local now = whole(today)
	local day = math.clamp(whole(n), 1, DAYS)
	local _, _, _, freeze = readLogin(login)
	local count = if week ~= nil
		then (math.clamp(whole(week), 1, TRACK_DAYS // 7) - 1) * 7 + day
		else Daily.loginState(login, now).total
	-- Store the claim just before the one wanted, dated yesterday.
	if day > 1 then
		return { LastDay = now - 1, StreakDay = day - 1, Total = count - 1, FreezeWeek = freeze }
	end
	return { LastDay = 0, StreakDay = 0, Total = math.max(0, count - 1), FreezeWeek = freeze }
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
		local reward = rewardOf(row)
		table.insert(list, {
			index = index,
			minutes = minutes,
			reward = reward,
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

--- Whether `code` (normalized) is a Live code: off until switched on (Config.Daily.Codes).
function Daily.isLive(code: string): boolean
	local row = CODES[code]
	return row ~= nil and row.Live == true
end

--- The Live codes switched on, read from a stored value: { [CODE] = true } for Live codes in
--- Config only (anything else is dropped). A fresh table.
function Daily.readLive(stored: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(stored) == "table" then
		for code, on in stored do
			if type(code) == "string" and on == true and Daily.isLive(code) then
				out[code] = true
			end
		end
	end
	return out
end

--- The live-codes transform: the stored set with `code` switched on or off (a fresh table),
--- or nil when `code` is not a Live code (nothing to write).
function Daily.setLive(stored: any, code: string, on: boolean): { [string]: boolean }?
	if not Daily.isLive(code) then
		return nil
	end
	local out = Daily.readLive(stored)
	if on then
		out[code] = true
	else
		out[code] = nil
	end
	return out
end

--- Redeems typed text as a code at unix time `now` and marks it in `codesSave` (the save's
--- own Codes table). `liveOn`: the Live codes switched on ({ [CODE] = true }; a Live code
--- not in it answers "Unknown", so it cannot be found early). Returns (true, reward) or
--- (false, reason): "Bad" (not a possible code), "Unknown" (no such code), "Used" (this
--- player already redeemed it), "Expired" (now is at or after its Expires). Only codes in
--- Config are ever written to the save.
function Daily.redeem(
	codesSave: { [string]: boolean },
	text: any,
	now: number,
	liveOn: { [string]: boolean }?
): (boolean, Reward | string)
	local code = Daily.normalizeCode(text)
	if code == nil then
		return false, "Bad"
	end
	local row = CODES[code]
	if row == nil or (row.Live == true and not (liveOn ~= nil and liveOn[code] == true)) then
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
