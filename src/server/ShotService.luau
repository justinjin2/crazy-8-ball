--!strict
-- ShotService: the server decides what a shot did.
--
-- The client sends inputs and nothing else. This validates them, runs the simulation once,
-- stores the result as the table's new truth, and tells every client how to replay it.
--
-- WHY THE CLIENTS ARE NOT SENT {angle, power} TO RE-STRIKE FROM
--
-- Cue.strike calls math.cos, math.sin and a fractional power, and none of those three are
-- correctly rounded: they come from the platform's libm, so a Linux x86-64 server and an
-- ARM phone can disagree in the last bit. One ulp in a break's opening velocity is not a
-- rounding error by the time sixteen balls have finished scattering, it is a different
-- shot. So the server strikes ONCE and broadcasts the resulting cue-ball velocity and spin
-- as the seed. Every client starts from bit-identical doubles and steps the same
-- deterministic integrator from there. The inputs still travel client to server, because
-- the server must validate them; they simply are not what the replay is built from.
--
-- Whatever drift is left is measured rather than assumed: the broadcast carries a checksum
-- of the server's final positions, and a client that ends up somewhere else says so in the
-- console and settles onto the server's answer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Physics = Shared:WaitForChild("Physics")
local Ball = require(Physics:WaitForChild("Ball"))
local Simulation = require(Physics:WaitForChild("Simulation"))
local TableService = require(script.Parent:WaitForChild("TableService"))

local ShotService = {}

-- Quantising the seed before it goes on the wire means every client receives exactly the
-- same doubles, rather than whatever the serialiser happened to round to.
local SEED_PLACES = 1e6

local function quantise(v: number): number
	return math.floor(v * SEED_PLACES + 0.5) / SEED_PLACES
end

--- The final balls, flattened for the wire: x, y, z, pocketed per ball in list order.
local function packBalls(balls: { Ball.Ball }): { number }
	local out = table.create(#balls * 4)
	for i, b in balls do
		out[4 * i - 3] = b.x
		out[4 * i - 2] = b.y
		out[4 * i - 1] = b.z
		out[4 * i] = if b.pocketed then 1 else 0
	end
	return out
end

--- Check a shot is one this player is allowed to take right now, and that its numbers are
--- numbers. Returns the table id, or nil with a reason.
local function validate(player: Player, payload: any): (number?, string?)
	if typeof(payload) ~= "table" then
		return nil, "payload is not a table"
	end
	local id = payload.tableId
	if typeof(id) ~= "number" or id ~= id or id % 1 ~= 0 then
		return nil, "table id is not a whole number"
	end
	if TableService.tableOf(player) ~= id then
		return nil, "player is not seated at that table"
	end
	if TableService.isBusy(id) then
		return nil, "a shot is already running on that table"
	end
	local angle, power = payload.angle, payload.power
	if typeof(angle) ~= "number" or angle ~= angle then
		return nil, "angle is not a number"
	end
	if typeof(power) ~= "number" or power ~= power then
		return nil, "power is not a number"
	end
	if power < Config.Input.MinPowerToShoot or power > 1 then
		return nil, "power out of range"
	end
	return id, nil
end

local function onShotFired(player: Player, payload: any)
	local id, reason = validate(player, payload)
	if id == nil then
		-- Not necessarily cheating: a shot can arrive just after someone else's started.
		if Config.Debug.LogRejectedShots then
			warn(("[8ball] rejected shot from %s: %s"):format(player.Name, reason or "?"))
		end
		return
	end

	local state = TableService.stateOf(id)
	if state == nil then
		return
	end

	-- Clamp rather than trust. A client that asks for 3.0 power gets 1.0, not an error.
	local shot = {
		angle = payload.angle % (2 * math.pi),
		power = math.clamp(payload.power, 0, 1),
	}

	-- Strike once, here, and keep the resulting cue ball state: that is the replay seed.
	local seedState = Simulation.cloneState(state)
	Simulation.strike(seedState, shot)
	local cue = Simulation.findBall(seedState, 0)
	if cue == nil then
		return
	end
	local seed = {
		vx = quantise(cue.vx),
		vy = quantise(cue.vy),
		wx = quantise(cue.wx),
		wy = quantise(cue.wy),
		wz = quantise(cue.wz),
	}

	-- Run the whole shot. No frames: the server never draws anything.
	local outcome = Simulation.runHeadless(state, shot)
	state.balls = Ball.cloneList(outcome.finalBalls)

	local seq, startedAt = TableService.beginShot(id, outcome.duration)
	Net.get("ShotResult"):FireAllClients({
		tableId = id,
		seq = seq,
		startedAt = startedAt,
		shooter = player.UserId,
		seed = seed,
		duration = outcome.duration,
		final = packBalls(outcome.finalBalls),
		checksum = Simulation.checksum(outcome.finalBalls),
	})
end

function ShotService.start()
	Net.get("ShotFired").OnServerEvent:Connect(function(player, payload)
		-- One malformed payload must not take the handler down for everybody else.
		local ok: boolean, err: any = pcall(onShotFired, player, payload)
		if not ok then
			warn(("[8ball] shot from %s blew up: %s"):format(player.Name, tostring(err)))
		end
	end)
end

return ShotService
