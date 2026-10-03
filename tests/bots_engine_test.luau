--!strict
-- The engine's bot hooks (the Bots lane): against bots the real player always breaks
-- (`breakFor`), on the first game and every rematch, whichever side the coin picks.
local H = require("./harness")
local E = H.require("Rules.MatchEngine")
local Brain = H.require("Bots.Brain")
local Rng = H.require("Bots.Rng")
local Ball = H.require("Physics.Ball")
local Placement = H.require("Rules.CuePlacement")
local expect = H.expect

local BOT = -1000

-- A 1v1 pad: the real player `host` first, then the bot (or the bot first).
local function pad(botFirst: boolean): any
	local m = E.new(1, 1)
	if botFirst then
		expect(E.join(m, BOT, "Bot", "Bot", 0))
		expect(E.join(m, 7, "Real", "Real", 0.1))
	else
		expect(E.join(m, 7, "Real", "Real", 0))
		expect(E.join(m, BOT, "Bot", "Bot", 0.1))
	end
	m.breakFor = 7
	return m
end

local function teamOf(m: any, id: number): number
	return (E.seat(m, id) :: any).team
end

local tests = {}

tests["the real player breaks whatever the coin, host or not"] = function()
	for _, botFirst in { false, true } do
		for coin = 1, 2 do
			local m = pad(botFirst)
			expect(
				E.action(
					m,
					m.hostId,
					{ kind = "Start", epoch = m.epoch, turnId = m.turnId },
					0,
					coin
				)
			)
			expect(m.coin.winnerTeam == teamOf(m, 7), "the coin lands for the real player")
			expect(m.coin.breaker == 7, "they break")
			expect(m.activeTeam == teamOf(m, 7))
		end
	end
end

tests["a rematch against a bot: the real player breaks again"] = function()
	local m = pad(false)
	expect(E.action(m, m.hostId, { kind = "Start", epoch = m.epoch, turnId = m.turnId }, 0, 2))
	E.advance(m, m.deadline) -- the coin
	expect(E.action(m, 7, { kind = "Surrender", epoch = m.epoch, turnId = m.turnId }, 1))
	expect(m.phase == "Result")
	for _, id in { 7, BOT } do
		expect(E.action(m, id, { kind = "Rematch", epoch = m.epoch, turnId = m.turnId }, 2))
	end
	E.advance(m, 2)
	expect(m.phase ~= "Result", "the rematch started")
	expect(m.breakFor == 7, "kept through the rematch")
	expect(m.activeTeam == teamOf(m, 7), "the real player breaks the rematch too")
end

tests["without breakFor the coin decides as before"] = function()
	local m = E.new(1, 1)
	expect(E.join(m, 1, "a", "a", 0))
	expect(E.join(m, 2, "b", "b", 0.1))
	expect(E.action(m, 1, { kind = "Start", epoch = m.epoch, turnId = m.turnId }, 0, 2))
	expect(m.coin.winnerTeam == 2)
end

tests["fill with PC: the real side together, the robots on the other"] = function()
	-- Teams alternate by arrival unless a seat carries presetTeam (BotService's Fill with PC),
	-- and the preset is used once (a later game on the pad alternates again).
	local m = E.new(1, 2)
	expect(E.join(m, 7, "Real", "Real", 0))
	expect(E.join(m, 8, "Mate", "Mate", 0.1))
	expect(E.join(m, BOT, "Bot", "Bot", 0.2))
	expect(E.join(m, BOT - 1, "Bot2", "Bot2", 0.3))
	for _, s in m.seats do
		s.presetTeam = if s.userId < 0 then 2 else 1
	end
	m.breakFor = 7
	expect(E.action(m, 7, { kind = "Start", epoch = m.epoch, turnId = m.turnId }, 0, 2))
	expect(teamOf(m, 7) == 1 and teamOf(m, 8) == 1, "the real players together")
	expect(teamOf(m, BOT) == 2 and teamOf(m, BOT - 1) == 2, "the robots together")
	expect(m.activeTeam == 1, "the real side breaks")
	for _, s in m.seats do
		expect(s.presetTeam == nil, "used once")
	end
end

local AIM = { Placement = true, Aiming = true }

-- Moves the clock on until someone has a shot to play (or the game is over).
local function toShot(m: any, now: number): number
	for _ = 1, 50 do
		if AIM[m.phase] or m.phase == "Result" then
			return now
		end
		now = math.max(now + 0.5, m.deadline or now)
		E.advance(m, now)
	end
	error("no shot came up")
end

tests["a bot's planned shot plays exactly the same on the table"] = function()
	-- Brain.simulate must follow the server's path (placement, ShotInput, the quantised seed),
	-- or a bot's chosen pot or scripted 8 can miss for real. Several random shots in a row,
	-- fouls and ball in hand included.
	local m = pad(false)
	expect(E.action(m, m.hostId, { kind = "Start", epoch = m.epoch, turnId = m.turnId }, 0, 1))
	local rng = Rng.new(99)
	local now = 0
	local compared, placed = 0, 0
	for _ = 1, 16 do
		now = toShot(m, now)
		if m.phase == "Result" then
			break
		end
		local view = {
			geometry = m.state.geometry,
			balls = Ball.cloneList(m.state.balls),
			groups = table.clone(m.groups),
			team = m.activeTeam,
			breakShot = m.breakShot == true,
		}
		local x, y = nil, nil
		if m.ballInHand then
			for _ = 1, 40 do
				local tx = Rng.range(rng, -40, 40)
				local ty = Rng.range(rng, -20, 20)
				if Placement.valid(m.state, tx, ty, m.breakShot) then
					x, y = tx, ty
					break
				end
			end
			placed += 1
		end
		local shot = {
			angle = Rng.range(rng, 0, 2 * math.pi),
			power = Rng.range(rng, 0.25, 0.95),
			spin = { x = 0, y = 0 },
		}
		local trial = Brain.simulate(view :: any, shot, x, y)
		local payload = {
			tableId = m.id,
			epoch = m.epoch,
			turnId = m.turnId,
			angle = shot.angle,
			power = shot.power,
			spin = shot.spin,
			cueX = x,
			cueY = y,
		}
		local result, why = E.acceptShot(m, m.shooter, payload, now)
		expect(result ~= nil, "the shot was accepted: " .. tostring(why))
		for _, real in m.pending.outcome.finalBalls do
			local mine
			for _, b in trial.balls do
				if b.id == real.id then
					mine = b
				end
			end
			expect(mine ~= nil, "ball " .. real.id)
			expect(
				mine.pocketed == real.pocketed
					and math.abs(mine.x - real.x) < 1e-9
					and math.abs(mine.y - real.y) < 1e-9,
				("ball %d ends in the same place"):format(real.id)
			)
		end
		compared += 1
	end
	expect(compared >= 8, "enough shots compared")
	expect(placed >= 1, "ball in hand was among them")
end

return tests
