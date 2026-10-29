--!strict
-- CuePreviewMath: the Cue Preview's panel at the four sizes, the camera that frames the focus
-- in the window's centre, and the loop's timeline (hw-gui lane; R7).

local H = require("./harness")

-- The menu screen (under Roblox's top bar) and the viewport (the whole window) per size.
local SIZES = {
	{
		name = "phone 844x390",
		screen = { w = 750, h = 311 },
		viewport = { w = 844, h = 390 },
		offset = { x = 47, y = 58 },
	},
	{
		name = "phone 844x332",
		screen = { w = 844, h = 332 },
		viewport = { w = 844, h = 390 },
		offset = { x = 0, y = 58 },
	},
	{
		name = "iPad 1024x768",
		screen = { w = 1024, h = 700 },
		viewport = { w = 1024, h = 768 },
		offset = { x = 0, y = 68 },
	},
	{
		name = "PC 1920x1080",
		screen = { w = 1920, h = 1022 },
		viewport = { w = 1920, h = 1080 },
		offset = { x = 0, y = 58 },
	},
}

local function inside(r: any, outer: any): boolean
	return r.x >= outer.x
		and r.y >= outer.y
		and r.x + r.w <= outer.x + outer.w
		and r.y + r.h <= outer.y + outer.h
end

local function touches(a: any, b: any): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

return {
	["the panel fits every size: a big window, 44 px buttons, nothing overlapping"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local C = Config.UI.CuePreview
		for _, size in SIZES do
			local p = M.panel(size.screen)
			local where = size.name
			H.expect(
				inside(p.panel, { x = 0, y = 0, w = size.screen.w, h = size.screen.h }),
				"panel inside: " .. where
			)
			H.expect(p.window.w >= C.WindowMinShare * p.panel.w, "window wide enough: " .. where)
			H.expect(p.window.h >= 200, "window 200 px tall: " .. where .. " " .. p.window.h)
			local pieces = { p.header, p.window, p.sheet }
			for _, r in pieces do
				H.expect(inside(r, p.panel), "inside the panel: " .. where)
			end
			for _, r in { p.name, p.pill, p.note, p.equip, p.tabs[1], p.tabs[2], p.tabs[3] } do
				H.expect(inside(r, p.sheet), "inside the sheet: " .. where)
			end
			for _, r in { p.equip, p.tabs[1], p.tabs[2], p.tabs[3] } do
				H.expect(r.h >= C.MinHitPx and r.w >= C.MinHitPx, "a 44 px button: " .. where)
			end
			H.expect(
				p.close.h >= 28 and inside(p.close, p.header),
				"the X in the header: " .. where
			)
			local list = { p.name, p.pill, p.note, p.tabs[1], p.tabs[2], p.tabs[3], p.equip }
			for i = 1, #list do
				for j = i + 1, #list do
					H.expect(
						not touches(list[i], list[j]),
						("sheet pieces %d and %d overlap: %s"):format(i, j, where)
					)
				end
			end
			H.expect(not touches(p.window, p.sheet), "window and sheet apart: " .. where)
			H.expect(inside(p.hint, p.window), "the hint on the window: " .. where)
		end
	end,

	["the camera puts the focus at the window's centre, at every size and turn"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local C = Config.UI.CuePreview
		local focus = { x = 2400, y = 2401, z = 0 }
		for _, size in SIZES do
			local p = M.panel(size.screen)
			local at = {
				x = p.window.x + p.window.w / 2 + size.offset.x,
				y = p.window.y + p.window.h / 2 + size.offset.y,
			}
			for _, yaw in { 0, 45, 137, 270 } do
				for _, pitch in { C.PitchMinDeg, 12, C.PitchMaxDeg } do
					for _, distance in { 4.5, 9 } do
						local eye, target =
							M.camera(focus, yaw, pitch, distance, C.FovDeg, size.viewport, at)
						local px, depth = M.project(focus, eye, target, C.FovDeg, size.viewport)
						H.expect(depth > 0, "in front")
						local err = math.sqrt((px.x - at.x) ^ 2 + (px.y - at.y) ^ 2)
						H.expect(
							err <= 4,
							("%s yaw %d pitch %d: %.2f px off"):format(size.name, yaw, pitch, err)
						)
					end
				end
			end
		end
	end,

	["the loop: TRAIL strokes, rolls, drops, holds the finisher; FINISHER rolls its last share"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local C = Config.UI.CuePreview
		local trail = M.timeline("Trail", nil)
		local names = {}
		for _, phase in trail do
			table.insert(names, phase.name)
		end
		H.expect(
			table.concat(names, " ") == "back hit roll drop finisher gap",
			table.concat(names, " ")
		)
		local total = C.StrokeBackSeconds
			+ C.StrokeHitSeconds
			+ C.RollSeconds
			+ C.DropSeconds
			+ C.FinisherHoldSeconds
			+ C.GapSeconds
		H.near(trail[#trail].to, total, 1e-9, "the loop's length")
		H.near(
			M.timeline("Trail", 3)[5].to - M.timeline("Trail", 3)[5].from,
			3,
			1e-9,
			"the cue's finisher length"
		)
		local fin = M.timeline("Finisher", nil)
		H.expect(fin[1].name == "roll" and #fin == 4, "FINISHER: roll, drop, finisher, gap")
		H.near(fin[1].to, C.RollSeconds * C.FinisherRollShare, 1e-9)
		local name, progress = M.phaseAt(trail, C.StrokeBackSeconds / 2)
		H.expect(name == "back" and math.abs(progress - 0.5) < 1e-9, "half way back")
		name = M.phaseAt(trail, total + 0.01)
		H.expect(name == "back", "it wraps")
		H.near(
			M.rollShare("Finisher", 0),
			1 - C.FinisherRollShare,
			1e-9,
			"the finisher's roll starts late"
		)
		H.near(M.rollShare("Trail", 0.5), 0.5, 1e-9)
		H.expect(M.easeOut(0) == 0 and M.easeOut(1) == 1 and M.easeOut(0.5) > 0.5, "eases out")
	end,

	["who may open it: every cue while Enabled, else only the event's cues while Event is on"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local Catalog = H.require("Progression.Catalog")
		local four = { "PitchforkCue", "WitchBroomCue", "JackOLanternCue", "HalloweenSwordCue" }
		local event = { Enabled = true, Cues = four }
		-- Switched on: every cue (My Cues and the Index), the event's too.
		local on = { Enabled = true, Event = event }
		H.expect(M.allowed(on, "Classic") and M.allowed(on, "WitchBroomCue"), "Enabled: every cue")
		-- Off, the event on: its four alone.
		local off = { Enabled = false, Event = event }
		for _, id in four do
			H.expect(M.allowed(off, id), "the event's cue: " .. id)
		end
		H.expect(not M.allowed(off, "Classic"), "not another cue")
		H.expect(not M.allowed(off, "CandyCornCue"), "not another Halloween cue")
		-- Both off, or no event row: none.
		H.expect(
			not M.allowed({ Enabled = false, Event = { Enabled = false, Cues = four } }, four[1])
		)
		H.expect(not M.allowed({ Enabled = false }, four[1]), "no event row")
		H.expect(not M.allowed(off, nil) and not M.allowed(off, 7), "not a cue id")
		-- As shipped: the preview off for all, on for the four, and the four are catalog cues.
		local C = Config.UI.CuePreview
		H.expect(C.Enabled == false, "the preview stays off for My Cues and the Index")
		H.expect(C.Event.Enabled == true and #C.Event.Cues == 4, "the event's switch is on")
		for _, id in four do
			H.expect(M.allowed(C, id), "shipped: " .. id)
			H.expect(Catalog.get(id) ~= nil, "a catalog cue: " .. id)
		end
		H.expect(not M.allowed(C, "Classic"), "shipped: no other cue")
	end,

	["a particle's climb: straight, under gravity, with Roblox's halving drag"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local F = Config.UI.CuePreview.Fit
		H.near(M.climb(6, 0, 0, 1), 6, 1e-6, "no drag, no lift: speed times life")
		H.near(M.climb(7, 0, -6, 2), 49 / 12, 0.15, "under gravity: its peak")
		local life = F.MaxLifeSeconds
		H.near(
			M.climb(4, 1, 0, 99),
			4 / math.log(2) * (1 - 2 ^ -life),
			0.1,
			"halving drag, life capped"
		)
		H.expect(M.climb(5, 0, 0, 0) == 0 and M.climb(0, 0, 0, 3) == 0, "nothing to climb")
	end,

	["a finisher's reach: its high sprites, fountains and creature count, sparks and sprays do not climb"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local CueSkins = H.require("CueSkins")
		local C = Config.UI.CuePreview
		local F = C.Fit
		local none = M.finisherReach(nil, nil)
		H.expect(none.top == F.TopStuds[1] and none.radius == F.RadiusStuds[1], "a plain burst")
		H.expect(none.seconds == 0, "no finisher of its own")
		-- A big sprite high over the pocket (the Broom's witch): at its height, its seen size.
		local witch = {
			Layers = {
				{
					Delay = 0.35,
					Host = { Kind = "Point", Offset = { 0, 3.4, 0 }, Size = 0 },
					Size = 5,
					Speed = { 0, 0 },
					Lifetime = { 1.05, 1.05 },
				},
			},
		}
		local w = M.finisherReach(witch, nil)
		H.near(w.top, 3.4 + 5 * F.SpriteShare / 2, 1e-9, "the witch's top")
		H.near(w.radius, 5 * F.SpriteShare / 2, 1e-9, "and its width")
		H.near(w.seconds, 1.4, 1e-9, "its delay and life")
		-- A narrow fountain climbs; the same as sparks, or sprayed every way, does not.
		local function one(size: number, spread: number): number
			local layer = { Size = size, Speed = 6, Lifetime = 1, SpreadAngle = { spread, spread } }
			return M.finisherReach({ Layers = { layer } }, nil).top
		end
		local climbs = 6 * F.ClimbShare + 0.6 * F.SpriteShare / 2
		H.near(one(0.6, 12), climbs, 1e-6, "a fountain climbs")
		H.expect(one(0.1, 12) == F.TopStuds[1], "sparks fly high but are not counted")
		H.expect(one(0.6, 180) == F.TopStuds[1], "a spray stays round its host")
		-- The creature at its highest rise and largest scale.
		local creature = { Parts = { { Offset = { 0.5, 1, 0 }, Size = { 1, 2, 1 } } } }
		local risen = M.finisherReach({
			Layers = {},
			Piece = {
				Piece = "x",
				Delay = 0.1,
				Seconds = 2,
				Rise = { { 0, -0.3 }, { 1, 1.5 } },
				Scale = { { 0, 0.5 }, { 1, 1.6 } },
			},
		}, creature)
		H.near(risen.top, 1.5 + 2 * 1.6, 1e-9, "risen and grown")
		H.near(risen.radius, 1 * 1.6, 1e-9, "its width grown")
		H.near(risen.seconds, 2.1, 1e-9, "its delay and length")
		-- Clamped.
		local tower = { Layers = { { Host = { Offset = { 0, 40, 0 } }, Size = 1 } } }
		H.expect(M.finisherReach(tower, nil).top == F.TopStuds[2], "never taller than TopStuds")
		-- The four Halloween cues (their rows may be rebuilt: only what any finisher shows).
		for _, id in Config.UI.CuePreview.Event.Cues do
			local pocket = CueSkins.get(id).Pocket
			local p = pocket and pocket.Piece
			local reach = M.finisherReach(pocket, p and CueSkins.piece(p.Piece))
			H.expect(
				reach.top > none.top and reach.top <= F.TopStuds[2],
				"taller than a burst: " .. id
			)
			H.expect(reach.radius >= F.RadiusStuds[1] and reach.radius <= F.RadiusStuds[2], id)
			H.expect(reach.seconds > 0, "a finisher of its own: " .. id)
			local hold = M.holdSeconds(reach.seconds)
			H.expect(hold >= math.min(reach.seconds, C.FinisherMaxSeconds), "held whole: " .. id)
		end
	end,

	["the loop holds a finisher its own length, never under the plain pace or over the cap"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local C = Config.UI.CuePreview
		H.expect(M.holdSeconds(nil) == C.FinisherHoldSeconds, "none: the plain pace")
		H.expect(M.holdSeconds(1) == C.FinisherHoldSeconds, "a short one: the plain pace")
		H.near(M.holdSeconds(3.1), 3.1, 1e-9, "a long one: its own")
		H.expect(M.holdSeconds(99) == C.FinisherMaxSeconds, "capped")
		local trail = M.timeline("Trail", M.holdSeconds(3.1))
		H.near(trail[5].to - trail[5].from, 3.1, 1e-9, "the timeline holds it")
	end,

	["a cue as drawn: a body past the butt and its 3D piece counted, a pocket creature not"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local CueSkins = H.require("CueSkins")
		local F = Config.UI.CuePreview.Fit
		local L = Config.Cue.CueLengthStuds
		local plain = M.cueSpan(L, {})
		H.expect(plain.from == 0 and plain.to == L and plain.across == F.CueAcrossStuds, "a stick")
		-- A body whose last part reaches 1.5 studs past the butt (the mesh frame: the tip +L/2).
		local body = {
			Frame = "cue",
			Parts = {
				{ Offset = { 0, 0, 0 }, Size = { 0.2, 0.2, L } },
				{ Offset = { 0, 0, -L / 2 - 0.75 }, Size = { 1.4, 1.2, 1.5 } },
			},
		}
		local drawn = M.cueSpan(L, { body })
		H.near(drawn.from, 0, 1e-9, "the tip at the tip")
		H.near(drawn.to, L + 1.5, 1e-9, "past the butt")
		H.near(drawn.across, 0.7, 1e-9, "its widest part")
		local creature =
			{ Frame = "pocket", Parts = { { Offset = { 0, 0, 40 }, Size = { 9, 9, 9 } } } }
		H.near(M.cueSpan(L, { creature }).to, L, 1e-9, "a pocket creature is not on the cue")
		-- The four Halloween cues' bodies: at least the stick, never far past it.
		for _, id in Config.UI.CuePreview.Event.Cues do
			local index = CueSkins.index(id)
			local rows = { CueSkins.piece(index.Body) }
			local row = CueSkins.get(id)
			if row.Piece then
				table.insert(rows, CueSkins.piece(row.Piece))
			end
			local span = M.cueSpan(L, rows)
			H.expect(span.to >= L and span.to <= L + 2, ("%s: %.2f long"):format(id, span.to))
			H.expect(math.abs(span.from) < 0.1, id .. ": the tip at the tip")
		end
	end,

	["the fitted camera keeps every point in the window all round the orbit, and no farther"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local C = Config.UI.CuePreview
		local F = C.Fit
		local focus = { x = 2405, y = 2404, z = 3 }
		-- A tall column off to one side and a roll on the cloth (TRAIL's kind of content).
		local points = {
			{ x = 2400, y = 2403, z = 0 },
			{ x = 2408, y = 2403, z = 4 },
			{ x = 2408, y = 2409, z = 4 },
			{ x = 2406, y = 2409, z = 6 },
			{ x = 2410, y = 2403, z = 2 },
		}
		for _, size in SIZES do
			local p = M.panel(size.screen)
			local W = p.window
			local at = { x = W.x + W.w / 2 + size.offset.x, y = W.y + W.h / 2 + size.offset.y }
			local half = { w = W.w / 2 * (1 - F.MarginShare), h = W.h / 2 * (1 - F.MarginShare) }
			for _, pitch in { 14, 30 } do
				local d = M.fitDistance(points, focus, pitch, C.FovDeg, size.viewport, at, half, 15)
				local function worst(distance: number): number
					local most = 0
					for yaw = 0, 345, 15 do
						local eye, target =
							M.camera(focus, yaw, pitch, distance, C.FovDeg, size.viewport, at)
						for _, q in points do
							local px, depth = M.project(q, eye, target, C.FovDeg, size.viewport)
							H.expect(depth > 0, "in front")
							most = math.max(
								most,
								math.abs(px.x - at.x) / half.w,
								math.abs(px.y - at.y) / half.h
							)
						end
					end
					return most
				end
				local where = ("%s pitch %d"):format(size.name, pitch)
				H.expect(worst(d) <= 1 + 1e-6, "all inside: " .. where)
				H.expect(worst(d * 0.97) > 1, "no farther than needed: " .. where)
			end
		end
		-- Only the focus to keep: never nearer than NearStuds.
		local only = M.fitDistance(
			{ focus },
			focus,
			20,
			C.FovDeg,
			SIZES[1].viewport,
			{ x = 300, y = 200 },
			{ w = 100, h = 80 },
			15
		)
		H.near(only, F.NearStuds, 1e-9, "the near limit")
	end,

	["TRAIL's camera eases to the finisher as the ball nears the pocket, holds, and comes back"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local F = Config.UI.CuePreview.Fit
		H.expect(M.follow("back", 0.5) == 0 and M.follow("hit", 1) == 0, "the stroke: on the roll")
		H.expect(
			M.follow("roll", 0) == 0 and M.follow("roll", F.FollowFrom) == 0,
			"the roll starts"
		)
		H.near(M.follow("roll", 1), 1, 1e-9, "at the pocket: on the finisher")
		local last = 0
		for i = 0, 20 do
			local w = M.follow("roll", i / 20)
			H.expect(w >= last - 1e-12, "it only eases over")
			last = w
		end
		H.expect(M.follow("drop", 0) == 1 and M.follow("finisher", 0.5) == 1, "holds on it")
		H.expect(M.follow("gap", 0) == 1 and M.follow("gap", 1) == 0, "back in the gap")
		H.expect(M.follow(nil, nil) == 0, "before the loop: on the roll")
	end,

	["the tab it opens on: the one asked for, else MODEL"] = function()
		local M = H.require("CuePreviewMath")
		H.expect(M.tabOf("Trail") == "Trail", "TRAIL (the event cards)")
		H.expect(M.tabOf("Finisher") == "Finisher" and M.tabOf("Model") == "Model")
		H.expect(M.tabOf(nil) == "Model", "none asked for")
		H.expect(M.tabOf("trail") == "Model" and M.tabOf(3) == "Model", "not a tab")
		H.expect(table.concat(M.Tabs, " ") == "Model Trail Finisher", "the row's order")
	end,

	["turning: a flick decays, the auto-turn waits, the pitch stays in its limits"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local C = Config.UI.CuePreview
		local yaw, spin = M.turn(10, 0, C.IdleResumeSeconds, 1)
		H.near(yaw, 10 + C.TurnDegPerSecond, 1e-9, "auto-turn")
		yaw, spin = M.turn(10, 0, 0, 1)
		H.expect(yaw == 10 and spin == 0, "no auto-turn right after a drag")
		local _, left = M.turn(0, 200, 0, 0.1)
		H.expect(left < 200 and left > 0, "a flick decays")
		H.expect(M.pitch(40, 30) == C.PitchMaxDeg and M.pitch(0, -90) == C.PitchMinDeg, "clamped")
		local y2 = M.turn(350, 0, 99, 1)
		H.expect(y2 >= 0 and y2 < 360, "yaw wraps")
	end,
}
