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
	-- server -> the shooter only: money this shot paid them, for the flying cash
	-- (CashFlyer). {tableId, epoch, seq, total, grants = {{ball, pocket?, amount, kind, at}}};
	-- `at` is the server time the ball drops in the replay. Nothing here is ever sent back:
	-- the money is already in the save (Economy, PlayerData).
	MoneyGrant = "RemoteEvent",
	-- server -> each player of a finished match: the result screen's numbers, once
	-- (Ranking). The client only animates them.
	MatchSummary = "RemoteEvent",
	-- server -> one player: a rank change outside a match's result screen (/xp, /newrank):
	-- {kind = "Up" | "Down", before, after, reward, newTier}.
	RankEvent = "RemoteEvent",
	-- server -> one player: a private line for the chat window (the developer commands).
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
	-- client -> server, answered: (action, a?, b?) -> reply { ok: boolean, reason: string?, ... }.
	-- Actions (src/server/Items.luau): "BuyCase" (caseId, count 1 | BulkCount), "OpenCase"
	-- (caseId, count 1 | FastOpenCount) -> { results = { { cue, rarity, new, duplicate } } },
	-- "SellCue" (cueId, count) -> { money }, "SellDuplicates" (cueId?) -> { money, sold },
	-- "EquipCue" (cueId), "MarkSeen" ({ cueId }), "ClaimIndexRow" (rarity) -> { money,
	-- title }, "BuyLimited" (cueId) -> { copy }.
	ItemRequest = "RemoteFunction",
	-- server -> one player: their inventory (Progression/Inventory.snapshot) on load and after
	-- every change. The server's copy is the truth; the client only draws it.
	ItemState = "RemoteEvent",
	-- server -> one player: the shop's state for them (offers and their end times, VIP and
	-- Fast Open ownership, paid-random-items restriction, a case sale, Limited shelf rows,
	-- first pack bought, live Robux prices). Sent on load and when any of it changes.
	ShopState = "RemoteEvent",
	-- client -> server, answered: "Buy" (a Config.Products key) -> { ok, reason? }: the server
	-- checks the offer is open and prompts the purchase itself ("ComingSoon" while its Id is 0).
	StoreRequest = "RemoteFunction",
	-- server -> one player: the rewards menu's state (the login streak, playtime gifts, the
	-- next streak reward for the reminder, titles). Sent on load and after each change.
	RewardState = "RemoteEvent",
	-- client -> server, answered: "ClaimDaily", "ClaimPlaytime" (index), "Redeem" (code text)
	-- -> { ok, reason?, money?, cases? }.
	RewardRequest = "RemoteFunction",
	-- server -> everyone (or one player): a banner line at the top middle: { kind = "Unbox" |
	-- "Party" | "Reyes" | "FirstReyes", userId?, name?, cue?, rarity?, endsAt? }. The client
	-- words it from Strings.
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
