--!strict
local H = require("./harness")
local E = H.require("Rules.MatchEngine")
local J = H.require("Rules.ShotJudge")
local P = H.require("Rules.CuePlacement")
local Ball = H.require("Physics.Ball")
local S = H.require("Physics.Simulation")
local function full(n)
	local t = E.new(n, n)
	for team = 1, 2 do
		for slot = 1, n do
			H.expect(E.join(t, team * 10 + slot, "Player", "Player", team, slot, 0))
		end
	end
	E.advance(t, 5, 1)
	E.advance(t, 7.6)
	return t
end
local function event(kind, id, other, time)
	return { type = kind, ball = id, other = other, t = time or 0, speed = 10 }
end
local function outcome(t, events)
	local balls = Ball.cloneList(t.state.balls)
	for _, ev in events do
		if ev.type == "pocket" then
			for _, b in balls do
				if b.id == ev.ball then
					b.pocketed = true
				end
			end
		end
	end
	return {
		events = events,
		finalBalls = balls,
		firstContact = S.firstContact(events),
		duration = 1,
		steps = 240,
		capped = false,
	}
end
local function resolve(t, events, time)
	local o = outcome(t, events)
	t.pending = {
		outcome = o,
		judgement = J.resolve(
			t.state.balls,
			o,
			t.groups,
			t.activeTeam,
			t.breakShot,
			t.calledPocket
		),
	}
	t.phase = "Resolving"
	t.deadline = time
	E.advance(t, time)
end
local function action(t, kind, extra)
	local a = extra or {}
	a.kind = kind
	a.epoch = t.epoch
	a.turnId = t.turnId
	return a
