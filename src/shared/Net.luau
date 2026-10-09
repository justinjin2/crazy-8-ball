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
	-- seq, total, grants = {{ball, pocket?, amount, plain?, kind, at}}}; plain: the pay without
	-- VIP when VIP doubled it (the chip shows it, then a gold "x2"); kind "Ball" or a nice shot's
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
	--   promoted, newTier, rewards = {{index, money, blocks = {[kind] = count}, cue?}} (every
	--   division the new peak passed, bottom first), rewardTotal, rewardBlocks = {[kind] =
	--   count}, rewardCues = {cueId}, breakdown = {base, mode, fade, gap, pc, farm, boosts =
	--   {{kind = "Streak", share}}, boostTotal}},
	-- money = {balls, ballMoney, nice, niceMoney, ballStreakMoney and bestStreak (the ball
	--   streak's bonus and the best level it paid at; the pots, paid live), bonus (win or loss),
	--   streak (the win-streak bonus), reward (rank-up money), boost (the money boost share
	--   applied at the end: VIP + Money Party, 0..2), total (all of them added)},
	-- block? = { kind, readyAt } (the win's lucky block, already in the hotbar: a Mystery
	-- block, the first win's Rare one; readyAt in unix seconds, 0 = ready now),
	-- rematch, arena, series? = {wins = {team 1, team 2}, games}}.
	MatchSummary = "RemoteEvent",
	-- server -> one player: a NEW RANK! preview (/newrank). Real rank-ups are not sent: the
	-- client shows one popup per division between the RankShown and PeakDivision attributes
	-- once it is free in a lobby server (Progression). XP is never lost, so there is no rank-down. {kind = "Up", preview?, before, after, reward
	-- (money), newTier, rewards? = {{index, money, blocks = {[kind] = count}, cue?}},
	-- rewardBlocks? = {[kind] = count}, rewardCues? = {cueId}} (the NEW RANK! chips).
	RankEvent = "RemoteEvent",
	-- server -> one player: a private line for the chat window (the developer commands).
	DevNotice = "RemoteEvent",
	-- The global queue and the arena (designer, 2026-09-28).
	-- server -> the players of one search: {kind = "Found" | "Teleporting" | "Failed" |
	-- "Searching" | "Stopped", mode, at?, reason?}. Found shows the teleport screen;
	-- Failed says why the players are still here (Strings.Queue.Failed[reason]).
	QueueNotice = "RemoteEvent",
	-- client -> server: "Start" or "Cancel" Play Global with no pad, from the spawn pill of a
	-- player alone in a public lobby (SoloSearch; designer, 2026-10-07).
	SoloSearch = "RemoteEvent",
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
	--   "SellCue" (cueId, count) -> { cueId, count, money }
	--   "SellDuplicates" (cueId? for one cue's, else every block cue's) -> { money, sold = { {
	--     id, count, money } } } (nothing to sell: money 0, sold {})
	--   "EquipCue" (cueId) -> { cueId }
	--   "MarkSeen" ({ cueId } at most Config.Items.MarkSeenMax) -> { cleared }
	--   "ClaimIndexRow" (rarity) -> { rarity, money }
	--   "BuyLimited" (cueId: a money-priced Limited shelf row) -> { cueId, copy, price }
	--   "BuyBlocks" (dealId: a Config.Shop.Deals key, count: a count it sells) -> { dealId,
	--     kind, count, price } (the lucky blocks land ready at once, paid origin; "BuyMystery"
	--     (count) is the old name for the Mystery deal)
	--   "BuyRestock" (itemId "Slot1" .. "Slot3" | "Vip" of the restock now) -> { itemId,
	--     price } (its lucky block lands ready at once)
	-- Reasons (Progression/Requests.Reasons): "BadRequest" (unknown action, wrong type,
	-- unknown id, count not allowed), "TooFast" (Config.Items.RateBurst / RatePerSecond),
	-- "Busy" (another request still being answered), "NotLoaded" (the save, or for a block
	-- purchase the PolicyService answer, is not ready), "Teleporting",
	-- "Restricted" (paid random items), "NotEnoughMoney" (+ need, price),
	-- "VipOnly" (the restock's VIP slot), "Full"
	-- (BuyBlocks, BuyRestock: the hotbar holds Config.LuckyBlocks.MaxBlocks),
	-- "NotOwned", "CantSell" (Exclusive, Unique, Classic), "Equipped" (the last
	-- copy of the equipped cue), "Claimed", "Incomplete", "NoReward" (Exclusive and Unique
	-- rows), "NotStarted", "Ended", "SoldOut", "Owned" (a Limited is one per player), "Error".
	ItemRequest = "RemoteFunction",
	-- server -> one player: their inventory, the Progression/Inventory.snapshot table itself (no
	-- wrapper): { cues = { { id, count, new, copy? } }, equipped,
	-- seen = { id }, rows = { { rarity, have, total, complete, claimed, reward = { money }? } },
	-- titles = { id } }. Sent when the save loads and after every change that
	-- touches it, at most once a frame, and only when it differs from the last one sent. The
	-- server's copy is the truth; the client only draws it. Copies in existence are not in it:
	-- they are attributes on ReplicatedStorage.CueCounts (one per cue id, from the first read
	-- on) and the Limited sold counts on ReplicatedStorage.LimitedSold (src/server/Counters).
	ItemState = "RemoteEvent",
	-- server -> one player: cues that just entered their Index for the first time, and the
	-- finder's money each paid (Config.Index.FindMoney, already added): { { cue, money } }.
	-- Sent for every source but a lucky block's reel (BlockRequest Open's reply carries
	-- theirs): rank-up and reward cues, the VIP and Starter cues, Limited cues (src/server/
	-- Items.luau, from PlayerData.CueFound). The client shows a banner line.
	CueFound = "RemoteEvent",
	-- server -> one player: the shop's state for them (src/server/Store.luau builds it with
	-- Progression/ShopView.build). Sent on load and whenever any of it changes: a purchase, a
	-- pass, the Vip/PaidRandomRestricted attributes, the Money Party,
	-- a Limited count, an offer or Limited window opening or closing on the clock. Times are
	-- unix seconds on the server's clock (workspace:GetServerTimeNow()). {
	--   vip (the pass OR the welcome offer), vipPass, vipOffer (bought the offer),
	--   restricted (paid random items), firstPackBought, starterBought,
	--   offers = { VipOffer = { open, startsAt, endsAt, kind = "Welcome" | "Comeback" },
	--     StarterPack = { open, startsAt, endsAt } } (keyed by Config.Products key, read by
	--     ItemState.offerEndsAt; VipOffer shows the open window, else the comeback still to
	--     come, else zeros),
	--   party = { endsAt, buyer? }? (this server's Money Party while it runs),
	--   limited = { { cue, product?, price?, cap?, sold?, startsAt, endsAt, open, soldOut,
	--     owned, copy?, canBuy } } (Config.Shop.Limited order),
	--   products = { [Config.Products key] = { kind = "Product" | "Pass", robux (live, else
	--     Config's), available (Id set; false: "Coming soon"), owned, canBuy, reason? (the
	--     StoreRequest reason a Buy would get now), money (what one purchase gives now: a first
	--     pack doubled; 0 for none) } },
	--   order = { section } (the one scrolling page top to bottom, Config.Shop.Order: "Offer",
	--     "Vip", "Restock", "Limited", "Mystery", "Money", "Boosts", "RobloxPlus"),
	--   robloxPlus (show Get Roblox Plus), bestValue (the pack marked "Best value"),
	--   packs = { key } (the money packs in order),
	--   restock = { slot, startsAt, endsAt, items = { { id ("Uncommon", "Rare", "Epic",
	--     "Legendary", "Mystery", "Vip"), price
	--     (money), product? (its Robux key), stock (per player), left (this player's), global?
	--     (a shared stock, none now), globalLeft? (nil: unknown), vip, canBuy, reason? } },
	--     each item's `block` the lucky block kind in that slot (Slot1 .. Slot3, Vip) } (a new
	--     restock every Config.Shop.Restock.SlotSeconds; ShopState is sent again when it
	--     changes),
	--   deals = { [dealId] = { kind, counts, money, products (three arrays side by side:
	--     counts[i] blocks for money[i] money or Robux product products[i]), open, timed,
	--     startsAt, endsAt, vaulted, vaultedUntil } } (Config.Shop.Deals: Mystery always open;
	--     GrandOpening for its 21 days, "vaulted" for 7 more),
	--   guarantees = { [kind] = { cue, at, opened, left, owned } } (a block kind's Guarantee:
	--     the Grand Opening block's Beta Cue on the 400th open),
	--   mystery = { price, bulkCount, bulkPrice },
	--   pity = { rare, epic } (Mystery blocks until a Rare / Epic tier is guaranteed),
	--   releaseSale = { open, startsAt, endsAt, percent, swap = { normal key -> sale key } }
	--     (GUI lane, 2026-10-03: the release sale's products Pack4Sale-Pack7Sale, VipSale,
	--     Mystery10Sale sell only while open; the Legendary restock has no shared stock now) }
	-- Product keys (Config.Products): passes Vip, UltSlot2, UltSlot3; products VipOffer,
	-- StarterPack, Pack1-7, Mystery1, Mystery5, GrandOpening1/3/10, RestockRare, RestockEpic,
	-- RestockLegendary, LuckyBlockSkip, MoneyParty, Spin1/5/10/50, Lucky1/3. Paid random
	-- items (blocks, Restock, the block skip, spins)
	-- answer "Restricted" where PolicyService restricts them; blocks answer "Full" when the
	-- hotbar is full.
	ShopState = "RemoteEvent",
	-- client -> server, answered: ("Buy", a Config.Products key) -> { ok, reason? }, or
	-- ("RobloxPlus") -> { ok } (the Roblox Plus subscription prompt; Roblox pays the game for
	-- a subscriber signed up in it). A restock
	-- product (RestockEpic, RestockLegendary) buys the item in the restock shown now, within
	-- this player's stock ("SoldOut", "VipOnly", "NotSold"). The server
	-- checks it (Progression/ShopView.check) and prompts the purchase itself; ok = true means
	-- the prompt is up, and the grant arrives later through ProcessReceipt (a pass: through
	-- PromptGamePassPurchaseFinished) and a new ShopState. Reasons: "BadRequest" (not "Buy" or
	-- not a product key), "TooFast", "NotLoaded", "Owned" (a pass owned, VIP already, the
	-- Starter Pack or that Limited bought), "Closed" (its offer or Limited window is shut),
	-- "SoldOut", "PartyFull" (an hour of Money Party already queued), "ComingSoon" (Id 0),
	-- "Restricted" (a paid random item where they are restricted), "Error" (the prompt failed).
	-- ("Gift", a Config.Products key, a user id) -> { ok, reason? } prompts the same product
	-- purchase for the giver and grants it to that player when the receipt comes (their
	-- save; a money pack pays their first-buy double, an offer they cannot have pays its money
	-- fallback). Only Kind "Product" rows without Restock or SkipSeconds: "NoGift"; "GiftSelf"
	-- (their own id), "GiftGone" (not in this server), "GiftNotLoaded", else as "Buy". A giver
	-- whose receipt arrives after the receiver left gets the item (GiftReceived returned).
	StoreRequest = "RemoteFunction",
	-- server -> one player: a gift landed. { from (the giver's display name), key (the
	-- Config.Products key) }, or to the giver { key, returned = true } when the receiver had
	-- left and the item went to them instead.
	GiftReceived = "RemoteEvent",
	-- server -> one player: a Robux purchase landed (a developer product's receipt granted, or a
	-- game pass bought in this server), for the thank-you and the flow to the HUD (Purchased).
	-- { key (the Config.Products key), money (0 for none), blocks = { { kind, count } }, cue?,
	--   vip?, party?, spins?, skip? (a block timer skip), claimAll?, pass? (a game pass),
	--   to? (a gift: the receiver's display name, sent to the giver), from? (a gift: the giver's
	--   display name, sent to the receiver) }. Money spent in the game sends nothing here.
	PurchaseDone = "RemoteEvent",
	-- server -> one player: the Rewards menu's state (src/server/Rewards.luau builds it with
	-- Progression/RewardView.build). Sent on load, after each claim or dev change, when a
	-- playtime gift becomes ready, when VIP or the group answer changes, and to everyone when
	-- the UTC day rolls over. A reward is always { money, blocks = { { kind, count } }, spins,
	-- lucky } (blocks in Config.LuckyBlocks.Order). {
	--   today (UTC day number), resetsAt (unix: the next UTC midnight), sentAt (unix),
	--   weeks (the 28-day track's four weeks),
	--   login = { canClaim, claimedToday, day (1..7 of the loop), week (the track's), total
	--     (days claimed with today's), bonus (a track reward today), frozen (the week's streak
	--     freeze kept the streak), freezeReady, reward (the loop day + track + VIP's spin) },
	--   days = { { day, reward, bonus (false), claimed, today } } (the loop's seven tiles),
	--   trackDays (28), trackPlace (days claimed this round, 0..28),
	--   track = { { day (a Config.Daily.Track day: 8, 14, 21, 28), reward, reached } },
	--   playtime = { { index, minutes, reward, ready, claimed, progress (0..1) } },
	--   playSeconds (played today at sentAt; it grows while the player stays),
	--   titles = { titleId } (sorted),
	--   group = { id, member, claimed, reward, boost (0.1) } (Join: the client's
	--     GroupService:PromptJoinAsync(id); then Claim),
	--   invite = { reward, used (this month), perMonth, invited, done, rewarded (the
	--     inviter's own block was given: once ever, Config.Social.InviterOnce) } (the client's
	--     SocialService:PromptGameInvite with ExperienceInviteOptions.LaunchData =
	--     Progression/Social.launchData(its own UserId)),
	--   favorite = { claimed, reward } (GUI lane: the Free Reward page's favorite card),
	--   ready (the day, a gift or the group can be claimed) }
	RewardState = "RemoteEvent",
	-- client -> server, answered: ("ClaimDaily"), ("ClaimPlaytime", index 1..#gifts),
	-- ("Redeem", the typed code text), ("ClaimGroup"), ("ClaimFavorite": after Roblox's
	-- favorite prompt said yes; GUI lane) -> { ok = true, money, blocks = { { kind,
	-- count } }, spins, lucky } or { ok = false, reason }. Reasons: "BadRequest" (an
	-- unknown action, a bad index, text that is not a string), "TooFast" (a request every
	-- Config.Daily.RequestCooldownSeconds, a code every RedeemCooldownSeconds, a group claim
	-- every Config.Social.ClaimCooldownSeconds), "NotLoaded", "AlreadyClaimed" (today's
	-- claim, that gift or the group), "NotReady" (not enough minutes yet), "Unknown" (no such
	-- code, or a like code not switched on), "Used" (this code already redeemed), "Expired",
	-- "NotMember" (not in the group yet), "Error".
	RewardRequest = "RemoteFunction",
	-- Trading (src/server/Trading.luau; the rules are Progression/Trade). An item is a cue id or
	-- "Block:<kind>" (a READY lucky block); a side is a list of up to Config.Trade.MaxSideItems
	-- (one entry a copy).
	-- client -> server, answered { ok = true, ... } or { ok = false, reason }:
	--   ("Invite", userId)   ask anyone in the server; they get TradeState { kind = "Invite" }
	--   ("Accept", userId)   accept that player's invite: the session opens for both
	--   ("Decline", userId)  turn it down; they get TradeState { kind = "Declined", by }
	--   ("Offer", { items }) set my side (any change takes both accepts back)
	--   ("Ready", true|false) accept / take it back; both accepted: the swap happens
	--     Config.Trade.ConfirmSeconds later unless anything changes
	--   ("Cancel")           close the session
	--   ("History")          -> { ok, history = { { Id, With, At, Gave, Got } } } (last 50)
	--   ("Want", item)       ask for one of their offerable items, or take the ask back (GUI
	--     lane, D12: a highlight on their screen, nothing moves; "Full" past MaxSideItems)
	-- Reasons: "BadRequest", "TooFast", "NotLoaded", "NotHere" (that player left), "Self",
	-- "Busy" (in another trade, or the swap is running), "NoInvite" (none, or it expired),
	-- "NoSession", and Trade.check's "Empty", "NotTradable", "NotOwned", "PaidBlocked" (a
	-- paid-origin copy where paid item trading is not allowed), "Owned" (one per player).
	TradeRequest = "RemoteFunction",
	-- server -> one player:
	--   { kind = "Invite", from = { userId, name }, expiresAt (unix) }
	--   { kind = "Declined", by = { userId, name } }
	--   { kind = "Session", id, with = { userId, name }, mine = { items }, theirs = { items },
	--     myReady, theirReady, confirmAt (unix the swap happens, or nil), problem (why these
	--     sides cannot swap now, or nil), lopsided ("Mine" | "Theirs" | nil: one side worth
	--     far more by N exist), paidOk (paid-origin copies may move), and (GUI lane, D12)
	--     myItems / theirItems ({ { item, count } } each side may offer now), theyWant /
	--     iWant ({ items } asked for) }
	--   { kind = "Closed", reason = "Done" | "Cancelled" | "Left" | "Failed", gave?, got? }
	TradeState = "RemoteEvent",
	-- server -> everyone here (or one player joining during a Money Party): a banner line at
	-- the top middle and a system chat line (src/server/Announce.luau). The server sends ids and
	-- names only; the client words it from Strings.Banner. `name` is the player's username
	-- (player.Name), not their DisplayName.
	--   { kind = "Unbox", userId, name, cue, rarity } a Legendary unboxed here
	--     (BlockOdds.announcesHere), or a Mythic or Secret unboxed in any server
	--     (BlockOdds.announces), sent Config.Items.UnboxAnnounceDelaySeconds after the roll
	--   { kind = "Party", endsAt, name? } a Money Party started (endsAt: unix seconds)
	--   { kind = "Restock", block, endsAt } a restock with that block began (a Legendary
	--     block; every server picks the same restock and announces it by itself)
	--   { kind = "Reyes" | "FirstReyes", userId, name } a player reached Reyes, in every
	--     server (MessagingService); FirstReyes: the first player ever
	Banner = "RemoteEvent",
	-- Ults in a match (src/server/UltService.luau, Ults/Match; the table's snapshot carries
	-- `ults` = { on, bars = { [tostring(userId)] = { bar, used, ready } }, armed = { by, id,
	-- stage = "Arming" | "Armed", at, readyAt, seq, practice }?, pausedUntil? }).
	-- client -> server: activate my equipped ult now. No arguments: the server picks the ult
	-- (the save's selected slot) and checks the turn, the phase, the bar and the rules; in solo
	-- it arms the free Practice ult. Success shows in the next TableState (armed).
	UltActivate = "RemoteEvent",
	-- server -> the bar's owner only: what one shot (or a timeout) filled. { tableId, epoch,
	-- seq (this game's gain message counter), gains = { { amount, reason = "Own" | "Nice" |
	-- "Opponent" | "Teammate" | "Turn" | "OpponentTurn", ball?, at } }, bar, used, ready (the
	-- bar after them) }. `at` is the server time the ball drops in the replay (a turn end's is
	-- the time it was judged), so each gain animates on its drop. The client only animates.
	UltGain = "RemoteEvent",
	-- server -> one player: { kind = "Refused", reason } for an UltActivate turned down.
	-- Reasons: "Off" (ults are off at this table), "NotYourTurn", "Moving" (the balls are
	-- rolling), "Break", "NotReady" (the bar is not full), "Used" (both ults of the match used),
	-- "Armed" (one is armed already), "NoTable" (not seated at a table).
	UltNotice = "RemoteEvent",
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
	-- The ult spin screen (src/server/UltSpins.luau; Ults/SpinView). client -> server,
	-- answered: (kind, args) -> { ok, reason?, ... }. A remote never carries an amount, price,
	-- rarity, ult id to grant or a result. Kinds: "Spin" { lucky, confirm? } -> { ok, id,
	-- rarity, replaced, wasPity, used = "Free" | "Spin" | "Lucky", slot, pity, state } (the
	-- server rolled and saved before this answer; refused "Confirm" adds current, rarity);
	-- "Select" { slot }, "Lock" { slot, locked } -> { ok, state }; "BuySpins" { pack (1, 5, 10,
	-- 50), currency = "Money" } -> { ok, pack, price, state } (NotEnoughMoney adds need,
	-- price); "BuyProduct" { product } -> { ok } once the Robux prompt is up; "AutoStart" {
	-- stopAt ("Rare" | "Epic" | "Legendary"), lucky } -> { ok, state }; "AutoStop" -> { ok }.
	-- Reasons: SpinView.Reasons (worded in Strings.Ults.Spins.Reasons).
	UltRequest = "RemoteFunction",
	-- server -> one player: the spin screen's snapshot (SpinView.state; its fields are written
	-- in SpinView.Payload), on load and after every change it shows.
	UltState = "RemoteEvent",
	-- server -> one player: Auto Spin (VIP). Each spin: { kind = "Spin", n, id, rarity,
	-- replaced, wasPity, used, slot, pity, state }; the end: { kind = "Stop", reason, n, id? }
	-- (reason: SpinView.AutoStops or a SpinView reason; id: the ult it stopped on or before).
	UltAuto = "RemoteEvent",
	-- The bots (the Bots lane). server -> all: a bot "says" something (the tutorial bot's
	-- AUGHHHH!): (bot seat id, text); every client shows a chat bubble over its head and a chat
	-- line in its name, like a person's.
	BotSay = "RemoteEvent",
	-- Settings (src/server/Settings.luau; GUI lane, C10). server -> one player, on load and after
	-- each change: { settings = { [key] = boolean } (Config.Settings.Defaults' keys), seen =
	-- { [kind] = true } }.
	SettingsState = "RemoteEvent",
	-- client -> server, answered { ok = true } or { ok = false, reason ("BadRequest",
	-- "TooFast", "NotLoaded") }: ("Set", key, boolean), ("Seen", kind in Config.Settings.SeenKinds).
	SettingsRequest = "RemoteFunction",
	-- The global boards (src/server/Leaderboards.luau; GUI lane, D9). server -> one player on
	-- load, then everyone after each read: { at, boards = { Wins = { { userId, name, value } },
	-- Rank = { ... } } } (best first, up to Config.Leaderboards.Size; Rank's value is RankXp).
	Leaderboards = "RemoteEvent",
	-- The tutorial lane (TutorialService, src/client/Tutorial.luau). client -> server: something
	-- the player did that only the client sees (kind, data?): "OpenedAbilities", "ClosedAbilities",
	-- "Nudged" (data: its name), "Skip", "RareSeen" ... each checked against the step; and for
	-- the repeating funnels "ShopOpened", "ShopViewed", "AbilitiesOpened" (any player).
	TutorialEvent = "RemoteEvent",
	-- server -> one player: (kind, data?) "Prompt" (an extra cue for the client: the target
	-- table id, the pocket to light ...), "Funnel" (Studio's debug print).
	TutorialCue = "RemoteEvent",
	-- client -> server: claim every held rank reward (RankClaim). server -> that player:
	-- { ok, money, blocks, cues, spins, rows } for the fly animation, or { ok = false }.
	RankClaim = "RemoteEvent",
	-- client -> server: (division index) NEW RANK! for that division was shown; the save's
	-- Flags.RankShown moves up to it (never past PeakDivision, never down).
	RankSeen = "RemoteEvent",
	-- Lucky blocks (2026-10-03; src/server/LuckyBlockService.luau).
	-- client -> server: (action, a, b), checked by Progression/LuckyBlocks.parse:
	-- "Hold" (block id, or nil to put it away), "Throw" (the held block's id, sent at the throw
	-- animation's release), "Open" (the thrown block's id, after the 1 s hold), "Move" (id,
	-- place in the list). Answers { ok = true, ... } or { ok = false, reason } (LuckyBlocks
	-- .Reasons). Open's answer: { ok, cue, rarity, kind, oddsId, tier?, copy?, forced, new,
	-- found, count, burstAt } (oddsId: the odds row it rolled, a Mystery block's rolled tier's;
	-- copy: a Unique cue's number; forced: the Guarantee gave it; burstAt: server time the
	-- block bursts and the reel may show).
	BlockRequest = "RemoteFunction",
	-- server -> one player: their blocks { blocks = { { id, kind, readyAt, paid? } } } in hotbar order
	-- (readyAt in unix seconds, compared with workspace:GetServerTimeNow()). Sent when the save
	-- loads and after every change, only when it differs from the last one sent.
	BlockState = "RemoteEvent",
	-- The Gift's first-leave drop (GiftDropService, client GiftDrop): server -> one player
	-- { at = CFrame } (where it lands: the client plays the fall and puts the block there);
	-- client -> server: (no arguments) "picked it up", answered back on the same event with
	-- { picked = true } or { picked = false, reason }.
	GiftDrop = "RemoteEvent",
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
