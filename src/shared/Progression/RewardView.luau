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
local Social = require(script.Parent.Social)

local D = Config.Daily
local DAYS = #D.Streak
local FIRST_DAYS = #D.FirstWeek
local WIN_TRACK: { string } = Config.BlockOdds.Drop.WinTrack :: any

-- A reward as remotes carry it: money, the lucky blocks as a list in
-- Config.LuckyBlocks.Order, the ability spins and Lucky Spins it adds (0 for none: the client
-- draws a chip when above 0).
export type RewardOut = {
	money: number,
	blocks: { Daily.BlockCount },
	spins: number,
	lucky: number,
	cues: { string }, -- cue ids it gives (economy v5: the first week's day 7)
}

export type LoginView = {
	canClaim: boolean,
	claimedToday: boolean,
	day: number, -- the day today's claim is (or was): the first week's or the loop's, 1..7
	firstWeek: boolean, -- today's claim is a first-week day (the days are the first week's)
	firstWeekDays: number, -- first-week days claimed (today's counts once made)
	firstWeekLeft: number, -- days left in the first week's window, today included (0: over)
	-- the first week is still on 7 days in a row, so its day 7 is the Week One Cue (else
	-- Config.Daily.FirstWeekMissed); false outside the first week (Daily.LoginState)
	firstInRow: boolean,
	needsMatch: boolean, -- today's claim waits for a finished match (Config.Daily.NeedsMatch)
	week: number, -- the 28-day track's week that claim is in: 1..weeks
	total: number, -- days claimed counting today's claim
	bonus: boolean, -- today's claim includes a 28-day track reward
	frozen: boolean, -- today's claim keeps the streak through this week's freeze
	freezeReady: boolean, -- this week's streak freeze is unused
	reward: RewardOut, -- the loop day, the track and VIP's spin together
	-- VIP's part of every day's claim (Daily.vipReward), shown once under the tiles (a VIP's
	-- bonus, else what VIP would add)
	vipPart: RewardOut,
	vip: boolean, -- the player is VIP (today's claim includes vipPart)
}

-- Claim All (Config.Daily.ClaimAll): the rest of this 7-day row at once, for Robux.
export type ClaimAllView = {
	-- some day of the row is still ahead, and paid random items are not restricted for the
	-- player (the days give lucky blocks: hidden where restricted)
	available: boolean,
	product: string?, -- the Config.Products key to buy (its price: the shop's live one)
	robux: number, -- Config's price for it (0: none), until the shop's live price arrives
	from: number, -- the first day it claims (1..7)
	days: number, -- how many days it claims
	reward: RewardOut, -- everything it gives
}

-- One of the seven day tiles: the first week's while it lasts, else the later weeks' loop.
export type DayView = {
	day: number,
	reward: RewardOut, -- the day's own reward (VIP's part is LoginView.vip, 2026-10-10)
	bonus: boolean, -- always false (the track has its own rows)
	claimed: boolean, -- claimed in this streak (a check mark)
	today: boolean, -- today's tile (it glows with Claim while canClaim)
}

-- One reward of the 28-day track.
export type TrackView = {
	day: number, -- 1..TrackDays
	reward: RewardOut,
	reached: boolean, -- claimed in this round of the track
}

export type GiftView = {
	index: number,
	minutes: number,
	reward: RewardOut,
	ready: boolean,
	claimed: boolean,
	progress: number, -- 0..1 of the minutes played today
}

-- The group card: Join (the client's prompt) then Claim (RewardRequest "ClaimGroup").
export type GroupView = {
	id: number, -- Config.Social.GroupId
	member: boolean, -- in the group when last asked (match money +GroupBoost)
	claimed: boolean, -- the one-time reward was claimed
	reward: RewardOut,
	boost: number, -- Config.Economy.GroupBoost (0.1 = +10%)
}

-- The invite card.
export type InviteView = {
	reward: RewardOut, -- what an invite gives each side
	used: number, -- invite rewards got this UTC month
	perMonth: number, -- Config.Social.InvitesPerMonth
	invited: boolean, -- this player came through an invite
	done: boolean, -- their own invite reward was given
	rewarded: boolean, -- their reward as an inviter was given (Config.Social.InviterOnce: once ever)
}

-- The Free Reward page's favorite card (GUI lane, D4): Roblox's favorite prompt, then Claim.
export type FavoriteView = {
	claimed: boolean,
	reward: RewardOut,
}

-- The day's win track (economy v4 plan section 5): the bar above the hotbar.
export type WinsView = {
	given: number, -- track steps given today, 0..#kinds
	kinds: { string }, -- each step's block kind or "Money" (Config.BlockOdds.Drop.WinTrack; the
	-- first win's block, while due, at the next step)
}

export type Payload = {
	today: number,
	resetsAt: number,
	sentAt: number,
	weeks: number,
	login: LoginView,
	claimAll: ClaimAllView,
	days: { DayView },
	trackDays: number, -- Config.Daily.TrackDays
	trackPlace: number, -- days claimed in this round of the track, 0..trackDays
	track: { TrackView },
	playtime: { GiftView },
	playSeconds: number,
	titles: { string },
	group: GroupView,
	invite: InviteView,
	favorite: FavoriteView,
	wins: WinsView,
	ready: boolean,
}

local RewardView = {}

-- The save's Flags key set once the favorite reward was given (GUI lane, D4).
RewardView.FavoriteFlag = "FavoriteReward"
-- The save's Flags key set once the inviter's reward was given (Config.Social.InviterOnce).
RewardView.InviterFlag = "InviterRewarded"
-- The save's Flags key set once the first win's block was given (PlayerData's FIRST_WIN_FLAG,
-- Config.BlockOdds.Drop.FirstWin).
RewardView.FirstWinFlag = "FirstWinBlock"

-- A finite number, else 0.
local function num(x: any): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return 0
	end
	return x
end

--- Claim All's offer (Daily.claimAllOffer) as the remote carries it, with Config's price
--- (`restricted`: paid random items are restricted for the player, so it is not available).
function RewardView.claimAll(offer: Daily.ClaimAllOffer, restricted: boolean?): ClaimAllView
	local row = if offer.product then (Config.Products.List :: any)[offer.product] else nil
	return {
		available = offer.available and restricted ~= true,
		product = offer.product,
		robux = if row then row.Robux else 0,
		from = offer.from,
		days = offer.days,
		reward = RewardView.reward(offer.reward),
	}
end

--- A Daily.Reward as a remote carries it: { money, blocks = { { kind, count } }, spins,
--- lucky, cues } with the blocks in Config.LuckyBlocks.Order (a list, so the client shows and
--- flies them in a fixed order); spins and lucky are 0 when the reward adds none; cues the
--- cue ids it gives, in order (economy v5: the Week One Cue), empty for none.
function RewardView.reward(reward: Daily.Reward): RewardOut
	local raw: any = reward
	local cues: { string } = {}
	if type(raw.cues) == "table" then
		for _, id in raw.cues do
			if type(id) == "string" then
				table.insert(cues, id)
			end
		end
	end
	return {
		money = math.max(0, math.floor(num(raw.money))),
		blocks = Daily.blockList(reward),
		spins = math.max(0, math.floor(num(raw.spins))),
		lucky = math.max(0, math.floor(num(raw.lucky))),
		cues = cues,
	}
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

--- Which playtime gifts are ready now, as a short key ("100": the first only), then whether a
--- match was finished today (the login claim waits for one) and the win track's steps, so
--- the server re-sends the state when any of these change and not on every playtime tick.
function RewardView.readyKey(daily: any): string
	local parts = {}
	for _, gift in Daily.playtimeState(daily) do
		table.insert(parts, if gift.ready then "1" else "0")
	end
	local t = if type(daily) == "table" then daily else {}
	table.insert(parts, if num(t.Matches) > 0 then "m" else "-")
	table.insert(parts, tostring(math.floor(num(t.Track))))
	return table.concat(parts)
end

--- The RewardState payload for one player at unix time `now` (its shape is written in
--- Net.luau, RewardState). `login` is the save's Login, `daily` today's Daily (a fresh one on
--- a new day: PlayerData.dailyState), `titles` the save's Titles, `vip` whether the player
--- is VIP (each day's claim adds Config.Daily.VipSpins and VipBlocks), `social` the save's
--- Social and `member` whether the player is in the group (the InGroup attribute), `flags`
--- the save's Flags (the favorite reward's flag, RewardView.FavoriteFlag; the first win's) and `extra` what
--- the login rules need besides the save (Daily.LoginExtra: the join day, VIP's restriction;
--- today's match is read from `daily`).
--- The day's win track for the bar: the steps given today and each step's kind, a block kind
--- or "Money" (Config.BlockOdds.Drop.WinTrack). A player whose first win's block is still due
--- (`flags` without RewardView.FirstWinFlag) sees it at the next step, as BlockDrop.winKind
--- gives it (a Rare block, economy v5).
function RewardView.wins(daily: any, flags: any?): WinsView
	local given = math.clamp(
		math.floor(num(if type(daily) == "table" then daily.Track else 0)),
		0,
		#WIN_TRACK
	)
	local kinds = table.clone(WIN_TRACK)
	if type(flags) == "table" and flags[RewardView.FirstWinFlag] ~= true and kinds[given + 1] then
		kinds[given + 1] = Config.BlockOdds.Drop.FirstWin
	end
	return { given = given, kinds = kinds }
end

function RewardView.build(
	login: any,
	daily: any,
	titles: any,
	now: number,
	vip: boolean?,
	social: any,
	member: boolean?,
	flags: any?,
	extra: Daily.LoginExtra?
): Payload
	local today = Daily.dayOf(num(now))
	local matches = if type(daily) == "table" then num(daily.Matches) else 0
	local loginExtra: Daily.LoginExtra = {
		joinDay = if extra then extra.joinDay else nil,
		restricted = if extra then extra.restricted else nil,
		played = matches > 0,
	}
	local restricted = loginExtra.restricted
	local state = Daily.loginState(login, today, vip, loginExtra)

	-- The track: the days claimed in this round (today's claim counts once made).
	local claimedTotal = if state.claimedToday then state.total else state.total - 1
	local place = if claimedTotal <= 0 then 0 else (claimedTotal - 1) % D.TrackDays + 1
	local track: { TrackView } = {}
	for _, row in D.Track :: { any } do
		local reward = Daily.trackReward(row.Day)
		if reward ~= nil then
			table.insert(track, {
				day = row.Day,
				reward = RewardView.reward(reward),
				reached = place >= row.Day,
			})
		end
	end

	-- Each tile shows its day's own reward; VIP's part is shown once (login.vip).
	local days: { DayView } = {}
	for day = 1, if state.firstWeek then FIRST_DAYS else DAYS do
		local reward, bonus
		if state.firstWeek then
			reward, bonus = Daily.firstWeekReward(day, false, nil, not state.firstInRow), false
		else
			reward, bonus = Daily.streakReward(day, false)
		end
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
	local soc = if type(social) == "table" then social else {}
	local groupClaimed = soc.Group == true
	anyReady = anyReady or (member == true and not groupClaimed)
	local month = Social.monthOf(num(now))
	local inviteBlock: { [string]: number } = { [Config.Social.InviteBlock] = 1 }
	return {
		today = today,
		resetsAt = Daily.dayStart(today + 1),
		sentAt = math.floor(num(now)),
		weeks = D.WeeksForBonus,
		login = {
			canClaim = state.canClaim,
			claimedToday = state.claimedToday,
			day = state.day,
			firstWeek = state.firstWeek,
			firstWeekDays = state.firstWeekDays,
			firstWeekLeft = state.firstWeekLeft,
			firstInRow = state.firstInRow,
			needsMatch = state.needsMatch,
			week = state.week,
			total = state.total,
			bonus = state.bonus,
			frozen = state.frozen,
			freezeReady = state.freezeReady,
			reward = RewardView.reward(state.reward),
			vipPart = RewardView.reward(Daily.vipReward(restricted)),
			vip = vip == true,
		},
		claimAll = RewardView.claimAll(
			Daily.claimAllOffer(login, today, vip, loginExtra),
			restricted
		),
		days = days,
		trackDays = D.TrackDays,
		trackPlace = place,
		track = track,
		playtime = playtime,
		playSeconds = math.max(0, math.floor(seconds)),
		titles = RewardView.titles(titles),
		group = {
			id = Config.Social.GroupId,
			member = member == true,
			claimed = groupClaimed,
			reward = RewardView.reward({
				money = 0,
				blocks = table.clone(Config.Social.GroupReward.Blocks),
				spins = 0,
				lucky = 0,
			}),
			boost = Config.Economy.GroupBoost,
		},
		invite = {
			reward = RewardView.reward({
				money = 0,
				blocks = inviteBlock,
				spins = 0,
				lucky = 0,
			}),
			used = if soc.InviteMonth == month
				then math.max(0, math.floor(num(soc.Invites)))
				else 0,
			perMonth = Config.Social.InvitesPerMonth,
			invited = num(soc.InvitedBy) > 0,
			done = soc.InviteDone == true,
			rewarded = type(flags) == "table" and flags[RewardView.InviterFlag] == true,
		},
		favorite = {
			claimed = type(flags) == "table" and flags[RewardView.FavoriteFlag] == true,
			reward = RewardView.reward({
				money = Config.Social.FavoriteReward.Money,
				blocks = table.clone(Config.Social.FavoriteReward.Blocks),
				spins = 0,
				lucky = 0,
			}),
		},
		wins = RewardView.wins(daily, flags),
		ready = anyReady,
	}
end

return RewardView
