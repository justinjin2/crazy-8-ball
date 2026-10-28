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
		H.expect(not R.decorInside(box(4.5, 1, 0, 2, 0.5, 1), body, 3.4), "past the end")
		H.expect(not R.decorInside(box(0, 1, 2.6, 1, 0.5, 0.2), body, 3.4), "past the side")
		H.expect(not R.decorInside(box(0, 3.3, 0, 1, 0.5, 1), body, 3.4), "above the rail top")
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
}
