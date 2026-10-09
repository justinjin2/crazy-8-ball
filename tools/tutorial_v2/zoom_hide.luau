--!strict
-- Tutorial v2 layout search, part 3: for each turn-2 candidate (eval_turn2.luau's lines), how
-- many zoom notches in from the home view (Input.ZoomStep each) first hide its pocket on a PC
-- (16:9) and on a phone (2.16:1, whose home is already a notch in), and whether the object
-- ball and cue ball still show there. A lesson that opens that close and asks to zoom out.
--
--   lune run tools/tutorial_v2/zoom_hide.luau <turn2.jsonl> <out.jsonl>
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Sim = require("./sim")
local Cam = require("./camera")

local V = Sim.Config.Camera.View
local STEP = Sim.Config.Input.ZoomStep
local HEADER = { pc = 0.08, phone = 0.14 }

local lines = {}
for line in fs.readFile(process.args[1]):gmatch("[^\n]+") do
	local row = serde.decode("json", line)
	for _, c in row.candidates do
		local mx, my = Sim.mouth(Sim.pocket(c.pocket))
		local res: any = {}
		for _, which in { "pc", "phone" } do
			local phone = which == "phone"
			local aspect = if phone then Cam.PhoneAspect else Cam.PcAspect
			local home = Cam.homeZoom(phone)
			res[which] = nil
			for k = 0, 12 do
				local z = home / STEP ^ k
				if z < V.ZoomMin - 1e-9 then
					break
				end
				local cf = Cam.view(row.cue[1], row.cue[2], c.angle, z, aspect)
				local q = Cam.screenOf(cf, aspect, mx, my)
				if Cam.inside(q, HEADER[which]) < 0 then
					res[which] = k
					break
				end
			end
		end
		table.insert(
			lines,
			Sim.json({
				seed = row.seed,
				dy = row.dy,
				turn = row.turn,
				power = row.power,
				ball = c.ball,
				pocket = c.pocket,
				notchesPc = res.pc,
				notchesPhone = res.phone,
			})
		)
	end
end
fs.writeFile(process.args[2], table.concat(lines, "\n") .. "\n")
