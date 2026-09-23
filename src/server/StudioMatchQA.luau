--!strict
-- Studio-only fixtures for automated inspection. ServerStorage BindableFunctions are
-- inaccessible to clients; this module creates nothing in a published server.
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Engine = require(Shared.Rules.MatchEngine)
local Ball = require(Shared.Physics.Ball)
local Simulation = require(Shared.Physics.Simulation)
local QA = {}

function QA.start(tables: any, seatOf: any, broadcast: (any) -> (), flush: (any) -> ())
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
		if command == "fixture" then
			-- Synthetic identities exercise six-portrait presentation, not network clients.
			local previousEpoch = t.engine.epoch
			t.engine = Engine.new(id, t.engine.teamSize)
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
			for team = 1, 2 do
				for slot = 1, t.engine.teamSize do
					local localSeat = team == 1 and slot == 1 and not (data and data.spectator)
					local uid = if localSeat then real.UserId else -(team * 10 + slot)
					local name = if localSeat
						then real.DisplayName
						else "FixturePlayerLongName" .. slot
					Engine.join(t.engine, uid, name, name, team, slot, now)
				end
			end
			Engine.advance(t.engine, now + 5, 1)
			Engine.advance(t.engine, now + 8, 1)
		elseif command == "shot" then
			local replay, reason = Engine.acceptShot(t.engine, t.engine.shooter, data, now)
			if replay then
				flush(t) -- grants before the snapshot that carries the replay, as ShotService does
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
			Engine.advance(t.engine, data.now or t.engine.deadline, data.coin or 1)
		elseif command ~= "phase" then
			error("Unknown QA command")
		end
		local e = t.engine
		assert(#e.seats > 0, "Create a fixture before setting its phase")
		if command == "phase" or command == "fixture" then
			data = data or {}
			e.phase, e.phaseStartedAt = data.phase or "Aiming", now
			e.deadline = now + (data.seconds or 30)
			e.breakShot = data.breakShot == true
			e.ballInHand = e.phase == "Placement"
			e.groups = if data.open then {} else { "solids", "stripes" }
			e.shot, e.pending = nil, nil
			e.turnId += 1
			e.shooter = if data.opponent then e.seats[#e.seats].userId else e.seats[1].userId
			e.activeTeam = if data.opponent then 2 else 1
			e.calledPocket = data.calledPocket
			e.foul = { by = e.shooter, team = e.activeTeam, reason = "Scratch" }
			e.result = { winner = data.winner or 1, reason = "LegalEight" }
			for _, b in e.state.balls do
				Ball.stop(b)
				b.pocketed = data.eligible and b.id >= 1 and b.id <= 7 or false
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
			e.revision += 1
		end
		broadcast(t)
		return Engine.snapshot(e)
	end
	hook.Parent = ServerStorage
end
return QA
