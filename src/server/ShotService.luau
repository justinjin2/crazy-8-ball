--!strict
-- The shared engine accepts one owned, current action and produces one replay.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Engine = require(Shared.Rules.MatchEngine)
local Tables = require(script.Parent.TableService)
local Economy = require(script.Parent.Economy)
local Service = {}
local started = false

-- A judged shot: its stings and gains, then its money, then the replay to everyone.
local function judged(t: any, player: Player?)
	Tables.flush(t)
	if player and t.engine.pending and t.engine.pending.judgement then
		-- The money this shot paid, into the save now and to the shooter for the flying cash
		-- (their replay drops the balls a moment later).
		local paid, err = pcall(function(): any
			Economy.onShot(t, player)
			return nil
		end)
		if not paid then
			warn("[8ball] Economy.onShot failed: " .. tostring(err))
		end
	end
end
function Service.start()
	if started then
		return
	end
	started = true
	Tables.onLateShot(function(t: any)
		local shot = t.engine.shot
		judged(t, if shot then Players:GetPlayerByUserId(shot.shooter) else nil)
		if shot then
			Net.get("ShotResult"):FireAllClients(shot)
		end
		Tables.broadcast(t)
	end)
	Net.get("ShotFired").OnServerEvent:Connect(function(player, payload)
		if type(payload) ~= "table" or not Tables.allow(player, "shot") then
			return
		end
		local id = Tables.tableOf(player)
		if not id or payload.tableId ~= id then
			Net.get("ShotRejected"):FireClient(player, "WrongTable")
			return
		end
		local t = Tables.get(id)
		local now = workspace:GetServerTimeNow()
		Tables.advance(t, now)
		local ok, result, reason = pcall(Engine.acceptShot, t.engine, player.UserId, payload, now)
		if not ok then
			warn("[8ball] shot failed: " .. tostring(result))
			Net.get("ShotRejected"):FireClient(player, "SimulationError")
		elseif result then
			-- Grants first, so the owning team already holds its bonus when the replay drops
			-- the ball and the sting lands with the drop (Audio.grant forgives a late one). A
			-- Time Stop shot's first part has no verdict yet (it is judged at the resume).
			judged(t, player)
			-- The shooter's root goes to the exact spot they shot from before anyone sees the
			-- shot, so its ShotSpot is there by the time their stroke hands over to idle. A
			-- second strike in stopped time leaves the body where it is.
			if not result.parts or not result.parts.strikes then
				Tables.shotAccepted(
					t,
					player.UserId,
					payload.angle,
					payload.spin,
					payload.elevation
				)
			end
			Net.get("ShotResult"):FireAllClients(result)
		else
			Net.get("ShotRejected"):FireClient(player, reason or "ShotRejected")
		end
		-- An accepted shot (or an advance above that moved a phase on) goes to everyone. A plain
		-- rejection changes nothing, so only the shooter needs the current state back.
		if t.engine.revision ~= t.sentRevision then
			Tables.broadcast(t)
		else
			Tables.broadcast(t, player)
		end
	end)
end
return Service
