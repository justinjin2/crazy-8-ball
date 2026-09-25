--!strict
-- The shared engine accepts one owned, current action and produces one replay.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Engine = require(Shared.Rules.MatchEngine)
local Tables = require(script.Parent.TableService)
local Service = {}
local started = false
function Service.start()
	if started then
		return
	end
	started = true
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
			-- the ball and the sting lands with the drop (Audio.grant forgives a late one).
			Tables.flush(t)
			-- The shooter's root goes to the exact spot they shot from before anyone sees the
			-- shot, so its ShotSpot is there by the time their stroke hands over to idle.
			Tables.shotAccepted(t, player.UserId, payload.angle, payload.spin, payload.elevation)
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
