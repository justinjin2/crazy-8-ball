--!strict
-- HudLayout: the boost pill and the Rush chip fit the bottom-left HUD at every size (Halloween
-- 2026, hw-gui lane). The HUD areas are the viewports less Roblox's top bar and the safe insets
-- (code-hud-boosts §1): 844x390 -> 750x311 (and 844x332 with no side insets), 1334x750 ->
-- 1334x692, 1024x768 -> 1024x700, 1920x1080 -> 1920x1022. Every case: the pill and the chip
-- inside the screen and at least ClearPx clear of the money HUD, Invite, Plus, the hotbar, the
-- WinTrack and the left column; the card inside the screen with every part and foot line. Overlaps among the pieces already
-- there today are printed once (a Request to the coordinator), never failed.

local H = require("./harness")

local SCREENS = {
	{ name = "phone 844x390", w = 750, h = 311 },
	{ name = "phone 844x332", w = 844, h = 332 },
	{ name = "phone 1334x750", w = 1334, h = 692 },
	{ name = "iPad 1024x768", w = 1024, h = 700 },
	{ name = "PC 1920x1080", w = 1920, h = 1022 },
}

local CHIPS: { string | false } = { false, "CANDY RUSH 8:12", "HALLOWEEN NIGHT 23:59:59" }

-- Every scene: VIP, the Candy line, chip, blocks, WinTrack open/folded, Plus tile, money words.
local function eachScene(fn: (any) -> ())
	for _, vip in { false, true } do
		for _, candy in { false, true } do
			for _, chip in CHIPS do
				for _, blocks in { 0, 3, 9 } do
					for _, open in { true, false } do
						for _, plusShown in { true, false } do
							for _, moneyText in { "$125,000", "$1,050,000" } do
								fn({
									vip = vip,
									candy = candy,
									chipText = if chip then chip else nil,
									blocks = blocks,
									winTrackOpen = open,
									plusShown = plusShown,
									moneyText = moneyText,
								})
							end
						end
					end
				end
			end
		end
	end
end

local function describe(screen: any, s: any): string
	return ("%s vip=%s candy=%s chip=%s blocks=%d track=%s plus=%s money=%s"):format(
		screen.name,
		tostring(s.vip),
		tostring(s.candy),
		tostring(s.chipText),
		s.blocks,
		if s.winTrackOpen then "open" else "folded",
		tostring(s.plusShown),
		s.moneyText
	)
end

local function inside(r: any, screen: any): boolean
	return r.x >= 0 and r.y >= 0 and r.x + r.w <= screen.w and r.y + r.h <= screen.h
end

