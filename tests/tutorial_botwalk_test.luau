--!strict
-- BotWalk (Tutorial/BotWalk, tutorial v2 4.3): which pad the player heads for, when game 1's bot
-- heads over, and how it keeps time so it steps on 0.5-2 s after the player.
local H = require("./harness")

local function load()
	return H.require("Tutorial.BotWalk"), H.require("Config").Tutorial.Bot
end

-- Tables 2 and 3's pads on the roof (19 along X, 8 along Z).
local PADS = {
	{ id = 2, x = -18, z = 57.75, hx = 9.5, hz = 4 },
	{ id = 3, x = 18, z = 57.75, hx = 9.5, hz = 4 },
	{ id = 6, x = -18, z = 26.25, hx = 9.5, hz = 4 },
}

return {
	["the distance to a pad is to its nearest edge, 0 on it"] = function()
		local W = load()
		local pad = PADS[1]
		H.expect(W.distanceToPad(pad, -18, 57.75) == 0, "the middle")
		H.expect(W.distanceToPad(pad, -27, 54) == 0, "a corner, inside")
		H.expect(math.abs(W.distanceToPad(pad, -18, 71.75) - 10) < 1e-9, "straight out in front")
		H.expect(math.abs(W.distanceToPad(pad, -5.5, 65.75) - 5) < 1e-9, "off a corner (3, 4, 5)")
	end,

	["the player heads for the pad they walk toward, the nearest if two"] = function()
		local W = load()
		-- From the spawn (0, 76.75), walking down-left toward table 2's pad.
		H.expect(W.heading(PADS, 0, 76.75, -8, -18) == 2, "toward table 2")
		H.expect(W.heading(PADS, 0, 76.75, 8, -18) == 3, "toward table 3")
		-- Walking along the front, past them: none is ahead.
		H.expect(W.heading(PADS, 0, 76.75, 20, 0) == nil, "along the front")
		-- Slow or still: not heading anywhere.
		H.expect(W.heading(PADS, 0, 76.75, -1, -2) == nil, "standing about")
		-- On a pad: that pad.
		H.expect(W.heading(PADS, -18, 57.75, 0, -20) == 2, "on it")
		-- Table 6's pad is straight behind table 2's on this line: the nearer one wins.
		H.expect(W.heading(PADS, -18, 75, 0, -20) == 2, "the nearer of two")
	end,

	["the bot heads over when its walk would end LeadSeconds after the player"] = function()
		local W, B = load()
		H.expect(W.shouldGo(2.5, 1.0) and W.shouldGo(2.0, 1.0), "its walk is long enough")
		H.expect(not W.shouldGo(1.9, 1.0), "it would be there under a second after them")
		-- The player nearly there and its walk short: it waits for them to step on (TutorialBot
		-- sends it the moment they are on).
		H.expect(not W.shouldGo(0.6, 0.3), "a short walk waits")
		H.expect(W.walkSeconds(B.WalkSpeed) == B.Overhead, "one second of walking, with its stops")
		H.expect(W.eta(B.PlayerSpeed, true) == 1, "")
		H.expect(W.eta(B.PlayerSpeed, false) == 1 + B.StoppedExtraSeconds, "standing still")
	end,

	["on the way it stops while early, never steps on too soon"] = function()
		local W, B = load()
		-- 1 s of walking left, the player 2 s out: it would be 2 s early.
		local late = W.lateness(1, 2, 0)
		H.expect(math.abs(late + 2) < 1e-9 and W.shouldPause(late), "early: a natural stop")
		-- The player on the pad for 0.8 s, it has 0.3 s left: 0.1 s past its aim (still well
		-- inside 2 s): no stop.
		late = W.lateness(0.3, 0, 0.8)
		H.expect(math.abs(late - (0.3 - (B.LeadSeconds - 0.8))) < 1e-9, "")
		H.expect(not W.shouldPause(late), "late: keeps going")
		H.expect(not W.shouldPause(W.lateness(1.5, 0.7, 0)), "0.2 s early: keeps going")
		H.expect(not W.mayStepOn(nil) and not W.mayStepOn(0.2), "too soon after the player")
		H.expect(W.mayStepOn(B.MinAfterSeconds), "")
	end,

	["the timing lands every front-row join inside 0.5-2 s (the plan's walks)"] = function()
		local W, B = load()
		-- Walks like the plan's (seconds at the players' speed, straight): the bot from where
		-- it strolls, the player from the spawn. Played out: it leaves when shouldGo says, walks at
		-- Overhead, and never steps on before MinAfterSeconds.
		local walks = {
			{ bot = 3.0, player = 2.3 },
			{ bot = 1.3, player = 0.8 },
			{ bot = 0.6, player = 2.4 },
			{ bot = 3.6, player = 4.6 },
		}
		for _, w in walks do
			local botSeconds = w.bot * B.Overhead
			local leaveAt = 0
			for step = 0, 1000 do
				local now = step * 0.1
				local eta = math.max(w.player - now, 0)
				if W.shouldGo(botSeconds, eta) then
					leaveAt = now
					break
				end
			end
			local arrive = math.max(leaveAt + botSeconds, w.player + B.MinAfterSeconds)
			local wait = arrive - w.player
			H.expect(
				wait >= B.MinAfterSeconds - 1e-9 and wait <= 2,
				("bot %.1f s, player %.1f s: waits %.2f s"):format(w.bot, w.player, wait)
			)
		end
	end,
}
