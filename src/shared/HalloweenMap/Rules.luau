--!strict
-- HalloweenMap.Rules (Halloween 2026, hw-map lane): the Haunted Rooftop's decisions as pure
-- functions (no Instances, no clock of its own), so Lune tests every one: which state the map
-- follows, what a state change does, the Pumpkin King's tier, who may get candy, the teleport
-- check, what a pickup's answer means, what the props may hide and where a table's decor may
-- go. EventMap, BossService, CandyDrop and MapClient call these; Config.HalloweenMap holds
-- every number.

local Config = require(script.Parent.Parent.Config)

local HM = Config.HalloweenMap

local Rules = {}

export type State = "Before" | "Countdown" | "Live" | "Ended"

local STATES: { [string]: boolean } = { Before = true, Countdown = true, Live = true, Ended = true }

--- The state the map follows: core's Event.state (nil while core's module is missing: the
--- map stays today's), or in Studio only a forced state name (Config's ForceAttribute).
function Rules.mapState(eventState: string?, forced: any, isStudio: boolean): State
	if isStudio and type(forced) == "string" and STATES[forced] then
		return forced :: State
	end
	if type(eventState) == "string" and STATES[eventState] then
		return eventState :: State
	end
	return "Before"
end

export type Actions = { preload: boolean, on: boolean, off: boolean }

--- What a change of state does: preload the Night sky and the props' meshes (Countdown, or
--- straight to Live), turn everything on (into Live) or off (out of Live). The same state twice
--- does nothing, so a repeat is harmless.
function Rules.actions(from: State?, to: State): Actions
	local wasLive = from == "Live"
	local isLive = to == "Live"
	return {
		-- (Countdown already preloaded what Live shows)
		preload = from ~= to and from ~= "Countdown" and (to == "Countdown" or isLive),
		on = isLive and not wasLive,
		off = wasLive and not isLive,
	}
end

--- The light a client uses: the event's Night (LightCycle.event) only while Live and the Night
--- part is switched on.
function Rules.nightOn(state: State?): boolean
	return HM.Enabled and HM.Night.Enabled and state == "Live"
end

