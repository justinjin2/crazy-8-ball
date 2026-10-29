--!strict
-- The Pumpkin King (king lane, Halloween 2026): his cloth cape (Config.HalloweenMap.King.Cloth,
-- KingCape on the client: its switch, its part budget, numbers that keep it stable) and his
-- arrival (Config.HalloweenMap.Boss.Entrance, HalloweenMap/KingScene: the rise's timing, the
-- cutscene's camera, who gets it and what ends it).

local H = require("./harness")

return {
	["the cloth cape has a switch and stays within its part budget"] = function()
		local Config = H.require("Config")
		local KL = Config.HalloweenMap.King
		local C = KL.Cloth
		H.expect(type(C.Enabled) == "boolean", "Cloth.Enabled is a boolean (off: the old cape)")
		H.expect(type(KL.Cape) == "table" and #KL.Cape == 3, "King.Cape is still the cape's colour")
		H.expect(C.Rows * 2 + 1 == 17, "17 parts a King (two a row and the collar)")
		H.expect(C.MaxCapes <= 4, "at most 4 capes at once")
		H.expect(
			C.MaxCapes >= 1 + Config.HalloweenMap.Boss.MaxAtOnce,
			"the throne King and every table King can wear one"
		)
		H.expect(
			type(C.Tag) == "string" and type(C.Anchor) == "string",
			"the tag and the anchor's name"
		)
	end,

	["the cloth's numbers keep it stable and off his legs"] = function()
		local C = H.require("Config").HalloweenMap.King.Cloth
		H.expect(C.Damping > 0 and C.Damping < 1, "damped, never frozen")
		H.expect(C.Bend > 0 and C.Bend < 0.5, "bends, never a plank")
		H.expect(C.FtlDamping > 0 and C.FtlDamping <= 1, "no whip from the length fix")
		H.expect(
			C.StepSeconds > 0 and C.StepSeconds <= 1 / 30 and C.MaxSteps >= 2,
			"a fixed small step"
		)
		H.expect(
			C.Gravity > (C.Flare + C.Wind.Studs) * 3,
			"it hangs: gravity beats the flare and wind"
		)
		H.expect(C.HemWidth > C.TopWidth, "wider at the hem")
		H.expect(C.SeatedLength < C.Length, "shorter on his throne (down to the cushion)")
		H.expect(
			C.Margin > C.Thickness * 2 * 0.6,
			"the lining keeps off a torso up to 2 studs deep"
		)
	end,

	["his arrival has its switches and the server's burst waits for him to land"] = function()
		local Config = H.require("Config")
		local KS = H.require("HalloweenMap.KingScene")
		local E = Config.HalloweenMap.Boss.Entrance
		H.expect(type(E.Enabled) == "boolean" and type(E.Cutscene) == "boolean", "two switches")
		H.near(
			KS.landSeconds(),
			E.DelaySeconds + E.RiseSeconds,
			1e-9,
			"he lands after the glow and the rise"
		)
		local saved = E.Enabled
		E.Enabled = false
		H.expect(not KS.on() and not KS.cutsceneOn(), "Enabled off: no rise and no cutscene")
		E.Enabled = saved
		local cut = E.Cutscene
		E.Cutscene = false
		H.expect(KS.on() == saved and not KS.cutsceneOn(), "Cutscene off: the rise alone")
		E.Cutscene = cut
	end,

	["only a throne seen at his visit's start rises (a late joiner sees him standing)"] = function()
		local KS = H.require("HalloweenMap.KingScene")
		local E = H.require("Config").HalloweenMap.Boss.Entrance
		local start = 1761779700 -- a visit's start (UTC :15)
		H.expect(KS.fresh(start, start), "at the start")
		H.expect(KS.fresh(start + 1.5, start), "a moment after (the server's 1 s loop)")
		H.expect(KS.fresh(start + E.FreshSeconds, start), "up to FreshSeconds")
		H.expect(not KS.fresh(start + E.FreshSeconds + 0.5, start), "not after")
		H.expect(not KS.fresh(start + 300, start), "a join mid-visit: nothing")
		H.expect(not KS.fresh(start - 1, start), "never before his visit")
	end,

	["the throne starts under the roof, comes up smoothly and stands on his stage"] = function()
		local KS = H.require("HalloweenMap.KingScene")
		local E = H.require("Config").HalloweenMap.Boss.Entrance
		H.near(KS.depthAt(0), E.DepthStuds, 1e-9, "under the roof at first")
		H.near(KS.depthAt(E.DelaySeconds), E.DepthStuds, 1e-9, "still there while the crack glows")
		H.near(KS.depthAt(KS.landSeconds()), 0, 1e-9, "on his stage when he lands")
		H.near(KS.depthAt(KS.landSeconds() + 10), 0, 1e-9, "and after")
		local last = math.huge
		for i = 0, 100 do
			local d = KS.depthAt(i / 100 * (KS.landSeconds() + 1))
			H.expect(d <= last + 1e-9 and d >= 0, "only ever up, never through the floor")
			last = d
		end
		H.expect(E.DepthStuds >= 18, "deep enough to hide the throne and its crown (~18 tall)")
		H.expect(
			KS.shakeAt(0) == 0 and KS.shakeAt(KS.landSeconds() + E.Shake.TailSeconds) == 0,
			"a short shake"
		)
		H.expect(
			KS.shakeAt(E.DelaySeconds + E.RiseSeconds / 2) == 1,
			"at its strongest while he rises"
		)
	end,

	["the cutscene is about 6 seconds: in, three beats, the title as he lands, back out"] = function()
		local KS = H.require("HalloweenMap.KingScene")
		local E = H.require("Config").HalloweenMap.Boss.Entrance
		local C = E.Camera
		H.expect(KS.length() >= 5 and KS.length() <= 7.5, "about 6 s (" .. KS.length() .. ")")
		H.expect(
			KS.weight(0) == 0 and KS.weight(C.InSeconds) == 1,
			"eases in from the player's camera"
		)
		H.expect(KS.weight((C.InSeconds + C.BackAt) / 2) == 1, "all the scene's in the middle")
		H.near(KS.weight(KS.length()), 0, 1e-9, "the player's own camera at the end")
		H.expect(C.Shots[1].At == 0, "the first shot from the start")
		for i = 2, #C.Shots do
			H.expect(C.Shots[i].At > C.Shots[i - 1].At, "shots in order")
		end
		H.expect(C.Shots[#C.Shots].At <= C.BackAt, "every shot before the blend back")
		H.expect(
			E.TitleAt >= KS.landSeconds() and E.TitleAt < C.BackAt,
			"the title as he lands, before the end"
		)
		local landed = false
		for _, shot in C.Shots do
			landed = landed or math.abs(shot.At - KS.landSeconds()) < 0.05
			H.expect(
				math.abs(shot.Eye[1]) < 8.5,
				"the camera stays in the aisle between the tables"
			)
			H.expect(shot.Eye[3] > 6 and shot.Eye[2] > 1, "in front of him, above the floor")
			H.expect(shot.Fov >= 30 and shot.Fov <= 70, "a sane field of view")
		end
		H.expect(landed, "a shot lands with him (the push-in ends there)")
		-- the aim follows him up while he rises and is the shot's own once he has landed
		local _, lookLow = KS.shot(E.DelaySeconds)
		H.expect(lookLow[2] < 0, "aimed down at him while he is still under the roof")
		local _, lookEnd = KS.shot(C.BackAt)
		H.near(lookEnd[2], C.Shots[#C.Shots].Look[2], 1e-9, "the hero shot's own aim")
	end,

	["the cutscene is only for a player free in the lobby, and a seat or a menu ends it"] = function()
		local KS = H.require("HalloweenMap.KingScene")
		local function free(): any
			return {
				hwOn = true,
				tutorial = false,
				body = true,
				arena = false,
				seated = false,
				freecam = false,
				menu = false,
				busy = false,
				cutscene = false,
			}
		end
		H.expect(KS.free(free()) == true, "free")
		local cases = {
			{ "hwOn", false },
			{ "body", false },
			{ "tutorial", true },
			{ "arena", true },
			{ "seated", true },
			{ "freecam", true },
			{ "menu", true },
			{ "busy", true },
			{ "cutscene", true },
		}
		for _, case in cases do
			local s = free()
			s[case[1]] = case[2]
			local ok, why = KS.free(s)
			H.expect(
				not ok and why == case[1],
				case[1] .. " keeps it away (got " .. tostring(why) .. ")"
			)
		end
		H.expect(KS.cutBy(free()) == nil, "nothing ends it while free")
		for _, k in { "seated", "menu", "freecam" } do
			local s = free()
			s[k] = true
			H.expect(KS.cutBy(s) == k, k .. " ends it at once")
		end
		local s = free()
		s.body = false
		H.expect(KS.cutBy(s) == "body", "the body going ends it")
		s = free()
		s.busy = true -- (its own scene makes the lobby busy: never a reason to end it)
		H.expect(KS.cutBy(s) == nil, "busy alone never ends it")
	end,
}
