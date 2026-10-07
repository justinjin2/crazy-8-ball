--!strict
-- PadBar: what the matchmaking bar above the hotbar says (designer, 2026-10-07: one option
-- only). Pure: the table's snapshot and the times come in, the bar's state goes out, so a
-- Lune test checks it and the client (MatchBar) only draws it.
--
-- Everyone on a waiting pad sees the bar: the mode, how many are on, and "Waiting for
-- opponent..." (or players), "Starting in 3" once full. The host alone gets more: after
-- Config.UI.MatchBar.PromptAloneSeconds on the pad (PromptFriendsSeconds with a Roblox friend
-- in the server) "Don't want to wait?" and Play Global, then the search's time and an X.
--
-- The server also asks it whether to send the "<name> needs an opponent!" popup itself when
-- a host steps on (autoRequest): only with no friend in the server, once per step-on.
local Config = require(script.Parent.Parent.Config)

local B = Config.UI.MatchBar
local M = Config.Multiplayer
local PadBar = {}

export type Press = {
	searchAt: number, -- this host's last Play Global, before the server's answer
	cancelledAt: number, -- and their last X
}

export type View = {
	line: string, -- "Waiting", "WaitingPlayers", "Starting", "Searching" or "Found"
	count: number, -- on the pad
	capacity: number, -- both teams
	isHost: boolean,
	startsIn: number?, -- whole seconds, while the line is Starting
	waited: number?, -- whole seconds searched, while the line is Searching or Found
	showGlobal: boolean, -- "Don't want to wait?" and Play Global
	needsSide: boolean, -- a team table's host before a whole side is on: no Play Global yet
	showCancel: boolean, -- the red X: the host's own search runs
}

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

--- How long the host waits on the pad before Play Global is offered.
function PadBar.promptAfter(friendHere: boolean): number
	return if friendHere then B.PromptFriendsSeconds else B.PromptAloneSeconds
end

--- The bar for `userId` on `snapshot` (a Waiting table), `since` being when they stepped on.
function PadBar.view(
	snapshot: any,
	userId: number,
	now: number,
	since: number,
	friendHere: boolean,
	press: Press
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
	}
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
	view.showGlobal = not view.needsSide and now - since >= PadBar.promptAfter(friendHere)
	return view
end

--- "0:07": the search's time.
function PadBar.clock(seconds: number): string
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

--- Whether the server sends "<name> needs an opponent!" for a host who just stepped on:
--- the pad has room, no friend of theirs is in the server (friends are assumed to come
--- over), no search runs, and their last one is AutoRequestCooldownSeconds old, so stepping
--- off and on again does not flood everyone with popups.
function PadBar.autoRequest(args: {
	isHost: boolean,
	count: number,
	capacity: number,
	friendHere: boolean,
	searching: boolean,
	lastAt: number?,
	now: number,
}): boolean
	if not args.isHost or args.count >= args.capacity or args.friendHere or args.searching then
		return false
	end
	return args.lastAt == nil or args.now - args.lastAt >= M.Queue.AutoRequestCooldownSeconds
end

return PadBar