--- The Pumpkin King's tier for a player's rank tier (nil, "Unranked" or anything unknown counts
--- as Bronze): Config's TierFor row, else two tiers above at least MinTier, at most the top.
function Rules.kingTier(playerTier: string?): string
	local tiers = Config.Ranks.Tiers
	local index: { [string]: number } = {}
	for i, name in tiers do
		index[name] = i
	end
	local own = if playerTier and index[playerTier] then playerTier else tiers[1]
	local row = HM.Boss.TierFor[own]
	if row and index[row] then
		return row
	end
	local i = math.max(index[own] + HM.Boss.TiersAbove, index[HM.Boss.MinTier] or 1)
	return tiers[math.min(i, #tiers)]
end

--- The names under workspace.Map the props hide while Live: those matching a Hide pattern,
--- never one the portals already hide (Config.Portals.Replaces: their client owns those).
function Rules.hideList(names: { string }, patterns: { string }): { string }
	local portal: { [string]: boolean } = {}
	for _, name in Config.Portals.Replaces do
		portal[name] = true
	end
	local out: { string } = {}
	for _, name in names do
		if not portal[name] then
			for _, pattern in patterns do
				if name:match(pattern) then
					table.insert(out, name)
					break
				end
			end
		end
	end
	return out
end

export type Box = { cx: number, cy: number, cz: number, sx: number, sy: number, sz: number }

--- A decor part (its box in the table's own space: centre and size, studs) may go on a table
--- only inside the body's footprint (X and Z) with its top below the rail top (railTopY, the
--- same space). Touching the edge counts as inside, give or take a thousandth of a stud (the
--- boxes come from float32 world CFrames tens of studs from the origin).
function Rules.decorInside(part: Box, body: Box, railTopY: number): boolean
	local eps = 1e-3
	local function within(c: number, s: number, bc: number, bs: number): boolean
		return c - s / 2 >= bc - bs / 2 - eps and c + s / 2 <= bc + bs / 2 + eps
	end
	return within(part.cx, part.sx, body.cx, body.sx)
		and within(part.cz, part.sz, body.cz, body.sz)
		and part.cy + part.sy / 2 <= railTopY + eps
end

export type Who = {
	isLobby: boolean,
	live: boolean,
	hwOn: any, -- core's player attribute: only true counts
	freecam: boolean,
	inMatch: boolean, -- Tables.tableOf(p) ~= nil (roaming or not)
	sitting: boolean, -- Humanoid.SeatPart
	movedStuds: number, -- how far the root moved in the last Candy.IdleSeconds
}

--- May this player be targeted by a candy drop and pick one up? (true, or false and why)
function Rules.eligible(who: Who): (boolean, string?)
	if not who.isLobby then
		return false, "Arena"
	elseif not who.live then
		return false, "NotLive"
	elseif who.hwOn ~= true then
		return false, "NotOn"
	elseif who.freecam then
		return false, "Freecam"
	elseif who.inMatch then
		return false, "InMatch"
	elseif who.sitting then
		return false, "Sitting"
	elseif who.movedStuds < HM.Candy.IdleStuds then
		return false, "Idle"
	end
	return true, nil
end

--- Did the root jump more than Candy.TeleportStuds since the last pickup tick (a teleport: a
--- turn's move, a portal)? Positions as {x, y, z}.
function Rules.teleported(last: { number }?, now: { number }): boolean
	if last == nil then
		return true -- no position yet: treat it as a fresh arrival (the grace applies)
	end
	local dx, dy, dz = now[1] - last[1], now[2] - last[2], now[3] - last[3]
	return math.sqrt(dx * dx + dy * dy + dz * dz) > HM.Candy.TeleportStuds
end

--- The next UTC hour's start (unix seconds) after now.
function Rules.nextHour(now: number): number
	return (math.floor(now / 3600) + 1) * 3600
end

export type Pickup = { take: boolean, note: boolean, pauseUntil: number? }

--- What CandyService.pickup's answer means for the candy and the player: ok takes the candy;
--- "Cap" (core's hour cap) leaves it for others, shows the bag-full note and stops targeting
--- the player until the next UTC hour; anything else ("NotLive", "NotLoaded", nil) leaves it
--- and shows nothing (tried again on a later tick).
function Rules.pickupOutcome(ok: boolean, reason: string?, now: number): Pickup
	if ok then
		return { take = true, note = false, pauseUntil = nil }
	elseif reason == "Cap" then
		return { take = false, note = true, pauseUntil = Rules.nextHour(now) }
	end
	return { take = false, note = false, pauseUntil = nil }
end

--- Seconds to the next candy for a player, from a random number in [0, 1).
function Rules.spawnDelay(r: number): number
	local C = HM.Candy
	return math.max(1, C.SpawnEverySeconds + (r * 2 - 1) * C.JitterSeconds)
end

--- The mode of a table by its id (Config.Hub.Tables' teamSize; 1 if not listed) and the event
--- look for it (Tables.ByTeamSize).
function Rules.tableLook(tableId: number): (number, { Cloth: { number }, Kit: string })
	local size = 1
	for _, row in Config.Hub.Tables do
		if row.id == tableId then
			size = row.teamSize
			break
		end
	end
	local look = HM.Tables.ByTeamSize[size] or HM.Tables.ByTeamSize[1]
	return size, look
end

--- A King match's end for its challenger, from BotService.matchEnded's info (won: the King's
--- side won; reason: the result's). "Won": the King lost a real game (a player who walks away
--- forfeits, so the King wins that one); "Lost": the King won; "Left": no real result (the
--- King's side emptied, or no info); "Gone": the player left the server. The table is not
--- asked: it lets the player go as the result lands, before the bot sees it.
function Rules.kingOutcome(info: any, here: boolean): "Won" | "Lost" | "Left" | "Gone"
	if not here then
		return "Gone"
	elseif type(info) ~= "table" or info.reason == nil or info.reason == "EmptyTeam" then
		return "Left"
	elseif info.won then
		return "Lost"
	end
	return "Won"
end

--- "m:ss" for a countdown (the King's prompt while he rests); never negative.
function Rules.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(s // 60, s % 60)
end

return Rules
