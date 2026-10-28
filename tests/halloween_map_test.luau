--!strict
-- Checks the Haunted Rooftop's rules (src/shared/HalloweenMap/Rules.luau, Config.HalloweenMap;
-- Halloween 2026, hw-map lane): the state the map follows and what each change does, the
-- Pumpkin King's tier, who may get candy, the teleport check, a pickup's answer, the hide list
-- and the decor bounds, and the event light (LightCycle.event).

local H = require("./harness")

-- CIEDE2000 between two sRGB colours (0-255), as ~/Desktop/8ball-refs/halloween/research/
-- agents/cloth_contrast.py computes it.
local function lab(c: { number }): (number, number, number)
	local function f(u: number): number
		u /= 255
		return if u > 0.04045 then ((u + 0.055) / 1.055) ^ 2.4 else u / 12.92
	end
	local r, g, b = f(c[1]), f(c[2]), f(c[3])
	local X = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
	local Y = 0.2126 * r + 0.7152 * g + 0.0722 * b
	local Z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
	local function k(t: number): number
		return if t > 0.008856 then t ^ (1 / 3) else 7.787 * t + 16 / 116
	end
	local fx, fy, fz = k(X), k(Y), k(Z)
	return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)
end

local function deltaE(c1: { number }, c2: { number }): number
	local L1, a1, b1 = lab(c1)
	local L2, a2, b2 = lab(c2)
	local C1, C2 = math.sqrt(a1 * a1 + b1 * b1), math.sqrt(a2 * a2 + b2 * b2)
	local Cb = (C1 + C2) / 2
	local G = 0.5 * (1 - math.sqrt(Cb ^ 7 / (Cb ^ 7 + 25 ^ 7)))
	local a1p, a2p = (1 + G) * a1, (1 + G) * a2
	local C1p, C2p = math.sqrt(a1p * a1p + b1 * b1), math.sqrt(a2p * a2p + b2 * b2)
	local function hue(b: number, a: number): number
		return math.deg(math.atan2(b, a)) % 360
	end
	local h1, h2 = hue(b1, a1p), hue(b2, a2p)
	local dL, dC = L2 - L1, C2p - C1p
	local dh = h2 - h1
	if C1p * C2p == 0 then
		dh = 0
	elseif dh > 180 then
		dh -= 360
	elseif dh < -180 then
		dh += 360
	end
	local dH = 2 * math.sqrt(C1p * C2p) * math.sin(math.rad(dh / 2))
	local Lb, Cbp = (L1 + L2) / 2, (C1p + C2p) / 2
	local hb
	if C1p * C2p == 0 then
		hb = h1 + h2
	elseif math.abs(h1 - h2) <= 180 then
		hb = (h1 + h2) / 2
	elseif h1 + h2 < 360 then
		hb = (h1 + h2 + 360) / 2
	else
		hb = (h1 + h2 - 360) / 2
	end
	local T = 1
		- 0.17 * math.cos(math.rad(hb - 30))
		+ 0.24 * math.cos(math.rad(2 * hb))
		+ 0.32 * math.cos(math.rad(3 * hb + 6))
		- 0.2 * math.cos(math.rad(4 * hb - 63))
	local dth = 30 * math.exp(-((hb - 275) / 25) ^ 2)
	local RC = 2 * math.sqrt(Cbp ^ 7 / (Cbp ^ 7 + 25 ^ 7))
	local SL = 1 + 0.015 * (Lb - 50) ^ 2 / math.sqrt(20 + (Lb - 50) ^ 2)
	local SC, SH = 1 + 0.045 * Cbp, 1 + 0.015 * Cbp * T
	local RT = -math.sin(math.rad(2 * dth)) * RC
	return math.sqrt((dL / SL) ^ 2 + (dC / SC) ^ 2 + (dH / SH) ^ 2 + RT * (dC / SC) * (dH / SH))
end

local function who(over: { [string]: any }?): any
	local w: { [string]: any } = {
		isLobby = true,
		live = true,
		hwOn = true,
		freecam = false,
		inMatch = false,
		sitting = false,
		movedStuds = 20,
	}
	for k, v in over or {} do
		w[k] = v
	end
	return w
