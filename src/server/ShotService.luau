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
		if type(payload) ~= "table" or not Tables.allow(player) then
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
			Net.get("ShotResult"):FireAllClients(result)
		else
			Net.get("ShotRejected"):FireClient(player, reason or "ShotRejected")
		end
		Tables.broadcast(t)
	end)
end
return Service
