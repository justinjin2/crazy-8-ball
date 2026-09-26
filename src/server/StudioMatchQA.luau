--!strict
-- Studio-only fixtures for automated inspection. ServerStorage BindableFunctions are
-- inaccessible to clients; this module creates nothing in a published server.
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Engine = require(Shared.Rules.MatchEngine)
local Judge = require(Shared.Rules.ShotJudge)
local Ball = require(Shared.Physics.Ball)
local Simulation = require(Shared.Physics.Simulation)
local QA = {}

function QA.start(
	tables: any,
	seatOf: any,
	broadcast: (any) -> (),
	flush: (any) -> (),
	shotAccepted: (any, number, number, { x: number, y: number }?, number?) -> ()
)
	if not RunService:IsStudio() then
		return
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "PoolMatchQA"
	hook.OnInvoke = function(command: string, id: number, data: any)
		local t = assert(tables[id], "Unknown QA table")
		local now = workspace:GetServerTimeNow()
		if command == "snapshot" then
			return Engine.snapshot(t.engine)
		end
		if command == "fixture" or command == "queue" then
			-- Synthetic identities exercise six-portrait presentation, not network clients.
			local previousEpoch = t.engine.epoch
			t.engine = Engine.new(id)
			t.engine.epoch = previousEpoch + 1
			local real = assert(Players:GetPlayers()[1], "QA requires a running client")
			if not (data and data.spectator) then
				for _, other in tables do
					if other ~= t then
						Engine.remove(other.engine, real.UserId, now)
						broadcast(other)
					end
				end
				seatOf[real.UserId] = id
			end
			local e = t.engine
			if command == "queue" then
				-- A box still waiting for its host: the real player first (the host), then one
				-- synthetic player per entry of data.sides, standing in that half. The real
				-- player has to stand in the box, or the poll lets them go.
				local q = data or {}
				Engine.join(e, real.UserId, real.DisplayName, real.DisplayName, q.side or 1, now)
				for i, side in q.sides or {} do
					local name = "FixturePlayerLongName" .. i
					Engine.join(e, -i, name, name, side, now)
				end
				broadcast(t)
				return Engine.snapshot(e)
			elseif data and data.solo then
				-- Solo: only the real player sits down, then starts the game as the button does.
				Engine.join(e, real.UserId, real.DisplayName, real.DisplayName, 1, now)
				local request = { kind = "StartSolo", epoch = e.epoch, turnId = e.turnId }
				assert(Engine.action(e, real.UserId, request, now), "StartSolo was refused")
			else
				-- data.teamSize a side (1 by default), team A in the head half; the first in hosts.
				local size = data and data.teamSize or 1
				for slot = 1, size do
					for team = 1, 2 do
						local localSeat = team == 1 and slot == 1 and not (data and data.spectator)
						local uid = if localSeat then real.UserId else -(team * 10 + slot)
						local name = if localSeat
							then real.DisplayName
							else "FixturePlayerLongName" .. slot
						Engine.join(e, uid, name, name, team, now)
					end
				end
				local request = { kind = "Start", epoch = e.epoch, turnId = e.turnId }
				assert(Engine.action(e, e.hostId, request, now, 1), "Start was refused")
				Engine.advance(e, now + 8)
			end
		elseif command == "shot" then
			local shooter = t.engine.shooter
			local replay, reason = Engine.acceptShot(t.engine, shooter, data, now)
			if replay then
				flush(t) -- grants before the snapshot that carries the replay, as ShotService does
				shotAccepted(t, shooter, data.angle, data.spin, data.elevation) -- and the stance, as it does
			end
			broadcast(t)
			return { replay = replay, reason = reason }
		elseif command == "action" then
			local accepted = Engine.action(t.engine, data.userId or t.engine.shooter, data, now)
			broadcast(t)
			return accepted
		elseif command == "remove" then
			Engine.remove(t.engine, data.userId, now)
		elseif command == "death" then
			Engine.death(t.engine, data.userId, now)
		elseif command == "advance" then
			Engine.advance(t.engine, data.now or t.engine.deadline)
		elseif command ~= "phase" then
			error("Unknown QA command")
		end
		local e = t.engine
		assert(#e.seats > 0, "Create a fixture before setting its phase")
		if command == "phase" or command == "fixture" then
			data = data or {}
			e.phase, e.phaseStartedAt = data.phase or "Aiming", now
			e.deadline = now + (data.seconds or 30)
			-- Solo has no clock on the setup and aiming phases.
			local untimed = e.phase == "PocketChoice"
				or e.phase == "Placement"
				or e.phase == "Aiming"
			if e.solo and untimed then
				e.deadline = nil
			end
			e.breakShot = data.breakShot == true
			e.ballInHand = e.phase == "Placement"
			e.groups = if data.open then {} else { "solids", "stripes" }
			e.shot, e.pending = nil, nil
			e.turnId += 1
			e.placeSeq = 0 -- a new turn, so the client's placement counter starts again
			e.shooter = if data.opponent then e.seats[#e.seats].userId else e.seats[1].userId
			e.activeTeam = if data.opponent then 2 else 1
			e.calledPocket = data.calledPocket
			e.foul = { by = e.shooter, team = e.activeTeam, reason = "Scratch" }
			e.nextTeam = 3 - e.activeTeam -- a forced Foul hands the table over when it ends
			e.result = { winner = data.winner or 1, reason = "LegalEight" }
			for _, b in e.state.balls do
				Ball.stop(b)
				b.pocketed = data.eligible and b.id >= 1 and b.id <= 7 or false
				if e.solo and data.eligible then
					b.pocketed = b.id ~= 0 and b.id ~= 8 -- solo: the 8 is on once all 14 are down
				end
			end
			local cue = assert(Simulation.findBall(e.state, 0))
			cue.x, cue.y = -25, 0
			if data.finalEight then
				for _, b in e.state.balls do
					b.pocketed = b.id ~= 0 and b.id ~= 8
				end
				local eight = assert(Simulation.findBall(e.state, 8), "QA requires eight")
				eight.x, eight.y = 0, e.state.geometry.halfWidth - 5
				cue.x, cue.y = 0, eight.y - 8
			end
			if e.solo then
				-- Solids first; the solo player's group is whichever of the two is still up.
				e.solo.first = e.groups[e.solo.team]
				local current = Judge.soloGroup(e.state.balls, e.solo.first)
				if current then
					e.groups = {}
					e.groups[e.solo.team], e.groups[3 - e.solo.team] =
						current, Judge.opposite(current)
				end
			end
			e.revision += 1
		end
		broadcast(t)
		return Engine.snapshot(e)
	end
	hook.Parent = ServerStorage
end
return QA
