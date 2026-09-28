--!strict
-- Net: the one place that names the remotes, so the server and the client cannot disagree
-- about what a message is called or which direction it travels.
--
-- The server creates them and the client waits for them; nothing here is in the Rojo tree,
-- because a RemoteEvent is state, not source.
--
-- Most of these are reliable and rare: seats change when somebody steps on a pad, and a
-- shot is one message. The aim pair is the exception and is deliberately unreliable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AimStream = require(script.Parent.AimStream)

local Net = {}

local FOLDER = "Net"

local REMOTES: { [string]: string } = {
	MatchAction = "RemoteEvent", -- phase/version validated gameplay requests
	SnapshotRequest = "RemoteEvent", -- listeners ready; send complete authoritative state
	-- server -> the owning team only: a bonus sting this player's team earned, sent when the
	-- shot is accepted and before its ShotResult. {tableId, epoch, id, seq, index, ball, team,
	-- at}; the client plays it on the matching replay pocket drop (epoch, seq, ball) and
	-- dedupes by id.
	MatchFeedback = "RemoteEvent",
	-- server -> all: a table's seats changed (someone joined, left, or the host moved on).
	TableState = "RemoteEvent",
	-- client -> server: please seat me at this table / take me off it.
	RequestSeat = "RemoteEvent",
	RequestLeave = "RemoteEvent",
	-- server -> everyone free (not seated at a table): a host whose pad has room asks for
	-- players. {tableId, epoch, teamSize, userId, name, at}; the client shows OpponentPrompt.
	OpponentRequest = "RemoteEvent",
	-- client -> server: I answer that ask with Join. (tableId, epoch); the server checks it
	-- still stands, then puts the player on the pad and seats them.
	AnswerRequest = "RemoteEvent",
	RequestRerack = "RemoteEvent", -- Studio-only developer reset; server advances/broadcasts rack seed
	-- client -> server: I want to take this shot. Inputs only; the server decides what
	-- actually happens (ARCHITECTURE.md section 1, never trust the client).
	-- {tableId, angle, power, spin={x,y}, elevation}; optional ability id requires server
	-- authorization. Client-supplied material coefficients are rejected.
	ShotFired = "RemoteEvent",
	-- server -> one client: your shot was turned down, and why. Without this the client
	-- that optimistically disabled its own input when it fired never hears anything back
	-- and sits there with dead controls.
	ShotRejected = "RemoteEvent",
	-- server -> all: a shot has started on a table. Carries the post-strike cue ball state
	-- to replay from, the server's final positions to settle on, and a checksum.
	-- Optional overrides are copied from the server's material catalog for this shot only.
	-- On the shot that picks the colors, `assign` {groups, ball, index} names the ball whose
	-- drop reveals both teams' groups, before the snapshot catches up at resolution.
	ShotResult = "RemoteEvent",
	-- server -> each player a shot paid (the shooter, and every teammate for the team's balls,
	-- ECONOMY 3.3), their own share only, for the flying cash (CashFlyer). {tableId, epoch,
	-- seq, total, grants = {{ball, pocket?, amount, kind, at}}}; kind "Ball" or a nice shot's
	-- kind (the shooter's only); `at` is the server time the ball drops in the replay. Nothing
	-- here is ever sent back: the money is already in the save (Economy, PlayerData).
	MoneyGrant = "RemoteEvent",
	-- server -> each player of a finished match: the result screen's numbers, once
	-- (Ranking). The client only animates them. {key, tableId, epoch, preview?, solo, winner?,
	-- reason, short (not real, not solo), teams = {{{userId, name, displayName, tier,
	-- division, left}}} (team 1, team 2), you = {userId, team, outcome = "Win" | "Loss" |
	-- "Draw", forfeited},
	-- xp? (nil: solo, under the one-minute mark, or no save) = {before, after (ranks: tier,
	--   division, index, xpInDivision, width?), xpBefore, xpAfter, delta (never below 0),
	--   promoted, newTier, rewards = {{index, money, cases = {[caseId] = count}, cue?}} (every
	--   division the new peak passed, bottom first), rewardTotal, rewardCases = {[caseId] =
	--   count}, rewardCues = {cueId}, breakdown = {base, mode, fade, gap, pc, farm, boosts =
	--   {{kind = "Rookie" | "Vip" | "FirstWin" | "Streak", share}}, boostTotal}},
	-- money = {balls, ballMoney, nice, niceMoney (the pots, paid live), bonus (win or loss),
	--   streak (the win-streak bonus), reward (rank-up money), boost (the money boost share
	--   applied at the end: VIP + Money Party, 0..2), total (all of them added)},
	-- freeCase? (a case id put in the inventory), firstWin? = {case, cue, rarity, new, found}
	-- (the first win's case, opened at once: its cue is already owned; found is the finder's
	-- money it paid, 0 when the cue was in the Index already; freeCase is nil then),
	-- nextReward? (Daily.nextReward: {day, week, reward = {money, cases}, bonus, tomorrow}, the
	-- reminder line), rookieLeft? (real matches left in the Rookie Boost), rematch, arena,
	-- series? = {wins = {team 1, team 2}, games}}.
	MatchSummary = "RemoteEvent",
	-- server -> one player: a promotion outside a match's result screen (/xp, /newrank). XP is
	-- never lost, so there is no rank-down. {kind = "Up", preview?, before, after, reward
	-- (money), newTier, rewards? = {{index, money, cases = {[caseId] = count}, cue?}},
	-- rewardCases? = {[caseId] = count}, rewardCues? = {cueId}} (the NEW RANK! chips).
	RankEvent = "RemoteEvent",
	-- server -> one player: a private line for the chat window (the developer commands), or a
	-- table { kind = "OpenCase", caseId, count } that opens that case on the reel (/opencase;
	-- CaseOpening listens, the chat handler ignores tables).
	DevNotice = "RemoteEvent",
	-- The global queue and the arena (designer, 2026-09-28).
	-- server -> the players of one search: {kind = "Found" | "Teleporting" | "Failed" |
	-- "Searching" | "Stopped", mode, at?, reason?}. Found shows the teleport screen;
	-- Failed says why the players are still here (Strings.Queue.Failed[reason]).
	QueueNotice = "RemoteEvent",
	-- client -> server (arena only): the post-game choice that is not the table's own vote:
	-- "Another" (a new opponent), "CancelAnother", "Lobby" (back to the lobby server).
	ArenaAction = "RemoteEvent",
	-- server -> everyone in an arena: {mode, teams = {{userId}}, arrived = {userId},
	-- deadline?, choices = {[userId] = "Another" | "Lobby"}, searching = {[userId] = at},
	-- notice?}. The arrival card and the post-game row read it.
	ArenaState = "RemoteEvent",
	-- The economy (2026-09-28). Every request carries ids and counts only, never an amount of
	-- money, a price, a rarity or a result: the server prices, rolls and decides everything.
	-- client -> server, answered (src/server/Items.luau): (action, a?, b?) -> { ok = true, ... }
	-- or { ok = false, reason }; it never errors. A missing count is 1. Actions and replies:
	--   "BuyCase" (caseId, count 1 | Config.Cases.BulkCount) -> { caseId, count, price,
	--     perCase, onSale } (a failed buy for money adds { need, price })
	--   "OpenCase" (caseId, count 1 | Config.Cases.FastOpenCount, more than 1 with Fast Open)
	--     -> { caseId, results = { { cue, rarity, new, duplicate, count, found } } } (count:
	--     copies owned once it was added; found: the finder's money a cue new to the Index
	--     paid, else 0; rolled by the server; a switched-off case still opens)
	--   "SellCue" (cueId, count) -> { cueId, count, money }
	--   "SellDuplicates" (cueId? for one cue's, else every case cue's) -> { money, sold = { {
	--     id, count, money } } } (nothing to sell: money 0, sold {})
	--   "EquipCue" (cueId) -> { cueId }
	--   "MarkSeen" ({ cueId } at most Config.Items.MarkSeenMax) -> { cleared }
	--   "ClaimIndexRow" (rarity) -> { rarity, money, title }
	--   "BuyLimited" (cueId: a money-priced Limited shelf row) -> { cueId, copy, price }
	-- Reasons (Progression/Requests.Reasons): "BadRequest" (unknown action, wrong type,
	-- unknown id, count not allowed), "TooFast" (Config.Items.RateBurst / RatePerSecond),
	-- "Busy" (another request still being answered), "NotLoaded" (the save, or for BuyCase the
	-- PolicyService answer, is not ready), "Teleporting", "NotSold" (a switched-off case),
	-- "Restricted" (paid random items), "NotEnoughMoney" (+ need, price), "NoCases",
	-- "NoFastOpen", "NotOwned", "CantSell" (Exclusive, Unique, Classic), "Equipped" (the last
	-- copy of the equipped cue), "Claimed", "Incomplete", "NoReward" (Exclusive and Unique
	-- rows), "NotStarted", "Ended", "SoldOut", "Owned" (a Limited is one per player), "Error".
	ItemRequest = "RemoteFunction",
	-- server -> one player: their inventory, the Progression/Inventory.snapshot table itself (no
	-- wrapper): { cues = { { id, count, new, copy? } }, cases = { { id, count } }, equipped,
	-- seen = { id }, rows = { { rarity, have, total, complete, claimed, reward = { money,
	-- title }? } }, titles = { id } }. Sent when the save loads and after every change that
	-- touches it, at most once a frame, and only when it differs from the last one sent. The
	-- server's copy is the truth; the client only draws it. Copies in existence are not in it:
	-- they are attributes on ReplicatedStorage.CueCounts (one per cue id, from the first read
	-- on) and the Limited sold counts on ReplicatedStorage.LimitedSold (src/server/Counters).
	ItemState = "RemoteEvent",
	-- server -> one player: cues that just entered their Index for the first time, and the
	-- finder's money each paid (Config.Index.FindMoney, already added): { { cue, money } }.
	-- Sent for every source but a case reel (OpenCase's reply and MatchSummary.firstWin carry
	-- theirs): rank-up and reward cues, the VIP and Starter cues, Limited cues (src/server/
	-- Items.luau, from PlayerData.CueFound). The client shows a banner line.
	CueFound = "RemoteEvent",
	-- server -> one player: the shop's state for them (src/server/Store.luau builds it with
	-- Progression/ShopView.build). Sent on load and whenever any of it changes: a purchase, a
	-- pass, the Vip/FastOpen/PaidRandomRestricted attributes, the case sale, the Money Party,
	-- a Limited count, an offer or Limited window opening or closing on the clock. Times are
	-- unix seconds on the server's clock (workspace:GetServerTimeNow()). {
	--   vip (the pass OR the welcome offer), vipPass, vipOffer (bought the offer), fastOpen,
	--   restricted (paid random items), firstPackBought, starterBought,
	--   offers = { VipOffer = { open, startsAt, endsAt, kind = "Welcome" | "Comeback" },
	--     StarterPack = { open, startsAt, endsAt } } (keyed by Config.Products key, read by
	--     ItemState.offerEndsAt; VipOffer shows the open window, else the comeback still to
	--     come, else zeros),
	--   party = { endsAt, buyer? }? (this server's Money Party while it runs),
	--   sale = { case, percent, endsAt }? (the one case on sale now),
	--   limited = { { cue, product?, price?, cap?, sold?, startsAt, endsAt, open, soldOut,
	--     owned, copy?, canBuy } } (Config.Shop.Limited order),
	--   products = { [Config.Products key] = { kind = "Product" | "Pass", robux (live, else
	--     Config's), available (Id set; false: "Coming soon"), owned, canBuy, reason? (the
	--     StoreRequest reason a Buy would get now), money (what one purchase gives now: a first
	--     pack doubled; 0 for none) } } }
	ShopState = "RemoteEvent",
	-- client -> server, answered: ("Buy", a Config.Products key) -> { ok, reason? }. The server
	-- checks it (Progression/ShopView.check) and prompts the purchase itself; ok = true means
	-- the prompt is up, and the grant arrives later through ProcessReceipt (a pass: through
	-- PromptGamePassPurchaseFinished) and a new ShopState. Reasons: "BadRequest" (not "Buy" or
	-- not a product key), "TooFast", "NotLoaded", "Owned" (a pass owned, VIP already, the
	-- Starter Pack or that Limited bought), "Closed" (its offer or Limited window is shut),
	-- "SoldOut", "PartyFull" (an hour of Money Party already queued), "ComingSoon" (Id 0),
	-- "Error" (the prompt failed).
	StoreRequest = "RemoteFunction",
	-- server -> one player: the Rewards menu's state (src/server/Rewards.luau builds it with
	-- Progression/RewardView.build). Sent on load, after each claim or dev change, when a
	-- playtime gift becomes ready, and to everyone when the UTC day rolls over. A reward is
	-- always { money, cases = { { id, count } } } (cases in Config.Cases.Order). {
	--   today (UTC day number), resetsAt (unix: the next UTC midnight), sentAt (unix),
	--   weeks (Config.Daily.WeeksForBonus),
	--   login = { canClaim, claimedToday, day (1..7), week, bonus (day 28), reward },
	--   days = { { day, reward, bonus, claimed, today } } (this week's seven tiles),
	--   next = { day, week, reward, bonus, tomorrow } (the reminder: "Come back tomorrow for
	--     your Rare Case"),
	--   playtime = { { index, minutes, reward, ready, claimed, progress (0..1) } },
	--   playSeconds (played today at sentAt; it grows while the player stays),
	--   titles = { titleId } (sorted), ready (the streak or a gift can be claimed) }
	RewardState = "RemoteEvent",
	-- client -> server, answered: ("ClaimDaily"), ("ClaimPlaytime", index 1..#gifts),
	-- ("Redeem", the typed code text) -> { ok = true, money, cases = { { id, count } } } or
	-- { ok = false, reason }. Reasons: "BadRequest" (an unknown action, a bad index, text that
	-- is not a string), "TooFast" (a request every Config.Daily.RequestCooldownSeconds, a code
	-- every RedeemCooldownSeconds), "NotLoaded", "AlreadyClaimed" (today's streak or that
	-- gift), "NotReady" (not enough minutes yet), "Unknown" (no such code), "Used" (this code
	-- already redeemed), "Expired", "Error".
	RewardRequest = "RemoteFunction",
	-- server -> everyone here (or one player joining during a Money Party): a banner line at
	-- the top middle and a system chat line (src/server/Announce.luau). The server sends ids and
	-- names only; the client words it from Strings.Banner. `name` is the player's username
	-- (player.Name), not their DisplayName.
	--   { kind = "Unbox", userId, name, cue, rarity } a Mythic or Secret unboxed here
	--     (Cases.announces), sent Config.Items.UnboxAnnounceDelaySeconds after the roll
	--   { kind = "Party", endsAt, name? } a Money Party started (endsAt: unix seconds)
	--   { kind = "Reyes" | "FirstReyes", userId, name } a player reached Reyes, in every
	--     server (MessagingService); FirstReyes: the first player ever
	Banner = "RemoteEvent",
	-- The aim stream, and the only unreliable pair here: a few low-value updates a second,
	-- and losing one just means a remote cue turns a frame later. Never worth a retransmit,
	-- and never worth blocking the reliable queue behind.
	-- client -> server: (tableId, angle, epoch, turnId, pull, seq?, x?, y?). pull is the
	-- wind-up, 0..1 in whole 1/Config.Aim.PullSteps steps (AimStream), always present so no
	-- nil sits in the middle; a let-go sends 0 at once. It is cosmetic: a shot's power comes
	-- only from ShotFired. seq, x and y ride along only while the shooter is moving the cue
	-- ball in hand; seq rises every send within a turn, because this remote guarantees
	-- neither delivery nor order.
	AimUpdate = "UnreliableRemoteEvent",
	-- server -> all: every table's aim, batched as a flat array of Net.AimStride values per
	-- table, {tableId, shooterUserId, angle, cueX, cueY, pull, elevation} (AimStream.pack
	-- and .read);
	-- the cue spot is the server's own and the pull is snapped again on the way through.
	AimBroadcast = "UnreliableRemoteEvent",
}

-- Values per table in an AimBroadcast batch.
Net.AimStride = AimStream.Stride

local function container(): Instance
	local existing = ReplicatedStorage:FindFirstChild(FOLDER)
	if existing then
		return existing
	end
	if not RunService:IsServer() then
		return ReplicatedStorage:WaitForChild(FOLDER, 30) or ReplicatedStorage
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER
	folder.Parent = ReplicatedStorage
	return folder
end

--- Create every remote. Server only, called once from Bootstrap before anything else.
function Net.build()
	local folder = container()
	for name, class in REMOTES do
		if folder:FindFirstChild(name) == nil then
			local remote = Instance.new(class)
			remote.Name = name
			remote.Parent = folder
		end
	end
end

--- Get a remote by name, waiting for it on the client.
function Net.get(name: string): any
	assert(REMOTES[name], ("Net: no remote called %q"):format(name))
	local folder = container()
	local remote = folder:FindFirstChild(name) or folder:WaitForChild(name, 30)
	assert(remote, ("Net: remote %q never arrived"):format(name))
	return remote :: RemoteEvent
end

return Net
