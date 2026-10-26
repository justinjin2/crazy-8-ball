--!strict
-- PadBar: what the matchmaking bar above the hotbar says (designer, 2026-10-07: one option
-- only). Pure: the table's snapshot and the times come in, the bar's state goes out, so a
-- Lune test checks it and the client (MatchBar) only draws it.
--
-- Everyone on a waiting pad sees the bar: the mode, how many are on, and "Waiting for
-- opponent..." (or players), "Starting in 3" once full. The host alone gets more: the moment
-- they step on, friends in the server or not (designer, 2026-10-09; it waited 3 s, 5 s with a
-- friend), "Don't want to wait?" and Play Global, then the search's time and an X.
--
-- The server also asks it whether to send the "<name> needs an opponent!" popup itself when
-- a host steps on (autoRequest): to everyone free, once per step-on.
local Config = require(script.Parent.Parent.Config)

local B = Config.UI.MatchBar
local M = Config.Multiplayer
local PadBar = {}

export type Press = {
	searchAt: number, -- this host's last Play Global, before the server's answer
	cancelledAt: number, -- and their last X
}

export type View = {
	line: string, -- "Waiting", "WaitingPlayers", "SwitchSides", "Starting", "Searching" or "Found"
	count: number, -- on the pad
	capacity: number, -- both teams
	isHost: boolean,
	startsIn: number?, -- whole seconds, while the line is Starting
	waited: number?, -- whole seconds searched, while the line is Searching or Found
	showGlobal: boolean, -- "Don't want to wait?" and Play Global
	needsSide: boolean, -- a team table's host before a whole side is on: no Play Global yet
	showCancel: boolean, -- the red X: the host's own search runs
	-- A split 2v2 or 3v3 pad (designer, 2026-10-26): the side you stand on, how many are on
	-- it, and whether you may walk across (the other side has room). Nil side: no split.
	side: number?,
	sideCount: number,
	sideFull: boolean,
	switchable: boolean,
}

--- `userId`'s side on a split team pad's snapshot (their waiting seat's `side`), or nil.
function PadBar.sideOf(snapshot: any, userId: number): number?
	for _, seat in snapshot.seats or {} do
		if seat.userId == userId and seat.connected ~= false then
			return if seat.side == 1 or seat.side == 2 then seat.side else nil
		end
	end
	return nil
end

-- How many wait on side `side` of a split pad's snapshot.
local function sideCount(snapshot: any, side: number): number
	local n = 0
	for _, seat in snapshot.seats or {} do
		if seat.connected ~= false and seat.side == side then
			n += 1
		end
	end
	return n
end

--- How many are on the pad (a seat that dropped its connection does not count).
function PadBar.count(snapshot: any): number
	local n = 0
	for _, seat in snapshot.seats do
		if seat.connected ~= false then
			n += 1
		end
	end
	return n
end

--- Whether this pad's global search is on: the server's record, or the host's own press
--- still on its way (and not cancelled since). A press is believed for ActionRetrySeconds.
function PadBar.searching(snapshot: any, press: Press, now: number): boolean
	local retry = M.ActionRetrySeconds
	local cancelling = press.cancelledAt > press.searchAt and now - press.cancelledAt < retry
	if snapshot.search then
		-- An X on its way hides it, unless the search already found its match.
		return snapshot.search.found == true or not cancelling
	end
	return press.searchAt > press.cancelledAt and now - press.searchAt < retry
end

--- The bar for `userId` on `snapshot` (a Waiting table); `dismissed`: the host pressed Play
--- Global's X on this step-on (designer, 2026-10-07: for those who would rather keep
--- waiting), so it stays hidden until they step on again.
function PadBar.view(
	snapshot: any,
	userId: number,
	now: number,
	press: Press,
	dismissed: boolean?
): View
	local count = PadBar.count(snapshot)
	local teamSize = snapshot.teamSize
	local capacity = teamSize * 2
	local isHost = snapshot.hostId == userId
	local searching = PadBar.searching(snapshot, press, now)
	local found = snapshot.search ~= nil and snapshot.search.found == true
	local room = count < capacity
	local view: View = {
		line = if teamSize == 1 then "Waiting" else "WaitingPlayers",
		count = count,
		capacity = capacity,
		isHost = isHost,
		startsIn = nil,
		waited = nil,
		showGlobal = false,
		needsSide = false,
		showCancel = false,
		side = PadBar.sideOf(snapshot, userId),
		sideCount = 0,
		sideFull = false,
		switchable = false,
	}
	local side = view.side
	if side then
		view.sideCount = sideCount(snapshot, side)
		view.sideFull = view.sideCount >= teamSize
		view.switchable = sideCount(snapshot, 3 - side) < teamSize
		-- "Walk across to switch sides" while the other side has room.
		if view.switchable then
			view.line = "SwitchSides"
		end
	end
	if snapshot.startsAt then
		view.line = "Starting"
		view.startsIn = math.max(1, math.ceil(snapshot.startsAt - now))
		return view
	end
	if searching then
		local at = if snapshot.search then snapshot.search.at else press.searchAt
		view.line = if found then "Found" else "Searching"
		view.waited = math.max(0, math.floor(now - at))
		view.showCancel = isHost and not found
		return view
	end
	if not isHost or not room then
		return view
	end
	-- A team table searches as a whole side (MatchEngine.canSearch).
	view.needsSide = count < teamSize
	view.showGlobal = not view.needsSide and not dismissed
	return view
