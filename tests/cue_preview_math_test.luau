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

-- The showcase's stage as CuePreview builds it (Config.UI.CuePreview.Origin; the 9-foot table,
-- the foot rail's corner pocket, the ball StartShare back along its diagonal, the floating cue
-- LiftStuds over the stage), a tall finisher and the window at `size`.
local function showcaseStage(size: any, reach: any?)
	local M = H.require("CuePreviewMath")
	local Config = H.require("Config")
	local C = Config.UI.CuePreview
	local S = C.Showcase
	local spi = Config.Table.StudsPerInch
	local o = { x = C.Origin[1], y = C.Origin[2], z = C.Origin[3] }
	local cloth = o.y + Config.Table.SurfaceHeightStuds
	local r = Config.Balls.RenderRadiusInches * spi
	local px, pz = 50 * spi, 25 * spi -- the corner pocket (+x, -y in the table's own frame)
	local pocket = { x = o.x + px, y = cloth + r, z = o.z + pz }
	local back = S.StartShare
	local start = { x = o.x + px * (1 - back), y = cloth + r, z = o.z + pz * (1 - back) }
	local scene = {
		spot = { x = o.x, y = o.y + S.Model.LiftStuds, z = o.z },
		start = start,
		pocket = pocket,
		ball = start,
		cloth = cloth,
		span = M.cueSpan(Config.Cue.CueLengthStuds, {}),
		reach = reach or { top = 6, radius = 2, seconds = 3 },
	}
	local p = M.showcasePanel(size.screen)
	local window = {
		x = p.window.x + size.offset.x,
		y = p.window.y + size.offset.y,
		w = p.window.w,
		h = p.window.h,
	}
	local view = {
		viewport = size.viewport,
		at = { x = window.x + window.w / 2, y = window.y + window.h / 2 },
		half = {
			w = window.w / 2 * (1 - C.Fit.MarginShare),
			h = window.h / 2 * (1 - C.Fit.MarginShare),
		},
		windowH = window.h,
	}
	return scene, window, view
end

-- Where `shot` puts its camera (the eye, the point it looks at, the camera's field of view).
local function aim(shot: any, view: any): (any, any, number)
	local M = H.require("CuePreviewMath")
	local fov = M.cameraFov(shot.fovDeg, view.viewport.h, view.windowH)
	local eye, target =
		M.camera(shot.focus, shot.yaw, shot.pitch, shot.distance, fov, view.viewport, view.at)
	return eye, target, fov
end

-- The ball where the client puts it at `beat` (rolled `beat.roll` of its path).
local function ballAt(scene: any, beat: any): any
	local a, b = scene.start, scene.pocket
	return {
		x = a.x + (b.x - a.x) * beat.roll,
		y = a.y,
		z = a.z + (b.z - a.z) * beat.roll,
	}
end

local function within(px: any, window: any, slack: number?): boolean
	local e = slack or 0
	return px.x >= window.x - e
		and px.x <= window.x + window.w + e
		and px.y >= window.y - e
		and px.y <= window.y + window.h + e
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
		-- Reduce Motion: it never turns on its own.
		local y3, s3 = M.turn(10, 0, 99, 1, true)
		H.expect(y3 == 10 and s3 == 0, "no auto-turn with Reduce Motion")
		local y4, s4 = M.turn(10, 300, 0, 0.1, true)
		H.expect(y4 == 10 and s4 == 0, "no flick's spin with Reduce Motion")
	end,
	["the showcase plays for the event cards while it is on; off, or opened elsewhere, the tabs"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local on = { Showcase = { Enabled = true, From = { "Halloween" } } }
		local off = { Showcase = { Enabled = false, From = { "Halloween" } } }
		H.expect(M.modeOf(on, "Halloween") == "Showcase", "the event cards")
		H.expect(M.modeOf(on, "Cues") == "Tabs" and M.modeOf(on, nil) == "Tabs", "anyone else")
		H.expect(M.modeOf(on, "Cues", "Showcase") == "Showcase", "asked for")
		H.expect(M.modeOf(on, "Halloween", "Tabs") == "Tabs", "the tabs asked for")
		H.expect(M.modeOf(off, "Halloween") == "Tabs", "switched off: today's tabs")
		H.expect(M.modeOf(off, "Halloween", "Showcase") == "Tabs", "off wins over asking")
		H.expect(
			M.modeOf(nil, "Halloween") == "Tabs" and M.modeOf({}, "Halloween") == "Tabs",
			"none"
		)
		H.expect(
			M.modeOf(Config.UI.CuePreview, "Halloween") == "Showcase",
			"shipped: the Halloween cards play the showcase"
		)
	end,

	["the showcase's loop: the model, the trail, the finisher held its own length, then again"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local C = Config.UI.CuePreview
		local S = C.Showcase
		local hold = M.holdSeconds(3.4)
		local tl = M.showcaseTimeline(hold)
		H.expect(#tl == 3, "three segments")
		H.expect(
			tl[1].name == "model" and tl[2].name == "trail" and tl[3].name == "finisher",
			"order"
		)
		H.near(tl[1].to - tl[1].from, S.Model.Seconds, 1e-9, "the model's length")
		H.near(tl[2].to - tl[2].from, S.Trail.Seconds, 1e-9, "the trail's length")
		H.near(
			tl[3].to - tl[3].from,
			S.Finisher.LeadSeconds + C.DropSeconds + hold + S.Finisher.TailSeconds,
			1e-9,
			"the finisher holds the cue's finisher whole"
		)
		H.near(
			M.showcaseTimeline(nil)[3].to - M.showcaseTimeline(nil)[3].from,
			S.Finisher.LeadSeconds + C.DropSeconds + C.FinisherHoldSeconds + S.Finisher.TailSeconds,
			1e-9,
			"a plain burst's pace"
		)
		local total = tl[3].to
		local b = M.showcaseBeat(tl, 0.4)
		H.expect(b.segment == "model" and b.phase == "none" and b.loop == 0, "starts on the model")
		b = M.showcaseBeat(tl, tl[2].from + C.StrokeBackSeconds / 2)
		H.expect(b.segment == "trail" and b.phase == "back" and b.roll == 0, "the stroke")
		b = M.showcaseBeat(tl, tl[2].from + C.StrokeBackSeconds + C.StrokeHitSeconds / 2)
		H.expect(b.phase == "hit" and b.roll == 0, "the hit")
		-- The roll goes on across the cut, never back, and ends over the pocket.
		local last = -1
		local t = tl[2].from + C.StrokeBackSeconds + C.StrokeHitSeconds
		while t < tl[3].from + S.Finisher.LeadSeconds do
			local beat = M.showcaseBeat(tl, t)
			H.expect(beat.phase == "roll", "rolling at " .. t)
			H.expect(beat.roll >= last - 1e-9, "never back at " .. t)
			last = beat.roll
			t += 1 / 30
		end
		local before = M.showcaseBeat(tl, tl[3].from - 1e-6)
		local after = M.showcaseBeat(tl, tl[3].from + 1e-6)
		H.expect(before.segment == "trail" and after.segment == "finisher", "the cut")
		H.near(before.roll, after.roll, 1e-4, "the ball rolls on across the cut")
		H.expect(
			after.roll > 0.6 and after.roll < 0.97,
			"the cut: most of the roll done, the pocket ahead"
		)
		b = M.showcaseBeat(tl, tl[3].from + S.Finisher.LeadSeconds + C.DropSeconds / 2)
		H.expect(b.phase == "drop" and b.roll == 1, "the drop over the pocket")
		b = M.showcaseBeat(tl, tl[3].from + S.Finisher.LeadSeconds + C.DropSeconds + hold / 2)
		H.expect(b.phase == "finisher", "the finisher")
		b = M.showcaseBeat(tl, total - S.Finisher.TailSeconds / 2)
		H.expect(b.phase == "tail", "its fade")
		b = M.showcaseBeat(tl, total + 0.2)
		H.expect(b.segment == "model" and b.loop == 1, "then the model again, one loop done")
		H.expect(M.rollAt(0) == 0 and math.abs(M.rollAt(1) - 1) < 1e-9, "the roll's ends")
		H.expect(M.rollAt(1) - M.rollAt(0.98) > 0.004, "still rolling as it drops")
	end,

	["the showcase waits at the model's cut for the cue's shot effects, then plays on"] = function()
		local M = H.require("CuePreviewMath")
		local tl = M.showcaseTimeline(nil)
		local cut = tl[1].to
		local t, waiting = M.showcaseAdvance(tl, cut - 0.1, 0.2, false)
		H.expect(waiting and t < cut and t > cut - 0.01, "waits just before the cut")
		local t2, still = M.showcaseAdvance(tl, t, 0.5, false)
		H.expect(still and t2 == t, "and keeps waiting")
		local t3, w3 = M.showcaseAdvance(tl, t2, 0.1, true)
		H.expect(not w3 and t3 > cut, "the effects are in: the trail")
		local t4, w4 = M.showcaseAdvance(tl, tl[2].from + 0.5, 0.1, false)
		H.expect(not w4 and math.abs(t4 - (tl[2].from + 0.6)) < 1e-9, "never waits past the cut")
		local total = tl[3].to
		local t5, w5 = M.showcaseAdvance(tl, total + cut - 0.05, 0.1, false)
		H.expect(w5 and t5 > total and t5 < total + cut, "every loop's model waits too")
		local t6 = M.showcaseAdvance(tl, 1, 0.1, false)
		H.near(t6, 1.1, 1e-9, "the model plays meanwhile")
	end,

	["the showcase's panel: one 16:9 screen as big as fits, the X in its header, the line under it"] = function()
		local M = H.require("CuePreviewMath")
		for _, size in SIZES do
			local where = size.name
			local p = M.showcasePanel(size.screen)
			local screen = { x = 0, y = 0, w = size.screen.w, h = size.screen.h }
			H.expect(inside(p.panel, screen), "panel inside: " .. where)
			H.expect(math.abs(p.window.w / p.window.h - 16 / 9) < 0.01, "16:9: " .. where)
			H.expect(
				inside(p.window, p.panel) and inside(p.line, p.panel),
				"screen and line in it: " .. where
			)
			H.expect(
				inside(p.close, p.header) and inside(p.title, p.header),
				"X and title in the header: " .. where
			)
			H.expect(not touches(p.title, p.close), "the title clear of the X: " .. where)
			H.expect(
				p.line.y >= p.window.y + p.window.h and p.line.w == p.window.w,
				"the line under it: " .. where
			)
			H.expect(not touches(p.header, p.window), "the header over the screen: " .. where)
			H.expect(
				p.window.h >= 0.6 * size.screen.h,
				"the screen fills the height: " .. where .. " " .. p.window.h
			)
		end
		local pc = M.showcasePanel({ w = 1920, h = 1022 })
		H.expect(pc.window.w >= 1150, "a PC's screen is big: " .. pc.window.w)
		local phone = M.showcasePanel({ w = 844, h = 332 })
		H.expect(phone.short and phone.window.w >= 420, "a phone's too: " .. phone.window.w)
	end,

	["the camera is widened so the screen shows its own field of view"] = function()
		local M = H.require("CuePreviewMath")
		H.near(M.cameraFov(40, 1080, 1080), 40, 1e-9, "a whole-view window")
		H.expect(M.cameraFov(40, 1080, 540) > 40, "a smaller window: a wider camera")
		H.expect(M.cameraFov(170, 1080, 100) <= 120, "Roblox's cap")
		-- A point 20 degrees over the camera's axis lands on the edge of a 40-degree window.
		local viewport = { w = 1920, h = 1080 }
		local fov = M.cameraFov(40, viewport.h, 540)
		local eye = { x = 0, y = 0, z = 10 }
		local target = { x = 0, y = 0, z = 0 }
		local up = 10 * math.tan(math.rad(20))
		local px = M.project({ x = 0, y = up, z = 0 }, eye, target, fov, viewport)
		H.near(px.y, viewport.h / 2 - 270, 0.5, "the window's top edge")
	end,

	["the showcase's model: the cue alone, large and diagonal, and no table in the screen"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local C = Config.UI.CuePreview
		local spi = Config.Table.StudsPerInch
		-- The table's footprint with its rails, and its rails' top (rough, generous).
		local halfX = (Config.Table.LengthInches / 2 + Config.Table.RailWidthInches) * spi + 0.5
		local halfZ = (Config.Table.WidthInches / 2 + Config.Table.RailWidthInches) * spi + 0.5
		for _, size in SIZES do
			local scene, window, view = showcaseStage(size)
			local tl = M.showcaseTimeline(M.holdSeconds(3))
			local fits = M.showcaseFits(scene, tl, view)
			local railTop = scene.cloth + 0.6
			for _, u in { 0, 0.25, 0.5, 0.75, 1 } do
				local beat = M.showcaseBeat(tl, u * (tl[1].to - 1e-6))
				H.expect(beat.segment == "model", "the model")
				local shot = M.showcaseShot(scene, beat, fits, false)
				local eye, target, fov = aim(shot, view)
				local right, upv, forward = M.basis(eye, target)
				local k = view.viewport.h / (2 * math.tan(math.rad(fov) / 2))
				-- Every ray through the window's edge stays off the table.
				for _, corner in
					{
						{ window.x, window.y + window.h },
						{ window.x + window.w, window.y + window.h },
						{ window.x + window.w / 2, window.y + window.h },
						{ window.x, window.y },
					}
				do
					local sx = (corner[1] - view.viewport.w / 2) / k
					local sy = (corner[2] - view.viewport.h / 2) / k
					local d = {
						x = forward.x + right.x * sx - upv.x * sy,
						y = forward.y + right.y * sx - upv.y * sy,
						z = forward.z + right.z * sx - upv.z * sy,
					}
					if d.y < 0 then
						local s = (railTop - eye.y) / d.y
						local hx, hz = eye.x + d.x * s, eye.z + d.z * s
						local onTable = math.abs(hx - C.Origin[1]) < halfX
							and math.abs(hz - C.Origin[3]) < halfZ
						H.expect(not onTable, ("%s u %.2f: the table shows"):format(size.name, u))
					end
				end
				-- Large and diagonal: the tip up-right, the butt down-left (as the cards), wide across.
				local a = M.showcaseAxis()
				local mid = (scene.span.from + scene.span.to) / 2
				local function at(along: number): any
					return {
						x = scene.spot.x + a.x * (along - mid),
						y = scene.spot.y + a.y * (along - mid),
						z = scene.spot.z + a.z * (along - mid),
					}
				end
				local tip = M.project(at(scene.span.from), eye, target, fov, view.viewport)
				local butt = M.project(at(scene.span.to), eye, target, fov, view.viewport)
				H.expect(
					tip.x > butt.x and tip.y < butt.y,
					size.name .. ": tip up-right, butt down-left"
				)
				H.expect(
					within(tip, window, 2) and within(butt, window, 2),
					("%s u %.2f: both ends in the screen (a head past the butt stays whole)"):format(
						size.name,
						u
					)
				)
				local slope = math.deg(math.atan2(butt.y - tip.y, tip.x - butt.x))
				H.expect(
					slope > 10 and slope < 35,
					("%s: diagonal, %.1f deg"):format(size.name, slope)
				)
				H.expect(
					math.abs(butt.x - tip.x) >= 0.7 * window.w,
					("%s u %.2f: large (%.0f of %d px)"):format(
						size.name,
						u,
						tip.x - butt.x,
						window.w
					)
				)
			end
		end
	end,

	["the showcase's trail: a low camera following the ball; its finisher: the pocket, then the whole column"] = function()
		local M = H.require("CuePreviewMath")
		local Config = H.require("Config")
		local C = Config.UI.CuePreview
		local S = C.Showcase
		for _, size in SIZES do
			local scene, window, view = showcaseStage(size)
			local tl = M.showcaseTimeline(M.holdSeconds(3))
			local fits = M.showcaseFits(scene, tl, view)
			local dx, dz = scene.pocket.x - scene.start.x, scene.pocket.z - scene.start.z
			local len = math.sqrt(dx * dx + dz * dz)
			local t = tl[2].from
			while t < tl[2].to do
				local beat = M.showcaseBeat(tl, t)
				scene.ball = ballAt(scene, beat)
				local shot = M.showcaseShot(scene, beat, fits, false)
				local eye, target, fov = aim(shot, view)
				-- It follows the ball: its focus a fixed step ahead of it.
				H.near(
					shot.focus.x - scene.ball.x,
					dx / len * S.Trail.AheadStuds,
					1e-6,
					"follows x"
				)
				H.near(
					shot.focus.z - scene.ball.z,
					dz / len * S.Trail.AheadStuds,
					1e-6,
					"follows z"
				)
				local px, depth = M.project(scene.ball, eye, target, fov, view.viewport)
				H.expect(
					depth > 0 and within(px, window),
					("%s t %.2f: the ball in the screen"):format(size.name, t)
				)
				local over = eye.y - scene.cloth
				H.expect(
					over > 0.3,
					("%s t %.2f: over the cloth (%.2f)"):format(size.name, t, over)
				)
				if
					beat.phase == "roll"
					and beat.at > C.StrokeBackSeconds + C.StrokeHitSeconds + S.Trail.EaseSeconds
				then
					H.expect(
						over < 1.2,
						("%s t %.2f: low by the cloth (%.2f)"):format(size.name, t, over)
					)
				end
				t += 0.1
			end
			-- FINISHER: the ball comes into the shot; once pulled back, the whole column shows.
			local arrive = M.showcaseBeat(tl, tl[3].from + 0.05)
			scene.ball = ballAt(scene, arrive)
			local eye, target, fov = aim(M.showcaseShot(scene, arrive, fits, false), view)
			local px, depth = M.project(scene.ball, eye, target, fov, view.viewport)
			H.expect(depth > 0 and within(px, window), size.name .. ": the ball rolls in")
			local full = M.showcaseBeat(tl, tl[3].from + S.Finisher.PullSeconds + 0.1)
			H.expect(full.phase == "finisher", "the finisher plays")
			eye, target, fov = aim(M.showcaseShot(scene, full, fits, false), view)
			local r, top = scene.reach.radius, scene.reach.top
			for _, h in { 0, top } do
				for _, off in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
					local p = {
						x = scene.pocket.x + off[1] * r,
						y = scene.cloth + h,
						z = scene.pocket.z + off[2] * r,
					}
					local q = M.project(p, eye, target, fov, view.viewport)
					H.expect(
						within(q, window, 2),
						("%s: the finisher whole (h %.1f)"):format(size.name, h)
					)
				end
			end
			-- A low camera: by the cloth as the ball arrives, never over the finisher's top.
			local low = aim(M.showcaseShot(scene, arrive, fits, false), view)
			H.expect(low.y - scene.cloth < 3.5, size.name .. ": low as the ball arrives")
			H.expect(eye.y - scene.cloth < top, size.name .. ": under the finisher's top")
		end
	end,

	["with Reduce Motion each showcase camera holds still: cuts only"] = function()
		local M = H.require("CuePreviewMath")
		local scene, _, view = showcaseStage(SIZES[4])
		local tl = M.showcaseTimeline(M.holdSeconds(3))
		local fits = M.showcaseFits(scene, tl, view)
		for _, seg in tl do
			local first: any = nil
			for _, u in { 0.02, 0.3, 0.6, 0.98 } do
				local beat = M.showcaseBeat(tl, seg.from + u * (seg.to - seg.from))
				scene.ball = ballAt(scene, beat)
				local shot = M.showcaseShot(scene, beat, fits, true)
				local moving = M.showcaseShot(scene, beat, fits, false)
				if first == nil then
					first = shot
				else
					for _, key in { "x", "y", "z" } do
						H.near(shot.focus[key], first.focus[key], 1e-9, seg.name .. " focus still")
					end
					H.near(shot.yaw, first.yaw, 1e-9, seg.name .. " yaw still")
					H.near(shot.pitch, first.pitch, 1e-9, seg.name .. " pitch still")
					H.near(shot.distance, first.distance, 1e-9, seg.name .. " distance still")
				end
				H.expect(moving.fovDeg == shot.fovDeg, "the same lens")
			end
		end
	end,
}
