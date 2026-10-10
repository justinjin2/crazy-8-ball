--!strict
-- Daily rewards (ECONOMY sections 10 and 18): the login days (the first week, then the later
-- weeks' streak), the playtime gifts and the promo codes. Pure: no Instances, no Roblox APIs,
-- no clocks (the caller passes the day or the unix time), no randomness, and every loop walks
-- an array (the day, track and playtime lists, Config.LuckyBlocks.Order), never a keyed table,
-- so nothing depends on hash order. A "day" starts at Config.Daily.ResetHour UTC (economy v4,
-- 2026-10-08: 08:00 UTC; Daily.dayOf).
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
-- empty when there is none), plus `cues` (cue ids, in the row's order; economy v5: the first
-- week's day 7 gives the Week One Cue); Daily.blockList lists its lucky blocks in
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
	cues: { string }?, -- cue ids, one copy each (economy v5); nil or empty: none
}

-- The save's login days: the last claimed day (0 none), the later weeks' loop day that claim
-- was (1..7; 0 none, or a first-week claim), every day ever claimed (the 28-day track), the
-- week whose streak freeze was used (Daily.weekOf; 0 none) and the first-week days claimed
-- (0..#Config.Daily.FirstWeek; economy v4).
export type Login = {
	LastDay: number,
	StreakDay: number,
	Total: number,
	FreezeWeek: number,
	FirstWeek: number?,
}

-- What the login rules need besides the save (economy v4): the day of the first join (nil:
-- no first week), whether a match was finished today (Config.Daily.NeedsMatch; nil counts as
-- yes) and, for a VIP, whether paid random items are restricted for them (no daily block or
-- spin; Config.Daily.VipRestrictedMoney instead).
export type LoginExtra = { joinDay: number?, played: boolean?, restricted: boolean? }

export type LoginState = {
	canClaim: boolean,
	claimedToday: boolean,
	-- The day today's claim is (or was, once claimed): first week 1..#FirstWeek, else the
	-- later weeks' loop day 1..7.
	day: number,
	firstWeek: boolean, -- today's claim is a first-week day
	firstWeekDays: number, -- first-week days claimed, counting today's claim once made
	firstWeekLeft: number, -- days left in the first week's window, today included (0: over)
	needsMatch: boolean, -- not claimed, and no match finished today yet (the claim waits)
	total: number, -- days claimed counting today's claim (the 28-day track)
	week: number, -- the track's week today's claim is in: 1..TrackDays / 7
	reward: Reward, -- what that claim gives: the day, the track and VIP's spin and block
	bonus: boolean, -- the claim includes a 28-day track reward
	track: Reward?, -- that track reward
	frozen: boolean, -- the claim keeps the streak through this week's freeze
	freezeReady: boolean, -- this week's freeze is not used yet
}

-- Claim All's offer on one day (Daily.claimAllOffer): the rest of this 7-day row at once.
export type ClaimAllOffer = {
	available: boolean, -- some day of this row is still ahead (today's unclaimed one counts)
	firstWeek: boolean, -- the row is the first week (else a later week's loop)
	from: number, -- the first day it claims: today's when not claimed yet, else tomorrow's
	days: number, -- how many days it claims (0: none left)
	product: string?, -- the Config.Products key it is bought with (Config.Daily.ClaimAll)
	reward: Reward, -- everything it gives (today's track prize and VIP's part included)
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

-- A Config reward row: Money, Blocks, Cues, Spins and/or LuckySpins, plus Minutes (playtime),
-- Day (the track) or Expires and Live (codes).
type RewardRow = {
	Money: number?,
	Blocks: { [string]: number }?,
	Cues: { string }?,
	Spins: number?,
	LuckySpins: number?,
	Minutes: number?,
	Day: number?,
	Expires: number?,
	Live: boolean?,
}

-- Config's rows are table literals of mixed shapes; read them through one row type.
local STREAK: { RewardRow } = D.Streak :: any
local FIRST: { RewardRow } = D.FirstWeek :: any
local FIRST_DAYS = #FIRST
local FIRST_WINDOW: number = D.FirstWeekWindow
local VIP_BLOCKS: { [string]: number } = D.VipBlocks :: any
local DAY_OFFSET: number = D.ResetHour * 3600
local PLAYTIME: { RewardRow } = D.Playtime :: any
local TRACK: { RewardRow } = D.Track :: any
local CODES: { [string]: RewardRow } = D.Codes :: any
local DAYS = #STREAK
local TRACK_DAYS: number = D.TrackDays
type ClaimAllStep = { MinDays: number, Product: string }
local CLAIM_ALL: { First: { ClaimAllStep }, Week: { ClaimAllStep } } = D.ClaimAll :: any

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

-- A new reward from a Config row. Only Money, Blocks, Cues, Spins and LuckySpins are read, so
-- a reward can never carry anything else.
local function rewardOf(row: RewardRow?): Reward
	local reward: Reward = { money = 0, blocks = {}, spins = 0, lucky = 0, cues = {} }
	if row == nil then
		return reward
	end
	if type(row.Cues) == "table" then
		for _, id in row.Cues :: { any } do
			if type(id) == "string" then
				table.insert(reward.cues :: { string }, id)
			end
		end
	end
	reward.money = math.max(0, whole(row.Money))
	reward.spins = math.max(0, whole(row.Spins))
	reward.lucky = math.max(0, whole(row.LuckySpins))
	if Config.Ults.Earn.LuckySpins == false then
		-- Lucky Spins are retired: a row's LuckySpins pay the same count of plain spins.
		reward.spins, reward.lucky = reward.spins + reward.lucky, 0
	end
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
	local cues: { string } = table.clone(a.cues or {})
	local more: { string } = b.cues or {}
	for _, id in more do
		table.insert(cues, id)
	end
	local out: Reward = {
		money = a.money + b.money,
		blocks = {},
		spins = a.spins + b.spins,
		lucky = a.lucky + b.lucky,
		cues = cues,
	}
	for _, kind in BLOCK_ORDER do
		local count = (a.blocks[kind] or 0) + (b.blocks[kind] or 0)
		if count > 0 then
			out.blocks[kind] = count
		end
	end
	return out
end

--- The day number a unix time falls in: days start at Config.Daily.ResetHour UTC (every
--- daily thing resets when it changes).
function Daily.dayOf(unix: number): number
	return math.floor((unix - DAY_OFFSET) / SECONDS_PER_DAY)
end

--- The day a player first joined (the save's Shop.FirstJoin, a unix time), nil when unknown:
--- the first week's window counts from it.
function Daily.joinDayOf(firstJoin: any): number?
	return if type(firstJoin) == "number" and firstJoin > 0 then Daily.dayOf(firstJoin) else nil
end

--- The unix time day `day` starts (Config.Daily.ResetHour UTC that date).
function Daily.dayStart(day: number): number
	return day * SECONDS_PER_DAY + DAY_OFFSET
end

--- Every cue id a login claim can give (the first week's, the later weeks' and the track's
--- rows), once each in row order: the server counts their copies in existence around a claim.
function Daily.rewardCues(): { string }
	local out: { string } = {}
	for _, rows in { FIRST, STREAK, TRACK } do
		for _, row in rows do
			local cues: { string } = rewardOf(row).cues or {}
			for _, id in cues do
				if table.find(out, id) == nil then
					table.insert(out, id)
				end
			end
		end
	end
	return out
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

-- The save's login days, cleaned: (last claimed day, loop day 0..DAYS, total days, freeze
-- week, first-week days 0..FIRST_DAYS). A loop day out of range means none.
local function readLogin(login: any): (number, number, number, number, number)
	if type(login) ~= "table" then
		return 0, 0, 0, 0, 0
	end
	local last = whole(login.LastDay)
	local day = whole(login.StreakDay)
	local total = math.max(0, whole(login.Total))
	local freeze = math.max(0, whole(login.FreezeWeek))
	local first = math.clamp(whole(login.FirstWeek), 0, FIRST_DAYS)
	if day < 1 or day > DAYS then
		day = 0
	end
	return last, day, total, freeze, first
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

-- VIP's part of every day's claim: the extra spin and the daily block, or where paid random
-- items are restricted for them, Config.Daily.VipRestrictedMoney instead of both (economy v4).
local function addVip(reward: Reward, vip: boolean?, restricted: boolean?): Reward
	if vip ~= true then
		return reward
	end
	if restricted == true then
		reward.money += math.max(0, whole(D.VipRestrictedMoney))
		return reward
	end
	reward.spins += math.max(0, whole(D.VipSpins))
	return merge(reward, rewardOf({ Blocks = VIP_BLOCKS }))
end

--- What the later weeks' loop day `day` gives (the seven tiles show these), with VIP's daily
--- spin and block (Config.Daily.VipSpins, VipBlocks) when `vip` (`restricted`: VIP's money
--- instead). The second answer is always false (the old week bonus is the track now:
--- Daily.trackReward).
function Daily.streakReward(day: number, vip: boolean?, restricted: boolean?): (Reward, boolean)
	return addVip(rewardOf(STREAK[day]), vip, restricted), false
end

--- What first-week day `day` gives (1..#Config.Daily.FirstWeek), with VIP's part like
--- Daily.streakReward.
function Daily.firstWeekReward(day: number, vip: boolean?, restricted: boolean?): Reward
	return addVip(rewardOf(FIRST[day]), vip, restricted)
end

-- Whether day `now` is inside the first week's window for a player who joined on `joinDay`
-- (the join's day is day 1 of FirstWeekWindow), and the days left in it, today included.
local function firstWindow(joinDay: number?, now: number): (boolean, number)
	if joinDay == nil then
		return false, 0
	end
	local left = whole(joinDay) + FIRST_WINDOW - now
	return left >= 1, math.max(0, math.min(left, FIRST_WINDOW))
end

-- Today's claim from the cleaned save: (day, claimed already, frozen, a first-week day).
local function todaysDay(
	login: any,
	now: number,
	joinDay: number?
): (number, boolean, boolean, boolean)
	local last, streakDay, _, freeze, first = readLogin(login)
	local claimed = last >= now and last <= now + 1
	-- A LastDay of tomorrow means another server's clock was a moment ahead at the reset (or
	-- the reset moved later, economy v4); it counts as today, so clock skew never gives a
	-- second claim.
	if claimed and streakDay == 0 and first > 0 then
		return first, true, false, true
	elseif claimed and streakDay > 0 then
		return streakDay, true, false, false
	end
	local inWindow = firstWindow(joinDay, now)
	if inWindow and first < FIRST_DAYS then
		return first + 1, false, false, true
	elseif streakDay > 0 and last == now - 1 then
		return following(streakDay), false, false, false
	elseif
		streakDay > 0
		and last == now - 2
		and whole(D.FreezePerWeek) > 0
		and freeze ~= Daily.weekOf(now)
	then
		-- One missed day, covered by this week's freeze.
		return following(streakDay), false, true, false
	end
	-- Never claimed in the later weeks (the first week's claims leave StreakDay 0), two or more
	-- missed days, or a LastDay far in the future (a broken save).
	return 1, false, false, false
end

--- Where a player's login days stand on day `today` (`vip`: today's claim adds VIP's spin and
--- block; `extra`: the join day, today's match, VIP's restriction). One claim per day, and
--- only once a match was finished that day (Config.Daily.NeedsMatch). The first week: the
--- first #FirstWeek days claimed within FirstWeekWindow days of joining, in a row or not.
--- Then the later weeks: a claim the day after the last one continues the loop, so does one
--- two days after it while this week's freeze is unused; anything later starts at day 1.
function Daily.loginState(
	login: Login,
	today: number,
	vip: boolean?,
	extra: LoginExtra?
): LoginState
	local now = whole(today)
	local joinDay = if extra then extra.joinDay else nil
	local restricted = if extra then extra.restricted else nil
	local played = not (extra and extra.played == false)
	local _, _, total, freeze, first = readLogin(login)
	local day, claimedToday, frozen, isFirst = todaysDay(login, now, joinDay)
	local count = if claimedToday then math.max(1, total) else total + 1
	local _, week = trackPlace(count)
	local reward = if isFirst
		then Daily.firstWeekReward(day, vip, restricted)
		else Daily.streakReward(day, vip, restricted)
	local track = Daily.trackReward(count)
	if track ~= nil then
		reward = merge(reward, track)
	end
	local inWindow, left = firstWindow(joinDay, now)
	local needsMatch = not claimedToday and D.NeedsMatch == true and not played
	return {
		canClaim = not claimedToday and not needsMatch,
		claimedToday = claimedToday,
		day = day,
		firstWeek = isFirst,
		firstWeekDays = if isFirst and claimedToday then day else first,
		firstWeekLeft = if inWindow and (first < FIRST_DAYS or (isFirst and claimedToday))
			then left
			else 0,
		needsMatch = needsMatch,
		total = count,
		week = week,
		reward = reward,
		bonus = track ~= nil,
		track = track,
		frozen = frozen,
		freezeReady = whole(D.FreezePerWeek) > 0 and freeze ~= Daily.weekOf(now),
	}
end

--- Claims today's login reward (`vip` and `extra` as Daily.loginState). Returns (true, the
--- new Login to store, the reward) or (false, an unchanged copy of the Login, nil) when today
--- is already claimed or waits for a match. A first-week claim stores StreakDay 0, so the
--- later weeks start at day 1. Never changes the table it is given.
function Daily.claimLogin(
	login: Login,
	today: number,
	vip: boolean?,
	extra: LoginExtra?
): (boolean, Login, Reward?)
	local now = whole(today)
	local last, streakDay, total, freeze, first = readLogin(login)
	local state = Daily.loginState(login, now, vip, extra)
	if not state.canClaim then
		return false,
			{
				LastDay = last,
				StreakDay = streakDay,
				Total = total,
				FreezeWeek = freeze,
				FirstWeek = first,
			},
			nil
	end
	return true,
		{
			LastDay = now,
			StreakDay = if state.firstWeek then 0 else state.day,
			Total = state.total,
			FreezeWeek = if state.frozen then Daily.weekOf(now) else freeze,
			FirstWeek = if state.firstWeek then state.day else first,
		},
		state.reward
end

-- The rest of this 7-day row on day `now`: (a first-week row, the first day ahead, whether
-- that day is today's unclaimed one).
local function rowAhead(login: any, now: number, joinDay: number?): (boolean, number, boolean)
	local day, claimedToday, _, isFirst = todaysDay(login, now, joinDay)
	if claimedToday then
		return isFirst, day + 1, false
	end
	return isFirst, day, true
end

--- Claim All on day `today` (`vip` and `extra` as Daily.loginState; `maxDays`: the most days
--- to claim, a receipt's product's ClaimAll; nil: all): every day still ahead in this 7-day
--- row, at once. Today's day, when not claimed yet, is claimed whole, as Daily.claimLogin
--- would (its 28-day track prize and VIP's part too, and no wait for a match: the purchase is
--- the player's); the days after it give their own day's reward only, since VIP's daily part
--- and the track count real login days. Returns (the days claimed, 0 for none; the new Login
--- to store; the reward). The row is then done: tomorrow is the later weeks' day 1. Never
--- changes the table it is given.
function Daily.claimAll(
	login: Login,
	today: number,
	vip: boolean?,
	extra: LoginExtra?,
	maxDays: number?
): (number, Login, Reward)
	local now = whole(today)
	local joinDay = if extra then extra.joinDay else nil
	local last, streakDay, total, freeze, first = readLogin(login)
	local out: Login = {
		LastDay = last,
		StreakDay = streakDay,
		Total = total,
		FreezeWeek = freeze,
		FirstWeek = first,
	}
	local isFirst, from, withToday = rowAhead(login, now, joinDay)
	local to = if isFirst then FIRST_DAYS else DAYS
	if maxDays ~= nil then
		to = math.min(to, from + math.max(0, whole(maxDays)) - 1)
	end
	local reward = rewardOf(nil)
	if from > to then
		return 0, out, reward
	end
	for day = from, to do
		if day == from and withToday then
			local played: LoginExtra = {
				joinDay = joinDay,
				played = true,
				restricted = if extra then extra.restricted else nil,
			}
			local state = Daily.loginState(login, now, vip, played)
			reward = merge(reward, state.reward)
			out.LastDay = now
			out.Total = state.total
			out.FreezeWeek = if state.frozen then Daily.weekOf(now) else freeze
		else
			reward = merge(reward, rewardOf(if isFirst then FIRST[day] else STREAK[day]))
		end
	end
	if isFirst then
		out.FirstWeek = to
		out.StreakDay = 0
	else
		out.StreakDay = to
	end
	return to - from + 1, out, reward
end

--- Claim All's offer on day `today` (`vip`, `extra` as Daily.loginState): what the rest of
--- this 7-day row gives at once and the product it is bought with (Config.Daily.ClaimAll: the
--- first step whose MinDays the days ahead reach). Not available once the row's last day is
--- claimed.
function Daily.claimAllOffer(
	login: Login,
	today: number,
	vip: boolean?,
	extra: LoginExtra?
): ClaimAllOffer
	local now = whole(today)
	local joinDay = if extra then extra.joinDay else nil
	local isFirst, from = rowAhead(login, now, joinDay)
	local days, _, reward = Daily.claimAll(login, now, vip, extra)
	local product: string? = nil
	if days > 0 then
		local steps: { ClaimAllStep } = if isFirst then CLAIM_ALL.First else CLAIM_ALL.Week
		for _, step in steps do
			if days >= whole(step.MinDays) then
				product = step.Product
				break
			end
		end
	end
	return {
		available = product ~= nil,
		firstWeek = isFirst,
		from = from,
		days = days,
		product = product,
		reward = reward,
	}
end

--- The /setday dev command: a new Login whose NEXT claim (today) is later-weeks loop day `n`
--- (1..7; the first week counts as done) and, when `week` is given (1..TrackDays / 7), the
--- track's day (week - 1) * 7 + n. `firstWeek` = true instead makes it first-week day `n`
--- (1..#FirstWeek; the player must still be inside the window). Works even when today is
--- already claimed, so the tester can claim day n straight away.
function Daily.setStreakDay(
	login: Login,
	today: number,
	n: number,
	week: number?,
	firstWeek: boolean?
): Login
	local now = whole(today)
	local _, _, _, freeze = readLogin(login)
	if firstWeek == true then
		local day = math.clamp(whole(n), 1, FIRST_DAYS)
		return {
			LastDay = if day > 1 then now - 1 else 0,
			StreakDay = 0,
			Total = day - 1,
			FreezeWeek = freeze,
			FirstWeek = day - 1,
		}
	end
	local day = math.clamp(whole(n), 1, DAYS)
	local count = if week ~= nil
		then (math.clamp(whole(week), 1, TRACK_DAYS // 7) - 1) * 7 + day
		else Daily.loginState(login, now).total
	-- Store the claim just before the one wanted, dated yesterday.
	if day > 1 then
		return {
			LastDay = now - 1,
			StreakDay = day - 1,
			Total = count - 1,
			FreezeWeek = freeze,
			FirstWeek = FIRST_DAYS,
		}
	end
	return {
		LastDay = 0,
		StreakDay = 0,
		Total = math.max(0, count - 1),
		FreezeWeek = freeze,
		FirstWeek = FIRST_DAYS,
	}
end

---------------------------------------------------------------------------------------------
-- Playtime gifts (ECONOMY 10): minutes played in the day, each gift once a day
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
