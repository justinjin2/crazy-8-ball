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
local ShotInput = require(Shared:WaitForChild("ShotInput"))
local Physics = Shared:WaitForChild("Physics")
local Ball = require(Physics:WaitForChild("Ball"))
local Cue = require(Physics:WaitForChild("Cue"))
local Simulation = require(Physics:WaitForChild("Simulation"))
local TableService = require(script.Parent:WaitForChild("TableService"))

local ShotService = {}

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
--- numbers. Returns the table id and validated shot, or nil with a reason.
local function validate(player: Player, payload: any): (number?, Cue.Shot?, string?)
	if typeof(payload) ~= "table" then
		return nil, nil, "payload is not a table"
	end
	local id = payload.tableId
	if not ShotInput.isFinite(id) or id % 1 ~= 0 then
		return nil, nil, "table id is not a finite whole number"
	end
	if TableService.tableOf(player) ~= id then
		return nil, nil, "player is not seated at that table"
	end
	if TableService.isBusy(id) then
		return nil, nil, "a shot is already running on that table"
	end
	-- No ownership/cooldown service exists yet, so no ability is authorized in live play.
	local shot, reason = ShotInput.validate(payload, nil)
	if shot == nil then
		return nil, nil, reason
	end
	-- Belt and braces for the scratch case: strike() throws without a cue ball, and a throw
	-- here would be swallowed by the pcall and answer the player with nothing at all.
	local state = TableService.stateOf(id)
	local cue = state and Simulation.findBall(state, 0)
	if cue == nil or cue.pocketed then
		return nil, nil, "no cue ball on that table"
	end
	return id, shot, nil
end

-- Tell the shooter their shot is not happening. They disabled their own controls when they
-- fired, expecting a ShotResult to turn them back on, so silence leaves them stuck.
local function reject(player: Player, reason: string)
	if Config.Debug.LogRejectedShots then
		warn(("[8ball] rejected shot from %s: %s"):format(player.Name, reason))
	end
	Net.get("ShotRejected"):FireClient(player, reason)
end

local function onShotFired(player: Player, payload: any)
	local id, shot, reason = validate(player, payload)
	if id == nil or shot == nil then
		-- Not necessarily cheating: a shot can arrive just after someone else's started.
		reject(player, reason or "?")
		return
	end

	local state = TableService.stateOf(id)
	if state == nil then
		reject(player, "that table has no state")
		return
	end

	-- Strike once, here. The resulting cue ball state is the replay seed.
	local sim = Simulation.cloneState(state)
	local strikeEvent = Simulation.strike(sim, shot)
	local cue = Simulation.findBall(sim, 0)
	if cue == nil then
		reject(player, "no cue ball to strike")
		return
	end

	-- Quantise IN PLACE, before integrating, so the server runs the very same numbers it
	-- puts on the wire. Rounding the seed for the wire and then simulating the unrounded
	-- values would make the server's answer one no client can reproduce: measured over 123
	-- breaks, 56 diverged, the worst by 51 inches, and 4 ended with a different set of
	-- balls pocketed.
	local seed = ShotInput.quantiseSeed(cue)

	-- Run that exact state to rest. No frames: the server never draws anything.
	local outcome = Simulation.settle(sim, { strikeEvent })
	state.balls = Ball.cloneList(outcome.finalBalls)

	-- A scratch must not end the table. Nothing else server-side un-pockets the cue ball,
	-- and a state whose cue ball is pocketed cannot be struck again, so without this every
	-- later shot at this table would throw inside strike and silently never broadcast.
	-- The clients respot identically when their replay ends, so they stay in step.
	Simulation.respotCueBall(state)

	local seq, startedAt = TableService.beginShot(id, outcome.duration)
	Net.get("ShotResult"):FireAllClients({
		tableId = id,
		seq = seq,
		startedAt = startedAt,
		shooter = player.UserId,
		seed = seed,
		overrides = outcome.overrides,
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
			-- Even a crash has to answer, or that player's controls stay dead.
			pcall(reject, player, "the server could not run that shot")
		end
	end)
end

return ShotService