end

return {
	["the map follows the event, and a Studio force only in Studio"] = function()
		local R = H.require("HalloweenMap.Rules")
		H.expect(R.mapState(nil, nil, false) == "Before", "no event module: today's map")
		H.expect(R.mapState("Live", nil, false) == "Live", "Live from the clock")
		H.expect(R.mapState("Live", "Ended", true) == "Ended", "a Studio force wins")
		H.expect(R.mapState("Live", "Ended", false) == "Live", "never forced outside Studio")
		H.expect(R.mapState("Before", "Nonsense", true) == "Before", "an unknown force is ignored")
		H.expect(R.mapState("Weird", nil, false) == "Before", "an unknown state is today's map")
	end,

	["each change of state preloads, turns on or turns off exactly once"] = function()
		local R = H.require("HalloweenMap.Rules")
		local function is(a: any, preload: boolean, on: boolean, off: boolean, what: string)
			H.expect(a.preload == preload and a.on == on and a.off == off, what)
		end
		is(R.actions("Before", "Countdown"), true, false, false, "Countdown only preloads")
		is(R.actions("Countdown", "Live"), false, true, false, "into Live: all on")
		is(R.actions(nil, "Live"), true, true, false, "a boot during Live: preload and on")
		is(R.actions("Before", "Live"), true, true, false, "straight to Live")
		is(R.actions("Live", "Live"), false, false, false, "Live twice changes nothing")
		is(R.actions("Live", "Ended"), false, false, true, "Ended: all off")
		is(R.actions("Live", "Before"), false, false, true, "a force back to Before: all off")
		is(R.actions("Ended", "Live"), true, true, false, "a force cycle turns on again")
		is(R.actions(nil, "Before"), false, false, false, "a boot before: nothing")
		is(R.actions("Ended", "Ended"), false, false, false, "Ended twice: nothing")
	end,

	["the King plays two tiers above, at least Gold, at most Reyes"] = function()
		local R = H.require("HalloweenMap.Rules")
		local want = {
			Bronze = "Gold",
			Silver = "Platinum",
			Gold = "Diamond",
			Platinum = "Expert",
			Diamond = "Veteran",
			Expert = "Master",
			Veteran = "Grandmaster",
			Master = "Reyes",
			Grandmaster = "Reyes",
			Reyes = "Reyes",
		}
		local tiers = H.require("Config").Ranks.Tiers
		H.expect(#tiers == 10, "ten rank tiers")
		for _, tier in tiers do
			-- A row stepped down after bot_duel (logged OVERRULED) may be one tier lower.
			local got = R.kingTier(tier)
			local gi, wi = table.find(tiers, got), table.find(tiers, want[tier])
			H.expect(gi ~= nil and wi ~= nil and gi <= wi and gi >= wi - 1, tier .. " -> " .. got)
			-- Never below the player's own tier, but at the top (no tier above Reyes to fall from).
			local pi = table.find(tiers, tier) :: number
			H.expect(gi :: number >= pi or pi == #tiers, tier .. ": never below")
		end
		H.expect(R.kingTier(nil) == R.kingTier("Bronze"), "no rank counts as Bronze")
		H.expect(R.kingTier("Unranked") == R.kingTier("Bronze"), "Unranked counts as Bronze")
	end,

	["a King match pays on the King's real loss, whatever the table says"] = function()
		local R = H.require("HalloweenMap.Rules")
		-- Studio 2026-10-28: the table lets the player go as the result lands, so a win must
		-- not depend on them still being seated (it logged "Left" and paid nothing).
		H.expect(R.kingOutcome({ won = false, reason = "LegalEight" }, true) == "Won", "his loss")
		H.expect(
			R.kingOutcome({ won = false, reason = "EarlyEight" }, true) == "Won",
			"his foul on 8"
		)
		H.expect(R.kingOutcome({ won = true, reason = "LegalEight" }, true) == "Lost", "his win")
		H.expect(R.kingOutcome({ won = true, reason = "Forfeit" }, true) == "Lost", "walked away")
		H.expect(
			R.kingOutcome({ won = false, reason = "EmptyTeam" }, true) == "Left",
			"he vanished"
		)
		H.expect(R.kingOutcome({ won = false }, true) == "Left", "no result: never paid")
		H.expect(R.kingOutcome(nil, true) == "Left", "no info: never paid")
		H.expect(
			R.kingOutcome({ won = false, reason = "LegalEight" }, false) == "Gone",
			"left the server"
		)
	end,

	["candy goes only to a free, active lobby player with HwOn"] = function()
		local R = H.require("HalloweenMap.Rules")
		H.expect(R.eligible(who()) == true, "an active lobby player")
		local cases: { [string]: { [string]: any } } = {
			NotOn = { hwOn = false },
			Freecam = { freecam = true },
			InMatch = { inMatch = true },
			Sitting = { sitting = true },
			Idle = { movedStuds = 1 },
			Arena = { isLobby = false },
			NotLive = { live = false },
		}
		for reason, over in cases do
			local ok, why = R.eligible(who(over))
			H.expect(ok == false and why == reason, reason)
		end
		local missing = who()
		missing.hwOn = nil
		local ok, why = R.eligible(missing)
		H.expect(ok == false and why == "NotOn", "HwOn missing: nothing")
		ok, why = R.eligible(who({ hwOn = "true" }))
		H.expect(ok == false and why == "NotOn", "only a real true counts")
	end,

	["a jump past TeleportStuds in one tick is a teleport"] = function()
		local R = H.require("HalloweenMap.Rules")
		local C = H.require("Config").HalloweenMap.Candy
		H.near(C.TeleportStuds, 20.8 * C.PickupTickSeconds * 3, 0.05, "three ticks of walking")
		H.expect(R.teleported({ 0, 0, 0 }, { 4, 0, 0 }) == false, "a walk")
		H.expect(R.teleported({ 0, 0, 0 }, { 0, 0, 13 }) == true, "a teleport")
		H.expect(R.teleported(nil, { 0, 0, 0 }) == true, "no last position: a fresh arrival")
	end,

	["only the hour cap shows the bag-full note and pauses targeting"] = function()
		local R = H.require("HalloweenMap.Rules")
		local now = 1793230000 -- 23:26:40 UTC on Oct 28
		local ok = R.pickupOutcome(true, nil, now)
		H.expect(ok.take and not ok.note and ok.pauseUntil == nil, "picked up")
		local cap = R.pickupOutcome(false, "Cap", now)
		H.expect(not cap.take and cap.note, "Cap: left for others, the note")
		H.expect(cap.pauseUntil == 1793232000, "paused to the next UTC hour (00:00)")
		for _, reason in { "NotLive", "NotLoaded", "Other" } do
			local o = R.pickupOutcome(false, reason, now)
			H.expect(not o.take and not o.note and o.pauseUntil == nil, reason .. ": nothing")
		end
		local none = R.pickupOutcome(false, nil, now)
		H.expect(not none.take and not none.note, "nil: nothing")
		H.expect(R.nextHour(3600) == 7200, "on the hour: the next one")
	end,

	["the props never hide what the portals already hide"] = function()
		local R = H.require("HalloweenMap.Rules")
		local Config = H.require("Config")
		local names = { "Palm_1", "Palm_18", "PalmPlanter_1", "palm_planter_01", "PlanterBed_3" }
		for _, name in Config.Portals.Replaces do
			table.insert(names, name)
		end
		local hidden = R.hideList(names, { "^Palm_%d+$", "^PlanterBed_%d+$", "^planter_bed_%d+$" })
		local set: { [string]: boolean } = {}
		for _, name in hidden do
			set[name] = true
		end
		for _, name in Config.Portals.Replaces do
			H.expect(not set[name], name .. " stays the portals'")
		end
		H.expect(set.Palm_1 and set.Palm_18 and set.PlanterBed_3, "the trees and a bed hide")
		H.expect(not set.PalmPlanter_1 and not set.palm_planter_01, "the pots and collision stay")
		local configured = R.hideList(Config.Portals.Replaces, Config.HalloweenMap.Props.Hide)
		H.expect(#configured == 0, "Config's own Hide list never takes a portal's")
	end,

	["decor must sit inside the body's footprint and under the rail top"] = function()
		local R = H.require("HalloweenMap.Rules")
		local body = { cx = 0, cy = 1.5, cz = 0, sx = 10, sy = 3, sz = 5 }
		local function box(cx: number, cy: number, cz: number, sx: number, sy: number, sz: number)
			return { cx = cx, cy = cy, cz = cz, sx = sx, sy = sy, sz = sz }
		end
		H.expect(R.decorInside(box(0, 1, 0, 2, 0.5, 1), body, 3.4), "inside")
		H.expect(R.decorInside(box(4, 1, 0, 2, 0.5, 1), body, 3.4), "touching the edge")
		H.expect(
			R.decorInside(box(4.0004, 1, 0, 2, 0.5, 1), body, 3.4),
			"a float's hair past the edge"
		)
		H.expect(
			not R.decorInside(box(4.003, 1, 0, 2, 0.5, 1), body, 3.4),
			"a few thousandths past"
		)
		H.expect(not R.decorInside(box(4.5, 1, 0, 2, 0.5, 1), body, 3.4), "past the end")
		H.expect(not R.decorInside(box(0, 1, 2.6, 1, 0.5, 0.2), body, 3.4), "past the side")
		H.expect(not R.decorInside(box(0, 3.3, 0, 1, 0.5, 1), body, 3.4), "above the rail top")
	end,

	["every decor kit keeps to its part and triangle budget"] = function()
		local HM = H.require("Config").HalloweenMap
		local D = HM.Decor
		for size, row in HM.Tables.ByTeamSize do
			H.expect(
				D.Kits[row.Kit] ~= nil,
				("team size %d's kit %s is in Decor.Kits"):format(size, row.Kit)
			)
		end
		for name, kit in D.Kits do
			-- Every piece is one part (the plate, and each prop's one MeshPart).
			local parts, tris = 0, 0
			if kit.Underglow then
				parts += 1
				tris += D.Triangles.Underglow
			end
			if kit.Trim then
				H.expect(
					HM.Assets.Origins.Trim ~= nil,
					"the trim ring is one of the event's meshes"
				)
				parts += 1
				tris += D.Triangles.Trim
			end
			for _, setName in kit.Sets do
				local set = D.Sets[setName]
				H.expect(set ~= nil, ("kit %s's set %s is in Decor.Sets"):format(name, setName))
				for _, row in set do
					H.expect(
						HM.Assets.Origins[row.Prop] ~= nil and D.Triangles[row.Prop] ~= nil,
						("%s is one of the event's meshes, with its triangles counted"):format(
							row.Prop
						)
					)
					parts += 1
					tris += D.Triangles[row.Prop]
				end
			end
			H.expect(parts <= D.MaxPartsPerTable, ("kit %s: %d parts"):format(name, parts))
			H.expect(tris <= D.MaxTrianglesPerTable, ("kit %s: %d triangles"):format(name, tris))
		end
	end,

	["a dead tree leans toward the roof's middle, never over the railing"] = function()
		local R = H.require("HalloweenMap.Rules")
		local lean = { 1.53, -2.91 } -- the DeadTree mesh's crown offset at no turn
		for i, spot in
			{ { 86, 31.5 }, { -86, 75.25 }, { -65, -74.35 }, { 87, -88.25 }, { 0.5, -60 } }
		do
			for _, jitter in { 0, 25 } do
				local yaw = R.treeYaw(spot[1], spot[2], lean[1], lean[2], jitter, i * 7)
				-- CFrame.Angles(0, yaw, 0) applied to the lean (x, z)
				local x = lean[1] * math.cos(yaw) + lean[2] * math.sin(yaw)
				local z = -lean[1] * math.sin(yaw) + lean[2] * math.cos(yaw)
				local tx, tz = -spot[1], -spot[2]
				local cos = (x * tx + z * tz)
					/ (math.sqrt(x * x + z * z) * math.sqrt(tx * tx + tz * tz))
				H.expect(
					cos >= math.cos(math.rad(jitter)) - 1e-9,
					("spot %d leans inward (jitter %d)"):format(i, jitter)
				)
			end
		end
	end,

	["the rooftop's props are the event's meshes and keep off the tables' areas"] = function()
		local Config = H.require("Config")
		local Placement = H.require("Placement")
		local P = Config.HalloweenMap.Props
		local origins = Config.HalloweenMap.Assets.Origins
		H.expect(origins[P.Trees.Prop] ~= nil, "the dead tree is one of the event's meshes")
		H.expect(origins[P.StrandProp] ~= nil, "the string of lights is one of the event's meshes")
		for _, row in P.Planters.Dressings do
			H.expect(origins[row.Prop] ~= nil, row.Prop .. " is one of the event's meshes")
		end
		local room = Config.Multiplayer.Fence.RoomStuds
		for i, row in P.Place do
			H.expect(origins[row.Prop] ~= nil, row.Prop .. " is one of the event's meshes")
			if row.At[2] < 8 then -- on the floor (overhead pieces hang 24 up)
				local _, out = Placement.nearestArea(row.At[1], row.At[3])
				H.expect(
					out > room + 1,
					("placement %d (%s) is clear of every table's area"):format(i, row.Prop)
				)
			end
		end
		for i, row in P.Strands do
			H.expect(row.From[2] >= 20 and row.To[2] >= 20, ("strand %d hangs overhead"):format(i))
		end
	end,

	["the King's challenge is on only with his throne"] = function()
		-- His prompt is on the throne: a challenge without one could never be met, while core's
		-- quest (it reads HM.Enabled and HM.Boss.Enabled) would still ask for it.
		local HM = H.require("Config").HalloweenMap
		H.expect(not HM.Boss.Enabled or HM.Throne.Enabled, "Boss.Enabled needs Throne.Enabled")
	end,

	["the cloths keep their raw contrast with every ball"] = function()
		local Config = H.require("Config")
		local HM = Config.HalloweenMap
		for size, row in HM.Tables.ByTeamSize do
			local worst, ball = math.huge, -1
			for n, colour in Config.Balls.Colors do
				local d = deltaE(row.Cloth, colour)
				if d < worst then
					worst, ball = d, n
				end
			end
			H.expect(
				worst >= HM.Tables.MinDeltaE,
				("%dv%d cloth: ball %d at %.1f"):format(size, size, ball, worst)
			)
			-- Never an orange cloth: balls 5 and 13 vanish on it.
			local r, g, b = row.Cloth[1], row.Cloth[2], row.Cloth[3]
			H.expect(not (r > 180 and g > 60 and g < 170 and b < 80), "an orange cloth")
		end
		-- The maths matches the agent report's numbers for PLAN's tints.
		H.near(deltaE({ 185, 90, 230 }, Config.Balls.Colors[4]), 23.2, 0.1, "orchid vs ball 4")
	end,

	["each table's event look comes from its mode"] = function()
		local R = H.require("HalloweenMap.Rules")
		local Config = H.require("Config")
		for _, row in Config.Hub.Tables do
			local size, look = R.tableLook(row.id)
			H.expect(size == row.teamSize, "table " .. row.id)
			H.expect(look == Config.HalloweenMap.Tables.ByTeamSize[size], "its look")
		end
		H.expect(R.clock(872) == "14:32" and R.clock(-3) == "0:00", "the prompt's clock")
		H.near(R.spawnDelay(0.5), Config.HalloweenMap.Candy.SpawnEverySeconds, 1e-9, "pace")
	end,

	["two ons at once build the throne once (a server starting while Live)"] = function()
		-- Bootstrap's thread and EventMap's pass both turn the throne on while the first build
		-- waits on the meshes (the coordinator's 12:16 blocker: two thrones). Once parks the
		-- second caller until the first build ends.
		local Once = H.require("HalloweenMap.Once")
		local builds = 0
		local once = Once.new(function(): boolean
			builds += 1
			coroutine.yield() -- the mesh wait
			return true
		end)
		local answers = {}
		local a = coroutine.create(function()
			answers.a = once:run()
		end)
		local b = coroutine.create(function()
			answers.b = once:run()
		end)
		coroutine.resume(a) -- starts the build, waits on the meshes
		coroutine.resume(b) -- finds it building: waits for it
		H.expect(builds == 1, "the second on does not build")
		H.expect(coroutine.status(b) == "suspended", "the second on waits for the build")
		coroutine.resume(a) -- the meshes are in: the build ends and wakes the waiting on
		H.expect(coroutine.status(a) == "dead" and coroutine.status(b) == "dead", "both ons end")
		H.expect(answers.a == true and answers.b == true, "both see it built")
		H.expect(once:run() == true and builds == 1, "a later on builds nothing")
	end,

	["a build that found no meshes is tried again, and an error reaches its caller"] = function()
		local Once = H.require("HalloweenMap.Once")
		local tries = 0
		local once = Once.new(function(): boolean
			tries += 1
			return tries >= 2
		end)
		H.expect(once:run() == false, "no meshes: not built")
		H.expect(once:run() == true and tries == 2, "the next on builds it")
		local failing = Once.new(function(): boolean
			error("boom", 0)
		end)
		local ok, err = pcall(function()
			failing:run()
		end)
		H.expect(not ok and err == "boom", "the error is passed on")
		H.expect(failing.building == false, "a failed build does not block the next")
	end,

	["the timed King visits at :15 and :45 for 12 minutes, never in the Candy Rush"] = function()
		local R = H.require("HalloweenMap.Rules")
		local Config = H.require("Config")
		local T = Config.HalloweenMap.Boss.Timed
		H.expect(T.EverySeconds == 1800 and T.OffsetSeconds == 900, "UTC :15 and :45")
		H.expect(T.StaySeconds == 720, "12 minutes")
		H.expect(T.StaySeconds < T.EverySeconds, "he leaves before the next visit")
		local hour = 1793228400 -- Wed Oct 28 23:00 UTC (StartsAt, an hour mark)
		local s, e = R.kingWindow(hour)
		H.expect(s == hour + 900 and e == hour + 1620, "at :00 the next visit is :15-:27")
		H.expect(not R.kingHere(hour), "not here at :00")
		s, e = R.kingWindow(hour + 900)
		H.expect(s == hour + 900 and R.kingHere(hour + 900), "here from :15:00")
		H.expect(R.kingHere(hour + 1619.5) and not R.kingHere(hour + 1620), "gone at :27:00")
		s = R.kingWindow(hour + 1620)
		H.expect(s == hour + 2700, "after :27 the next is :45")
		s, e = R.kingWindow(hour + 3000)
		H.expect(s == hour + 2700 and e == hour + 3420, "here :45-:57")
		H.expect(not R.kingHere(hour + 3420), "gone at :57:00")
		H.expect(R.kingNext(hour + 1000) == hour + 2700, "next after this visit")
		H.expect(R.kingNext(hour + 2000) == hour + 2700, "next while away")
		H.expect(
			R.minuteText(hour + 2700) == ":45" and R.minuteText(hour + 900) == ":15",
			"minutes"
		)
		-- Every second of every visit is clear of the Rush (UTC minutes 0 .. Rush.Minutes - 1).
		local rush = Config.Halloween.Rush and Config.Halloween.Rush.Minutes or 10
		for t = hour, hour + 7200, 30 do
			if R.kingHere(t) then
				H.expect(math.floor(t / 60) % 60 >= rush, "a visit in the Rush at " .. t)
			end
		end
	end,

	["the King's line keeps its order, joins once and drops"] = function()
		local R = H.require("HalloweenMap.Rules")
		local line = {}
		H.expect(R.lineJoin(line, 11) == 1 and R.lineJoin(line, 22) == 2, "first and second")
		H.expect(R.lineJoin(line, 11) == 1 and #line == 2, "joining twice keeps the place")
		H.expect(R.lineJoin(line, 33) == 3, "third")
		H.expect(R.lineDrop(line, 22) and table.find(line, 33) == 2, "the rest move up")
		H.expect(not R.lineDrop(line, 99), "dropping a stranger does nothing")
		H.expect(line[1] == 11, "the first in line is next")
	end,

	["a winner of this visit waits behind everyone who hasn't won"] = function()
		local R = H.require("HalloweenMap.Rules")
		local beaten = { [11] = true, [44] = true } -- 11 and 44 already won this visit
		local line = {}
		H.expect(R.lineJoin(line, 11, beaten) == 1, "a winner alone is first")
		H.expect(R.lineJoin(line, 22, beaten) == 1, "someone who hasn't won goes ahead of him")
		H.expect(R.lineJoin(line, 33, beaten) == 2, "and the next one behind them, still ahead")
		H.expect(R.lineJoin(line, 44, beaten) == 4, "a second winner at the very back")
		H.expect(table.concat(line, ",") == "22,33,11,44", "unpaid first in order, then winners")
		H.expect(R.lineJoin(line, 22, beaten) == 1 and #line == 4, "joining again keeps the place")
		H.expect(R.linePlace(line, 55, beaten) == 3 and #line == 4, "linePlace only looks")
		H.expect(R.linePlace(line, 55) == 5, "with no winners known it is first come first served")
		local everyone = function(_id: number): boolean
			return true
		end
		H.expect(R.lineNext(line, beaten, everyone) == 22, "the first who hasn't won plays next")
		local busy = { [22] = true, [33] = true }
		local free = function(id: number): boolean
			return not busy[id]
		end
		H.expect(
			R.lineNext(line, beaten, free) == nil,
			"no winner gets a table while anyone who hasn't won waits, even in another match"
		)
		R.lineDrop(line, 22)
		R.lineDrop(line, 33)
		H.expect(R.lineNext(line, beaten, free) == 11, "only winners left: the first of them")
		H.expect(R.lineNext({}, beaten, everyone) == nil, "an empty line seats nobody")
	end,

	["the timed King's fixed notices name the minutes his schedule uses"] = function()
		-- The queue notices can't be formatted, so they spell ":15 and :45"; they must follow
		-- Boss.Timed if it ever moves.
		local Strings = H.require("Strings")
		local Config = H.require("Config")
		local R = H.require("HalloweenMap.Rules")
		local T = Config.HalloweenMap.Boss.Timed
		local first = R.minuteText(T.OffsetSeconds)
		local second = R.minuteText(T.OffsetSeconds + T.EverySeconds)
		H.expect(3600 // T.EverySeconds == 2, "two visits an hour, as the notices say")
		for _, key in { "KingLeft", "KingAway" } do
			local text = Strings.GlobalQueue.Failed[key]
			H.expect(
				text:find(first .. " and " .. second, 1, true) ~= nil,
				key .. " names " .. first .. " and " .. second
			)
		end
	end,

	["the King's queue notices stay short enough for the queue card"] = function()
		-- The card is UI.Queue.StatusWidth px at every screen size (no UIScale), 20 px of it padding.
		-- Measured in Studio (TextService, FredokaOne 18 px): 43 characters is the longest King
		-- line, 311 px, which shows at about 17 px; longer ones shrink further.
		local Strings = H.require("Strings")
		local Config = H.require("Config")
		H.expect(Config.UI.Queue.StatusWidth == 320, "the card these lengths were measured for")
		local keys = { "KingBusy", "KingNoTable", "KingCooldown", "KingNotNow" }
		for _, key in { "KingLined", "KingLineLeft", "KingLeft", "KingAway", "KingLinedBeaten" } do
			table.insert(keys, key)
		end
		for _, key in keys do
			local text = Strings.GlobalQueue.Failed[key]
			H.expect(type(text) == "string" and utf8.len(text) <= 43, key .. " fits the card")
		end
	end,
}