return {
	["the pill and chip clear every other HUD piece at the four sizes, every case"] = function()
		local HudLayout = H.require("HudLayout")
		local Config = H.require("Config")
		local clear = Config.UI.BoostPill.ClearPx
		local existing: { [string]: boolean } = {}
		local cases = 0
		for _, screen in SCREENS do
			eachScene(function(s)
				cases += 1
				local others = HudLayout.others(screen, s)
				local b = HudLayout.boost(screen, s, others)
				local column = HudLayout.columnAfter(screen, s, others, b)
				local where = describe(screen, s)
				H.expect(inside(b.pill, screen), "pill inside: " .. where)
				H.expect(inside(b.card, screen), "card inside: " .. where)
				local mine = { { name = "pill", rect = b.pill } }
				if b.chip then
					H.expect(inside(b.chip, screen), "chip inside: " .. where)
					table.insert(mine, { name = "chip", rect = b.chip })
				else
					H.expect(s.chipText == nil, "a chip for its words: " .. where)
				end
				local theirs = {
					{ name = "money", rect = others.money },
					{ name = "invite", rect = others.invite },
				}
				for _, pair in
					{
						{ "plus", others.plus },
						{ "hotbar", others.hotbar },
						{ "winTrack", others.winTrack },
						{ "column", column },
					} :: { any }
				do
					if pair[2] then
						table.insert(theirs, { name = pair[1], rect = pair[2] })
					end
				end
				for _, m in mine do
					for _, o in theirs do
						local hits = HudLayout.overlaps({ m, o }, clear)
						H.expect(#hits == 0, ("%s touches %s: %s"):format(m.name, o.name, where))
					end
				end
				if b.chip then
					H.expect(
						#HudLayout.overlaps({ mine[1], mine[2] }, 0) == 0,
						"chip over the pill: " .. where
					)
				end
				-- The pieces there today (not ours to fix): printed once each.
				for _, pair in HudLayout.overlaps(theirs, 0) do
					local key = ("%s: %s x %s"):format(screen.name, pair[1], pair[2])
					existing[key] = true
				end
			end)
		end
		H.expect(cases == #SCREENS * 2 * 2 * 3 * 3 * 2 * 2 * 2, "every case ran")
		local lines = {}
		for key in existing do
			table.insert(lines, key)
		end
		table.sort(lines)
		for _, line in lines do
			print("        existing overlap (Request to the coordinator): " .. line)
		end
	end,

	["a phone's lines sit right of the left column when they fit, else over the money pill"] = function()
		local HudLayout = H.require("HudLayout")
		local Config = H.require("Config")
		local P = Config.UI.BoostPill
		-- 844x332 with the WinTrack folded: room right of the column, so the column never moves.
		local wide = { w = 844, h = 332 }
		local s = { moneyText = "$125,000", blocks = 3, winTrackOpen = false }
		local others = HudLayout.others(wide, s)
		local b = HudLayout.boost(wide, s, others)
		local column = others.column :: any
		H.expect(b.pill.x >= column.x + column.w + P.ColumnGapPx, "right of the column")
		H.expect(b.pill.y + b.pill.h == others.money.y - P.GapPx, "right over the money pill")
		local after = HudLayout.columnAfter(wide, s, others, b) :: any
		H.expect(after.y == column.y and after.h == column.h, "the column does not move for it")
		-- 750x311 with the WinTrack open: no room there, so over the money pill, the column above.
		local phone = { w = 750, h = 311 }
		local sp =
			{ moneyText = "$125,000", blocks = 3, candy = true, chipText = "CANDY RUSH 8:12" }
		local op = HudLayout.others(phone, sp)
		local bp = HudLayout.boost(phone, sp, op)
		H.expect(bp.pill.x == op.money.x + P.LeftPx, "over the money pill")
		local afterp = HudLayout.columnAfter(phone, sp, op, bp) :: any
		H.expect(afterp.y + afterp.h <= (bp.chip :: any).y, "the column keeps above the chip")
		-- A computer: over the money pill, one line, or two with Candy (Candy on top).
		local pc = { w = 1920, h = 1022 }
		local o2 = HudLayout.others(pc, s)
		local b2 = HudLayout.boost(pc, s, o2)
		H.expect(b2.pill.x == o2.money.x + P.LeftPx, "LeftPx from the money HUD's left edge")
		H.expect(b2.pill.h == P.LinePx and b.pill.h == P.ShortLinePx, "one line")
		local sc = { moneyText = "$125,000", blocks = 3, winTrackOpen = false, candy = true }
		local bc = HudLayout.boost(pc, sc, HudLayout.others(pc, sc))
		H.expect(bc.pill.h == 2 * P.LinePx and bc.lineH == P.LinePx, "two lines with Candy")
		H.expect(bc.pill.y + bc.pill.h == b2.pill.y + b2.pill.h, "the Candy line goes over it")
	end,

	["the Candy pill takes a row under the lines, right over the money pill"] = function()
		local HudLayout = H.require("HudLayout")
		local Config = H.require("Config")
		local P = Config.UI.BoostPill
		for _, screen in { { w = 1920, h = 1022 }, { w = 844, h = 390 }, { w = 750, h = 311 } } do
			local s = { moneyText = "$125,000", blocks = 3, candy = true, winTrackOpen = false }
			local withPill = table.clone(s)
			withPill.candyPill = true
			local b = HudLayout.boost(screen, s, HudLayout.others(screen, s))
			local bp = HudLayout.boost(screen, withPill, HudLayout.others(screen, withPill))
			local row = HudLayout.candyPillRow(screen)
			local tag = screen.w .. "x" .. screen.h
			H.expect(
				b.candyPillH == 0 and bp.candyPillH == row,
				tag .. ": the row only with the pill"
			)
			H.expect(bp.pill.h == b.pill.h + row, tag .. ": the box grows by the row")
			H.expect(
				bp.pill.y + bp.pill.h <= HudLayout.others(screen, withPill).money.y - P.GapPx,
				tag .. ": over the money pill"
			)
		end
	end,

	["the chip sits right over the pill, compact only when it must be"] = function()
		local HudLayout = H.require("HudLayout")
		local Config = H.require("Config")
		local C = Config.UI.BoostPill.Chip
		H.expect(
			HudLayout.compact("CANDY RUSH 8:12") == "CANDY 8:12",
			HudLayout.compact("CANDY RUSH 8:12")
		)
		H.expect(HudLayout.compact("HALLOWEEN NIGHT 23:59:59") == "HALLOWEEN 23:59:59")
		H.expect(HudLayout.compact("RUSH") == "RUSH", "one word stays")
		local pc = { w = 1920, h = 1022 }
		local s = { moneyText = "$125,000", blocks = 9, chipText = "CANDY RUSH 8:12" }
		local o = HudLayout.others(pc, s)
		local b = HudLayout.boost(pc, s, o)
		local chip = b.chip :: any
		H.expect(
			chip.x == b.pill.x and chip.y + chip.h == b.pill.y - C.GapPx,
			"right over the pill"
		)
		H.expect(
			not b.chipCompact and b.chipText == "CANDY RUSH 8:12",
			"a PC has room for the words"
		)
		H.expect(b.chipTextPx == C.TextPx and chip.h == C.HeightPx)
		-- Narrow room: the compact words or smaller text, never under MinTextPx.
		local phone = { w = 750, h = 311 }
		local sp = { moneyText = "$1,050,000", blocks = 3, chipText = "HALLOWEEN NIGHT 23:59:59" }
		local op = HudLayout.others(phone, sp)
		local bp = HudLayout.boost(phone, sp, op)
		H.expect(bp.chipTextPx >= C.MinTextPx, "never under MinTextPx")
		H.expect(bp.chipCompact, "a phone with the WinTrack open: compact")
	end,

	["the card fits over the pill at every size: foot lines go first, then it scales"] = function()
		local HudLayout = H.require("HudLayout")
		local Config = H.require("Config")
		local K = Config.UI.BoostPill.Card
		for _, screen in SCREENS do
			for rows = 1, 6 do
				local s = { moneyText = "$125,000", cardRows = rows, cardFeet = 4 }
				local b = HudLayout.boost(screen, s, HudLayout.others(screen, s))
				local where = ("%s, %d rows"):format(screen.name, rows)
				H.expect(inside(b.card, screen), "card inside: " .. where)
				H.expect(
					b.card.y + b.card.h <= b.pill.y - K.AbovePx + 0.001,
					"over the pill: " .. where
				)
				H.expect(b.cardScale >= K.MinScale and b.cardScale <= 1, "scale: " .. where)
				H.expect(b.cardScale == 1 or b.cardFeet == 0, "feet go before it scales: " .. where)
			end
		end
		-- A computer has room for every line; a phone on its side drops lines first.
		local pc = { w = 1920, h = 1022 }
		local s = { moneyText = "$125,000", cardRows = 6, cardFeet = 4 }
		local b = HudLayout.boost(pc, s, HudLayout.others(pc, s))
		H.expect(b.cardFeet == 4 and b.cardScale == 1, "a PC keeps everything")
		local feet, scale = HudLayout.cardFit(HudLayout.cardHeight(3, 2), 3, 4)
		H.expect(feet == 2 and scale == 1, "the last two foot lines go")
		feet, scale = HudLayout.cardFit(HudLayout.cardHeight(6, 0) / 2, 6, 4)
		H.expect(feet == 0 and scale == K.MinScale, "never under MinScale")
	end,

	["no chip words, no chip; the overlap check is symmetric and honours the gap"] = function()
		local HudLayout = H.require("HudLayout")
		local pc = { w = 1920, h = 1022 }
		local s = { moneyText = "$5" }
		local b = HudLayout.boost(pc, s, HudLayout.others(pc, s))
		H.expect(b.chip == nil and b.chipText == nil, "no chip")
		local a = { name = "a", rect = { x = 0, y = 0, w = 10, h = 10 } }
		local c = { name = "c", rect = { x = 11, y = 0, w = 10, h = 10 } }
		H.expect(#HudLayout.overlaps({ a, c }, 0) == 0, "1 px apart")
		H.expect(#HudLayout.overlaps({ a, c }, 2) == 1, "inside the 2 px gap")
		H.expect(#HudLayout.overlaps({ c, a }, 2) == 1, "either order")
	end,
}