end
return {
	["every mode counts cancels countdown rehosts and starts only once"] = function()
		for n = 1, 3 do
			local t = E.new(n, n)
			for team = 1, 2 do
				for slot = 1, n do
					E.join(t, team * 10 + slot, "p", "p", team, slot, 0)
				end
			end
			H.expect(t.phase == "Countdown")
			H.expect(not E.join(t, 11, "p", "p", 1, 1, 1))
			E.remove(t, 11, 2)
			H.expect(t.phase == "Waiting" and t.hostId ~= 11)
			E.advance(t, 9, 1)
			H.expect(t.phase == "Waiting")
			E.join(t, 99, "p", "p", 1, 1, 10)
			H.expect(t.deadline == 15)
			E.advance(t, 15, 2)
			local rev = t.revision
			H.expect(t.phase == "CoinFlip" and t.coin.winnerTeam == 2)
			E.advance(t, 15, 1)
			H.expect(t.revision == rev and t.coin.winnerTeam == 2)
		end
	end,
	["shot judge handles mixed assignment and never assigns on a foul"] = function()
		local t = full(1)
		local ev = { event("ballHit", 0, 9), event("pocket", 9, 1, 1), event("pocket", 1, 2, 2) }
		local j = J.resolve(t.state.balls, outcome(t, ev), {}, 1, false, nil)
		H.expect(j.groups[1] == "stripes" and j.keep and j.assigned)
		table.insert(ev, event("pocket", 0, 1, 3))
		j = J.resolve(t.state.balls, outcome(t, ev), {}, 1, false, nil)
		H.expect(j.foul == "Scratch" and not j.assigned and j.groups[1] == nil)
	end,
	["break requires apex and four distinct rails or a pocket"] = function()
		local t = full(1)
		local ev = { event("ballHit", 0, 1) }
		for _ = 1, 4 do
			table.insert(ev, event("railHit", 1))
		end
		H.expect(J.resolve(t.state.balls, outcome(t, ev), {}, 1, true, nil).foul == "IllegalBreak")
		for id = 2, 4 do
			table.insert(ev, event("railHit", id))
		end
		H.expect(J.resolve(t.state.balls, outcome(t, ev), {}, 1, true, nil).foul == nil)
		ev[1] = event("ballHit", 0, 2)
		H.expect(J.resolve(t.state.balls, outcome(t, ev), {}, 1, true, nil).foul == "IllegalBreak")
	end,
	["eight on break respots unless foul passes possession"] = function()
		local t = full(2)
		resolve(t, { event("ballHit", 0, 1), event("pocket", 8, 1, 1) }, 9)
		H.expect(t.shooter == 12 and t.groups[1] == nil and not S.findBall(t.state, 8).pocketed)
		local other = full(2)
		resolve(
			other,
			{ event("ballHit", 0, 1), event("pocket", 8, 1, 1), event("pocket", 0, 2, 2) },
			9
		)
		H.expect(other.phase == "Foul" and not S.findBall(other.state, 8).pocketed)
		E.advance(other, other.deadline)
		H.expect(other.shooter == 21 and other.ballInHand)
	end,
	["legal targets rail requirements and eight eligibility are pre shot"] = function()
		local t = full(1)
		t.groups = { "solids", "stripes" }
		H.expect(not J.legalTarget(t.state.balls, t.groups[1], 8))
		for _, b in t.state.balls do
			if b.id >= 1 and b.id <= 7 then
				b.pocketed = true
			end
		end
		H.expect(J.legalTarget(t.state.balls, t.groups[1], 8))
		local ev = { event("ballHit", 0, 8), event("railHit", 8), event("pocket", 0, 1, 1) }
		local j = J.resolve(t.state.balls, outcome(t, ev), t.groups, 1, false, 1)
		H.expect(j.foul == "Scratch" and j.winner == nil)
		ev = { event("ballHit", 0, 8), event("pocket", 8, 2, 1) }
		H.expect(
			J.resolve(t.state.balls, outcome(t, ev), t.groups, 1, false, 1).reason == "WrongPocket"
		)
		H.expect(J.resolve(t.state.balls, outcome(t, ev), t.groups, 1, false, 2).winner == 1)
		S.findBall(t.state, 7).pocketed = false
		ev = { event("ballHit", 0, 7), event("pocket", 7, 1, 1), event("pocket", 8, 2, 2) }
		H.expect(
			J.resolve(t.state.balls, outcome(t, ev), t.groups, 1, false, 2).reason == "EarlyEight"
		)
		H.expect(
			J.resolve(
				t.state.balls,
				outcome(t, { event("ballHit", 0, 7) }),
				t.groups,
				1,
				false,
				nil
			).foul == "NoRail"
		)
		H.expect(
			J.resolve(
				t.state.balls,
				outcome(t, { event("ballHit", 0, 9), event("railHit", 9) }),
				t.groups,
				1,
				false,
				nil
			).foul == "WrongContact"
		)
	end,
	["all modes finish legal games rotate each shot and reuse tables"] = function()
		for n = 1, 3 do
			local t = full(n)
			resolve(t, {
				event("ballHit", 0, 1),
				event("railHit", 1),
				event("railHit", 2),
				event("railHit", 3),
				event("railHit", 4),
			}, 10)
			H.expect(t.activeTeam == 2 and t.shooter == 21)
			local expectedSlot = 1
			for id = 1, 7 do
				H.expect(t.shooter == 20 + expectedSlot)
				resolve(t, { event("ballHit", 0, id), event("pocket", id, 1, 1) }, 10 + id * 10)
				expectedSlot = expectedSlot % n + 1
			end
			H.expect(J.eligible(t.state.balls, t.groups[2]) and t.activeTeam == 2)
			t.calledPocket = 2
			resolve(t, { event("ballHit", 0, 8), event("pocket", 8, 2, 1) }, 100)
			H.expect(t.phase == "Result" and t.result.winner == 2)
			local epoch = t.epoch
			E.advance(t, t.deadline)
			H.expect(
				t.phase == "Waiting"
					and #t.seats == 0
					and t.epoch == epoch + 1
					and not S.findBall(t.state, 8).pocketed
			)
		end
	end,
	["placement blocks edges pockets overlaps and finds valid fallback"] = function()
		local t = full(1)
		H.expect(P.valid(t.state, -25, 0, true))
		for _, v in { math.huge, 0 / 0, "0" } do
			H.expect(not P.valid(t.state, v, 0))
		end
		H.expect(
			not P.valid(t.state, 0, 25)
				and not P.valid(t.state, 25, 0)
				and not P.valid(t.state, 0, 0, true)
		)
		S.findBall(t.state, 1).x = -25
		S.findBall(t.state, 1).y = 0
		local x, y = P.fallback(t.state, 0, true)
		H.expect(x == -25 and P.valid(t.state, x, y, true))
	end,
	["setup deadlines call expiry and reselection never extend aiming"] = function()
		local t = full(1)
		E.advance(t, t.deadline)
		H.expect(t.phase == "Placement")
		E.advance(t, t.deadline)
		H.expect(t.phase == "Aiming")
		t.breakShot = false
		t.groups = { "solids", "stripes" }
		for _, b in t.state.balls do
			if b.id >= 1 and b.id <= 7 then
				b.pocketed = true
			end
		end
		t.phase = "Placement"
		t.ballInHand = true
		t.deadline = 100
		E.advance(t, 100)
		H.expect(t.phase == "PocketChoice")
		E.advance(t, 110)
		H.expect(t.phase == "Aiming" and t.calledPocket ~= nil)
		local deadline = t.deadline
		H.expect(E.action(t, t.shooter, action(t, "Pocket", { pocket = 2 }), 111))
		H.expect(t.deadline == deadline)
	end,
	["only current shooter current epoch and legal phase can act"] = function()
		local t = full(3)
		H.expect(not E.action(t, 12, action(t, "Place", { x = -25, y = 2 }), 8))
		H.expect(
			not E.action(t, 11, { kind = "Place", epoch = 0, turnId = t.turnId, x = -25, y = 2 }, 8)
		)
		H.expect(E.action(t, 11, action(t, "Place", { x = -25, y = 2 }), 8))
		local msg = { epoch = t.epoch, turnId = t.turnId, angle = 0, power = 0.7 }
		H.expect(E.acceptShot(t, 12, msg, 8) == nil)
		local shot = E.acceptShot(t, 11, msg, 8)
		H.expect(shot ~= nil and t.phase == "Resolving")
		H.expect(E.acceptShot(t, 11, msg, 8) == nil)
		local deadline = t.deadline
		E.advance(t, deadline - 0.01)
		H.expect(t.phase == "Resolving")
		E.advance(t, deadline)
		H.expect(t.phase ~= "Resolving")
	end,
	["team timeouts forfeit only after two without an accepted shot"] = function()
		local t = full(3)
		t.phase = "Aiming"
		t.deadline = 10
		E.advance(t, 10)
		H.expect(t.phase == "Foul" and t.timeouts[1] == 1)
		E.advance(t, t.deadline)
		t.phase = "Aiming"
		t.deadline = 20
		E.advance(t, 20)
		E.advance(t, t.deadline)
		t.phase = "Aiming"
		t.deadline = 30
		E.advance(t, 30)
		H.expect(t.phase == "Result" and t.result.winner == 2 and t.result.reason == "Timeouts")
	end,
	["surrender is unanimous with no expiry pause and cooldown"] = function()
		local t = full(3)
		local deadline = t.deadline
		H.expect(E.action(t, 11, action(t, "Surrender"), 8))
		H.expect(E.action(t, 12, action(t, "Vote", { yes = false }), 8.1))
		H.expect(t.vote == nil and t.deadline == deadline)
		H.expect(not E.action(t, 11, action(t, "Surrender"), 9))
		H.expect(E.action(t, 11, action(t, "Surrender"), 40))
		H.expect(E.action(t, 12, action(t, "Vote", { yes = true }), 40.1))
		H.expect(t.phase ~= "Result")
		H.expect(E.action(t, 13, action(t, "Vote", { yes = true }), 40.2))
		H.expect(t.phase == "Result" and t.result.winner == 2)
	end,
	["disconnects skip missing players and reset only fouls once"] = function()
		local t = full(3)
		E.death(t, 11, 8)
		local turn = t.turnId
		E.death(t, 11, 8.1)
		H.expect(t.phase == "Foul" and t.turnId == turn and E.seat(t, 11) ~= nil)
		E.remove(t, 12, 8.2)
		H.expect(t.phase == "Foul" and E.count(t, 1) == 2)
		E.advance(t, t.deadline)
		resolve(t, { event("ballHit", 0, 1), event("railHit", 1) }, 20)
		H.expect(t.shooter == 13)
		E.remove(t, 11, 21)
		E.remove(t, 13, 22)
		H.expect(t.result.winner == 2)
	end,
	["three engines keep epochs clocks balls votes and results independent"] = function()
		local a, b, c = full(1), full(2), full(3)
		local other = E.pack(b.state.balls)
		E.action(a, 11, action(a, "Surrender"), 8)
		E.action(c, 11, action(c, "Place", { x = -25, y = 5 }), 8)
		H.expect(a.phase == "Result" and b.phase == "Intro" and c.phase == "Intro")
		H.expect(S.findBall(b.state, 0).y == other[2] and S.findBall(c.state, 0).y == 5)
	end,
	["last disconnect waits for accepted shot to settle before empty-team result"] = function()
		local t = full(1)
		local payload = {
			epoch = t.epoch,
			turnId = t.turnId,
			angle = 0,
			power = 0.5,
			spin = { x = 0, y = 0 },
			elevation = 4,
		}
		local wire = E.acceptShot(t, 11, payload, 8)
		H.expect(wire ~= nil and t.phase == "Resolving")
		local pending = t.pending
		E.remove(t, 11, 8.1)
		H.expect(t.phase == "Resolving" and t.pending == pending)
		E.advance(t, t.deadline)
		H.expect(t.phase == "Result" and t.result.winner == 2 and t.result.reason == "EmptyTeam")
		H.expect(t.pending == nil and t.shot == nil)
	end,
	["active host reassignment leaves the agreed coin sides unchanged"] = function()
		local t = full(2)
		local heads = t.coin.headsTeam
		E.remove(t, 11, 8)
		H.expect(t.hostId == 12 and E.seat(t, 12).host)
		H.expect(t.coin.headsTeam == heads and t.phase == "Foul")
	end,
}