end

--- Whether `userId`'s seat on `snapshot` keeps them busy: they are at it (connected) and it is
--- not a pad still waiting with room (a game, its result, or a full pad about to start). A
--- player waiting on a pad with room wants an opponent: they are free to play.
local function busyAt(snapshot: any, userId: number): boolean
	local seated = false
	for _, seat in snapshot.seats or {} do
		if seat.userId == userId and seat.connected ~= false then
			seated = true
		end
	end
	if not seated then
		return false
	end
	if snapshot.phase ~= "Waiting" or snapshot.startsAt ~= nil then
		return true
	end
	return PadBar.count(snapshot) >= (snapshot.teamSize or 1) * 2
end

--- Whether nobody else in the server is free to play `me` (designer, 2026-10-09): the server
--- holds only them, or every other player is busy at a table (busyAt). `others` are the other
--- players' userIds; `snapshots` every table's latest snapshot by id.
function PadBar.nobodyFree(others: { number }, snapshots: { [any]: any }): boolean
	for _, userId in others do
		local busy = false
		for _, snapshot in snapshots do
			if busyAt(snapshot, userId) then
				busy = true
				break
			end
		end
		if not busy then
			return false
		end
	end
	return true
end

--- Whether the spawn pill shows (designer, 2026-10-07): "Don't want to wait?" and Play Global
--- for a player off the pads in a public lobby server while nobody else is free to play them
--- (nobodyFree: alone, or everyone else busy at a table; designer, 2026-10-09). Never in a
--- private server (people there play with their friends) or during the tutorial. It goes
--- when they press its X, after Config.UI.MatchBar.SpawnPillSeconds, when they step on a pad
--- (the pad's bar takes over) or when someone is free; a search it started keeps it up. In the
--- tutorial's soft part (`soft`: Play Global glows until it is pressed, 4.5 step 14) it shows
--- off the pads whoever is free and for as long as it takes, until its X.
function PadBar.spawnPill(
	args: {
		nobodyFree: boolean,
		publicLobby: boolean,
		tutorial: boolean,
		onPad: boolean,
		dismissed: boolean,
		since: number?, -- when it first showed this session (nil: not yet)
		now: number,
		searching: boolean,
		soft: boolean?,
	}
): boolean
	if args.searching then
		return true
	end
	if not args.publicLobby or args.tutorial or args.onPad or args.dismissed then
		return false
	elseif args.soft or B.SpawnPillAlways then
		return true
	elseif not args.nobodyFree then
		return false
	end
	return args.since == nil or args.now - args.since < B.SpawnPillSeconds
end

--- Whether the spawn pill's X still hides it (SpawnPillAlways): until a match ends after the
--- press (`played` counts the match results heard; `dismissedAt` was the count at the press).
function PadBar.stillDismissed(dismissedAt: number?, played: number): boolean
	if dismissedAt == nil then
		return false
	end
	return not B.SpawnPillAlways or played == dismissedAt
end

--- "0:07": the search's time.
function PadBar.clock(seconds: number): string
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

--- Whether the server sends "<name> needs an opponent!" for a host who just stepped on:
--- the pad has room, no search runs, and their last one is AutoRequestCooldownSeconds old,
--- so stepping off and on again does not flood everyone with popups. Friends in the server
--- or not (designer, 2026-10-09; with a friend here nobody was asked).
function PadBar.autoRequest(args: {
	isHost: boolean,
	count: number,
	capacity: number,
	searching: boolean,
	lastAt: number?,
	now: number,
}): boolean
	if not args.isHost or args.count >= args.capacity or args.searching then
		return false
	end
	return args.lastAt == nil or args.now - args.lastAt >= M.Queue.AutoRequestCooldownSeconds
end

--- Whether a 2v2 or 3v3 pad asks everyone free again (Config.Multiplayer.Queue.TeamPings;
--- designer, 2026-10-26), and why: "Join" when someone just joined and seats are still open,
--- "Reminder" ReminderSeconds after its last ask (or since its wait began, if it never
--- asked) while still short, at most MaxReminders a wait. Nil: no ask.
function PadBar.teamAsk(
	args: {
		teamSize: number,
		count: number,
		capacity: number,
		searching: boolean,
		joined: boolean, -- a player other than the host just stepped on
		lastAt: number?, -- the pad's last ask
		since: number, -- when this wait began
		reminders: number, -- reminders sent this wait
		now: number,
	}
): string?
	local T = M.Queue.TeamPings
	if
		not T.Enabled
		or args.teamSize < 2
		or args.count == 0
		or args.count >= args.capacity
		or args.searching
	then
		return nil
	end
	local last = args.lastAt or args.since
	if args.joined then
		return "Join"
	elseif args.reminders < T.MaxReminders and args.now - last >= T.ReminderSeconds then
		return "Reminder"
	end
	return nil
end

--- Whether a player freed from a table's seat may be seated from its pad again (designer,
--- 2026-10-12: after a match "give them a slight buffer for them to get off but otherwise
--- after like a second or two it should start queuing them again"): `freedAt` is when their
--- seat went while they stood on the pad (nil: nothing to wait for), and they are seated
--- Queue.RejoinGraceSeconds after it if still on.
function PadBar.rejoinReady(freedAt: number?, now: number): boolean
	return freedAt == nil or now - freedAt >= M.Queue.RejoinGraceSeconds
end

return PadBar
