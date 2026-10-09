--!strict
-- Tutorial v2 layout search, part 1 (docs/prompts/TUTORIAL_V2_PROMPT.md 5.1): rigged breaks
-- that look like every other break (the cue ball on the head spot, aimed straight at the
-- apex) up to invisible differences, and pot exactly 2 solids (no stripe, no 8, no scratch).
-- Each one found is written as a JSON line with how slowly its second ball drops, where the
-- 8 and the cue ball stop, and every ball's final spot.
--
--   lune run tools/tutorial_v2/search_breaks.luau <seedFrom> <seedCount> <out.jsonl>
--
-- "Invisible" (the brief: define it and stay under it): the cue ball within 0.25 in of the
-- head spot (a ninth of a ball across: a pixel or two at the break view) and the aim within
-- 0.15 degrees of dead straight at the apex ball (0.13 in at the apex, 6% of a ball); the rack
-- seed only moves balls by its 0.001 in jitter. Full power, no spin.
local fs = require("@lune/fs")
local process = require("@lune/process")
local Sim = require("./sim")
local Judge = Sim.H.require("Rules.ShotJudge")

local from = tonumber(process.args[1]) or 1
local count = tonumber(process.args[2]) or 10
local out = process.args[3] or "breaks.jsonl"

local OFFSETS = { -0.25, -0.125, 0, 0.125, 0.25 } -- across the table (y), inches
local TURNS_DEG = { -0.15, -0.075, 0, 0.075, 0.15 }
local POWERS = { 1, 0.95 }

local lines = {}
local tried, found = 0, 0
local clock = os.clock()
for seed = from, from + count - 1 do
	for _, dy in OFFSETS do
		for _, turn in TURNS_DEG do
			for _, power in POWERS do
				tried += 1
				local cx, cy = Sim.headX, Sim.headY + dy
				local angle = math.atan2(Sim.footY - cy, Sim.footX - cx) + math.rad(turn)
				local balls = Sim.rack(seed, cx, cy)
				local outcome = Sim.play(balls, { angle = angle, power = power })
				local down, scratch = Sim.down(outcome)
				if scratch or #down ~= 2 then
					continue
				end
				local solids = 0
				for _, id in down do
					if Judge.group(id) == "solids" then
						solids += 1
					end
				end
				if solids ~= 2 then
					continue
				end
				local j = Sim.judge(balls, outcome, nil, true, nil)
				if j.foul ~= nil or j.winner ~= nil or not j.keep then
					continue
				end
				-- Traced again to see how each ball dropped.
				local traced, paths = Sim.play(balls, { angle = angle, power = power }, nil, true)
				local drops = {}
				for _, ev in traced.events do
					if ev.type == "pocket" and ev.ball ~= 0 then
						local feel = Sim.dropFeel((paths :: any)[ev.ball], 2)
						table.insert(drops, {
							ball = ev.ball,
							pocket = ev.other,
							t = ev.t,
							near = feel.nearSeconds,
							tip = feel.tipSeconds,
							speed = feel.speed,
						})
					end
				end
				local final = {}
				for _, b in outcome.finalBalls do
					if not b.pocketed then
						table.insert(final, {
							b.id,
							math.floor(b.x * 1000 + 0.5) / 1000,
							math.floor(b.y * 1000 + 0.5) / 1000,
						})
					end
				end
				found += 1
				table.insert(
					lines,
					Sim.json({
						seed = seed,
						dy = dy,
						turn = turn,
						power = power,
						cx = cx,
						cy = cy,
						angle = angle,
						down = down,
						drops = drops,
						duration = outcome.duration,
						balls = final,
					})
				)
			end
		end
	end
end
fs.writeFile(out, table.concat(lines, "\n") .. (if #lines > 0 then "\n" else ""))
print(
	("seeds %d..%d: %d breaks in %.1f s, %d with exactly 2 solids"):format(
		from,
		from + count - 1,
		tried,
		os.clock() - clock,
		found
	)
)
