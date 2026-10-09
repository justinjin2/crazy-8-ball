--!strict
-- Tutorial v2 layout search, part 2 (docs/prompts/TUTORIAL_V2_PROMPT.md 5.1): for each
-- rigged break found by search_breaks.luau, the turn-2 shot it leaves (the aim and zoom
-- lesson): a solid close to a pocket, a small cut, both lines clear, and that pocket hard to
-- see at the home view (Camera.viewFor's framing, PC 16:9 and a 2.16:1 phone). Each candidate
-- is played on a small grid of new-player shots (aim errors x powers) with the hidden help
-- (Tutorial/Assist), counting the pots, the natural ricochets (a second solid down in the same shot), the
-- scratches and the 8's moves. Also scores where the break left the 8.
--
--   lune run tools/tutorial_v2/eval_turn2.luau <breaks.jsonl> <part> <parts> <out.jsonl>
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Sim = require("./sim")
local Cam = require("./camera")
local Ball = Sim.H.require("Physics.Ball")
local Judge = Sim.H.require("Rules.ShotJudge")
local Effects = Sim.H.require("Ults.Effects")
Effects.TutorialAssist = Sim.H.require("Tutorial.Assist")

local file = process.args[1]
local part = tonumber(process.args[2]) or 0
local parts = tonumber(process.args[3]) or 1
local out = process.args[4] or "turn2.jsonl"

local CUT_MAX, TO_POCKET_MAX, GHOST_MIN, GHOST_MAX = 30, 14, 6, 95
local AIM_ERRORS = { -1.5, -0.75, 0, 0.75, 1.5 }
local POWERS = { 0.2, 0.3, 0.45, 0.6, 0.8 }
-- The match header's band at the top of the screen (a share of the half height): the
-- phone's is deeper. A point under it reads as off screen.
local HEADER = { pc = 0.08, phone = 0.14 }

local function ballsOf(rows: { any }): { any }
	local list = {}
	local present = {}
	for _, row in rows do
		present[row[1]] = true
		table.insert(list, Ball.new(row[1], row[2], row[3]))
	end
	for id = 0, 15 do
		if not present[id] then
			local b = Ball.new(id, 0, 0)
			b.pocketed = true
			table.insert(list, b)
		end
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

-- Where the 8 sits: its nearest pocket mouth (any kind), whether the line is clear, how far
-- it is from every other ball.
local function eightSpot(balls: { any }): any
	local eight = Sim.find(balls, 8) :: any
	local best, which, clear = math.huge, nil, false
	for _, p in Sim.geometry.pockets do
		local mx, my = Sim.mouth(p)
		local d = math.sqrt((eight.x - mx) ^ 2 + (eight.y - my) ^ 2)
		if d < best then
			best, which = d, p.id
			clear = Sim.clear(balls, { [8] = true, [0] = true }, eight.x, eight.y, mx, my)
		end
	end
	local lonely = math.huge
	for _, b in balls do
		if not b.pocketed and b.id ~= 8 then
			lonely = math.min(lonely, math.sqrt((b.x - eight.x) ^ 2 + (b.y - eight.y) ^ 2))
		end
	end
	local corner = which ~= nil and Sim.pocket(which).x ~= 0
	return {
		gap = best,
		pocket = which,
		clear = clear,
		lonely = lonely,
		corner = corner,
		x = eight.x,
		y = eight.y,
	}
end

local text = fs.readFile(file)
local lines = {}
local index = 0
local clock = os.clock()
local candidatesTried = 0
for line in text:gmatch("[^\n]+") do
	index += 1
	if (index - 1) % parts ~= part then
		continue
	end
	local brk = serde.decode("json", line)
	local balls = ballsOf(brk.balls)
	local cue = Sim.find(balls, 0) :: any
	local eight = eightSpot(balls)
	local found = {}
	for _, pot in Sim.pots(balls, "solids", true) do
		if pot.cut > CUT_MAX or pot.toPocket > TO_POCKET_MAX then
			continue
		end
		if pot.toGhost < GHOST_MIN or pot.toGhost > GHOST_MAX then
			continue
		end
		-- The pocket at the home view, aimed along the pot.
		local mx, my = Sim.mouth(Sim.pocket(pot.pocket))
		local seen = {}
		for _, which in { "pc", "phone" } do
			local phone = which == "phone"
			local aspect = if phone then Cam.PhoneAspect else Cam.PcAspect
			local cf = Cam.view(cue.x, cue.y, pot.angle, Cam.homeZoom(phone), aspect)
			local q = Cam.screenOf(cf, aspect, mx, my)
			seen[which] = Cam.inside(q, HEADER[which])
			seen[which .. "At"] = if q
				then { math.floor(q.x * 1000 + 0.5) / 1000, math.floor(q.y * 1000 + 0.5) / 1000 }
				else nil
			-- Fully zoomed out the whole table shows (the lesson's answer).
			local whole = Cam.view(cue.x, cue.y, pot.angle, 1, aspect)
			seen[which .. "Whole"] = Cam.inside(Cam.screenOf(whole, aspect, mx, my), HEADER[which])
		end
		candidatesTried += 1
		-- The grid of new-player shots, with the hidden help on.
		local arm = Sim.magnet(balls, "solids", nil)
		arm.Effect = "TutorialAssist" -- the hidden help as built (Config.Tutorial.Assist.Pull)
		local n, potted, twice, scratch, eightMoved, fouls = 0, 0, 0, 0, 0, 0
		local seconds: { [number]: number } = {}
		for _, err in AIM_ERRORS do
			for _, power in POWERS do
				n += 1
				local outcome =
					Sim.play(balls, { angle = pot.angle + math.rad(err), power = power }, arm)
				local down, scr = Sim.down(outcome)
				local fresh = {}
				for _, id in down do
					if not (Sim.find(balls, id) :: any).pocketed then
						table.insert(fresh, id)
					end
				end
				down = fresh
				local j = Sim.judge(balls, outcome, nil, false, nil)
				local mine = 0
				local gotA = false
				for _, id in down do
					if Judge.group(id) == "solids" then
						mine += 1
					end
					if id == pot.ball then
						gotA = true
					end
				end
				if scr then
					scratch += 1
				end
				if j.foul then
					fouls += 1
				end
				if gotA and j.keep and not scr then
					potted += 1
					if mine >= 2 then
						twice += 1
						for _, id in down do
							if id ~= pot.ball and Judge.group(id) == "solids" then
								seconds[id] = (seconds[id] or 0) + 1
							end
						end
					end
				end
				local e8 = Sim.find(outcome.finalBalls, 8) :: any
				if e8.pocketed or math.sqrt((e8.x - eight.x) ^ 2 + (e8.y - eight.y) ^ 2) > 1 then
					eightMoved += 1
				end
			end
		end
		table.insert(found, {
			ball = pot.ball,
			pocket = pot.pocket,
			angle = pot.angle,
			cut = pot.cut,
			toGhost = pot.toGhost,
			toPocket = pot.toPocket,
			seen = seen,
			n = n,
			pot = potted / n,
			ricochet = if potted > 0 then twice / potted else 0,
			seconds = seconds,
			scratch = scratch / n,
			fouls = fouls / n,
			eightMoved = eightMoved / n,
		})
	end
	table.insert(
		lines,
		Sim.json({
			seed = brk.seed,
			dy = brk.dy,
			turn = brk.turn,
			power = brk.power,
			drops = brk.drops,
			cue = { cue.x, cue.y },
			eight = eight,
			candidates = found,
		})
	)
end
fs.writeFile(out, table.concat(lines, "\n") .. (if #lines > 0 then "\n" else ""))
print(
	("part %d/%d: %d breaks, %d candidates in %.1f s"):format(
		part,
		parts,
		#lines,
		candidatesTried,
		os.clock() - clock
	)
)
