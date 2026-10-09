--!strict
-- Tutorial v2: how far the hidden help's pull (Effects/Magnet.pull, through Tutorial/Assist)
-- bends each ball on the turn-2 lesson shot, for model players (player.luau) at the planned
-- power: the first ball potted and the ricochet's second ball, in degrees of heading turned in
-- all. A bend the player can see breaks "they must never notice".
--
--   lune run tools/tutorial_v2/diag_bend.luau <options.json> [n]    (TUT_OWNPOWER=1: their own power)
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Sim = require("./sim")
local Player = require("./player")
local Ball = Sim.H.require("Physics.Ball")
local Judge = Sim.H.require("Rules.ShotJudge")
local Effects = Sim.H.require("Ults.Effects")
Effects.TutorialAssist = Sim.H.require("Tutorial.Assist")

local opts = serde.decode("json", fs.readFile(process.args[1]))
local N = tonumber(process.args[2]) or 200
local OWN_POWER = process.env.TUT_OWNPOWER == "1" -- the player's own power, not the plan's
local b = opts.breakShot
local t2 = opts.turn2
local D = Sim.D

-- Every ball's pull, from Tutorial/Assist's own record (fx.pulled: the sines of each step's
-- turn summed, so radians near enough).
local turned: { [number]: number } = {}

local rack = Sim.rack(b.seed, b.cueX, b.cueY)
local after = Ball.cloneList((Sim.play(rack, { angle = b.angle, power = b.power })).finalBalls)
local cue = Sim.find(after, 0) :: any
local pot = Sim.pot(after, cue.x, cue.y, Sim.find(after, t2.ball), Sim.pocket(t2.pocket)) :: any
local second = Sim.find(after, t2.second) :: any
local mx, my = Sim.mouth(Sim.pocket(t2.secondPocket))
local len = math.sqrt((mx - second.x) ^ 2 + (my - second.y) ^ 2)
local arm = Sim.magnet(after, "solids", nil)
arm.Effect = "TutorialAssist"
arm.extra.Ricochet = {
	x = second.x - (mx - second.x) / len * D,
	y = second.y - (my - second.y) / len * D,
	ball = t2.second,
}
arm.extra.Guard = true

local firstBends, secondBends = {}, {}
local potters, twice = 0, 0
local over = { 5, 10, 20, 30 }
for i = 1, N do
	table.clear(turned)
	local p = Player.new(1000 + i)
	local shot =
		{ angle = Player.aim(p, pot.angle, pot.angle + math.rad(3), true), power = t2.power }
	if OWN_POWER then
		shot.power = Player.power(p) -- the player's own pull instead of the planned power
	end
	local outcome, _, fx = Sim.play(after, shot, arm, true)
	for id, sum in (fx and fx.pulled) or {} do
		turned[id] = math.deg(sum)
	end
	local j = Sim.judge(after, outcome, nil, false, nil)
	local gotA, mine = false, {}
	for _, ball in outcome.finalBalls do
		if ball.pocketed and ball.id ~= 0 and not (Sim.find(after, ball.id) :: any).pocketed then
			gotA = gotA or ball.id == t2.ball
			if Judge.group(ball.id) == "solids" and ball.id ~= t2.ball then
				table.insert(mine, ball.id)
			end
		end
	end
	if gotA and j.keep and j.foul == nil then
		potters += 1
		table.insert(firstBends, turned[t2.ball] or 0)
		if #mine > 0 then
			twice += 1
			for _, id in mine do
				table.insert(secondBends, { id = id, deg = turned[id] or 0 })
			end
		end
	end
end

local function report(name: string, list: { number })
	table.sort(list)
	local n = #list
	if n == 0 then
		print(name .. ": none")
		return
	end
	local function q(f: number): number
		return list[math.clamp(math.floor(f * (n - 1) + 1.5), 1, n)]
	end
	local shares = {}
	for _, limit in over do
		local c = 0
		for _, v in list do
			if v > limit then
				c += 1
			end
		end
		table.insert(shares, ("over %d deg %.0f%%"):format(limit, 100 * c / n))
	end
	print(
		("%s (%d): median %.1f, p75 %.1f, p90 %.1f, max %.1f deg; %s"):format(
			name,
			n,
			q(0.5),
			q(0.75),
			q(0.9),
			list[n],
			table.concat(shares, ", ")
		)
	)
end

print(
	("%d players, %d pot ball %d (%.0f%%), %d of them a second solid (%.0f%%)"):format(
		N,
		potters,
		t2.ball,
		100 * potters / N,
		twice,
		if potters > 0 then 100 * twice / potters else 0
	)
)
report("first ball bend", firstBends)
local byId: { [number]: { number } } = {}
for _, row in secondBends do
	byId[row.id] = byId[row.id] or {}
	table.insert(byId[row.id], row.deg)
end
for id, list in byId do
	report(("second ball %d bend"):format(id), list)
end
