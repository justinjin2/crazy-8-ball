--!strict
-- HudLayout: where the boost pill and the Rush chip go in the bottom-left HUD, and where the
-- pieces already there sit (Halloween 2026, PLAN §2 "Boost display"; hw-gui lane). Pure: no
-- Instances, so the Lune test (tests/hud_layout_test.luau) runs the same numbers as the game.
--
-- Rects are { x, y, w, h } in the PoolHud screen's pixels (the area under Roblox's top bar and
-- inside the safe insets). `others` mirrors from Config how MoneyHud, HubCorners (Invite,
-- Plus), LuckyHotbar, WinTrack and MenuColumn place themselves; in the game BoostPill passes
-- their LIVE rects instead (measured AbsolutePosition/AbsoluteSize), so this mirror only has to
-- be close enough for the test to catch a layout that cannot fit.
--
-- The rules (`boost`): the "pill" (since 2026-10-28 its lines of outlined text with no
-- background: Money Boost, and Candy Boost over it while the event is live) sits right over the
-- money pill, LeftPx right of the money HUD's left edge, the left column kept above it
-- (`columnAfter`; on a short screen too since 2026-10-29: ShortBesideColumn false); with
-- ShortBesideColumn a short screen puts it at least ColumnGapPx right of the left column when it
-- fits there, so the column never moves for it; if it still touches a piece (an
-- iPad's full hotbar) it rises over it. Its width is fixed by WidestText, plus on a touch screen
-- the "i" column at its left (`infoColumn`, 2026-10-30). The chip sits right over
-- the pill at the same left x; if it would touch another piece it becomes the compact chip
-- ("CANDY 8:12"), then its words shrink (never under MinTextPx), and as a last resort it rises
-- over the piece it touches. The card sits over the pill; when it is too tall for the room
-- there its foot lines go (the last first), then it scales down (`cardFit`). Text widths are
-- the CharWidthShare estimate, in the test and the game alike.
local Config = require(script.Parent.Config)

local P = Config.UI.BoostPill
local CHIP = P.Chip
local MONEY = Config.UI.Progress.MoneyHud
local CORNERS = Config.UI.Corners
local COLUMN = Config.UI.Menu.Column
local RANK = Config.UI.Progress.RankHud
local HOTBAR = Config.LuckyBlocks.UI
local TRACK = Config.UI.WinTrack
local SHORT_HEIGHT = Config.Multiplayer.Style.ShortHeight

export type Rect = { x: number, y: number, w: number, h: number }
export type Screen = { w: number, h: number }

-- What is on screen (the test's cases; the game passes what it sees).
export type Scene = {
	vip: boolean?,
	candy: boolean?, -- the Candy Boost line shows (the event is live): two lines, not one
	candyPill: boolean?, -- the Candy pill shows under the lines (Config.UI.BoostPill.CandyPill)
	info: boolean?, -- a touch screen: the "i" column left of the lines (Config.UI.BoostPill.Info)
	moneyText: string?, -- the money pill's words ("$125,000")
	moneyPlus: boolean?, -- the money pill's gold "+" (hidden in a match); nil = shown
	plusShown: boolean?, -- the Roblox Plus tile right of Invite
	blocks: number?, -- lucky blocks held (the hotbar's slots)
	hotbarShown: boolean?, -- nil = shown (its bag button shows with no blocks)
	winTrackOpen: boolean?, -- false: folded to its pill
	winTrackShown: boolean?, -- nil = shown
	columnTiles: number?, -- the left column's tiles (default 4)
	chipText: string?, -- core's chip words; nil = no chip
	cardRows: number?, -- the card's part rows (default 6, every part)
	cardFeet: number?, -- its foot lines before any go (default 1: the Candy card's Rush line)
}

export type Others = {
	money: Rect,
	invite: Rect,
	plus: Rect?,
	hotbar: Rect?,
	winTrack: Rect?,
	column: Rect?,
}

export type Boost = {
	pill: Rect, -- the lines' box (one line, or two with Candy)
	pillTextPx: number,
	lineH: number, -- one line's height
	candyPillH: number, -- the Candy pill's row at the box's bottom (its gap included), or 0
	infoW: number, -- the "i" column at the box's left (its gap included), or 0; the lines go right
	infoPx: number, -- the "i" disc's size, or 0
	chip: Rect?,
	chipText: string?, -- the words the chip shows (the compact form when chipCompact)
	chipTextPx: number,
	chipCompact: boolean,
	chipLifted: boolean, -- it had to rise over something
	card: Rect,
	cardFeet: number, -- the foot lines kept
	cardScale: number,
}

local HudLayout = {}

local function round(x: number): number
	return math.floor(x + 0.5)
end

--- Whether the screen is short (a phone on its side): the smaller sizes.
function HudLayout.short(screen: Screen): boolean
	return screen.h < SHORT_HEIGHT
end

--- The layout's estimate of a text's width at `px` (CharWidthShare per character).
function HudLayout.textWidth(text: string, px: number): number
	return math.ceil((utf8.len(text) or #text) * px * P.CharWidthShare)
end

--- The lines' box on this screen for `lines` lines (1 or 2): (width, height, text px, line
--- height).
function HudLayout.pillSize(screen: Screen, lines: number): (number, number, number, number)
	local short = HudLayout.short(screen)
	local lineH = if short then P.ShortLinePx else P.LinePx
	local textPx = if short then P.ShortTextPx else P.TextPx
	return HudLayout.textWidth(P.WidestText, textPx), lineH * lines, textPx, lineH
end

--- The "i" column left of the lines on a touch screen (`info`; Info.Enabled): (its width with
--- the gap, the disc's size); 0, 0 without it.
function HudLayout.infoColumn(screen: Screen, info: boolean?): (number, number)
	if not info or P.Info.Enabled ~= true then
		return 0, 0
	end
	local lineH = if HudLayout.short(screen) then P.ShortLinePx else P.LinePx
	local px = round(lineH * P.Info.BadgeShare)
	return px + P.Info.GapPx, px
end

--- The Candy pill's row under the boost lines: its height and the gap over it.
function HudLayout.candyPillRow(screen: Screen): number
	local CP = P.CandyPill
	return (if HudLayout.short(screen) then CP.ShortHeightPx else CP.HeightPx) + CP.GapPx
end

--- The chip's size for `text` at `textPx` with or without its icon: (width, height).
function HudLayout.chipSize(
	screen: Screen,
	text: string,
	textPx: number,
	icon: boolean
): (number, number)
	local h = if HudLayout.short(screen) then CHIP.ShortHeightPx else CHIP.HeightPx
	local iconW = if icon then math.floor(h * CHIP.IconShare) + CHIP.InnerGapPx else 0
	return CHIP.PadPx + iconW + HudLayout.textWidth(text, textPx) + CHIP.PadPx, h
end

--- The compact chip's words: "CANDY RUSH 8:12" -> "CANDY 8:12" (the first word and the clock).
function HudLayout.compact(text: string): string
	local first = text:match("^(%S+)")
	local rest = text:match(CHIP.CompactPattern)
	if first and rest then
		return first .. " " .. rest
	end
	return text
end

-- The money HUD's rect (MoneyHud.layout), the gold "+" included while it shows.
local function moneyRect(screen: Screen, s: Scene): Rect
	local short = HudLayout.short(screen)
	local margin = if short then MONEY.ShortMarginPx else MONEY.MarginPx
	local icon = if short then MONEY.ShortIconSizePx else MONEY.IconSizePx
	local textPx = if short then MONEY.ShortTextPx else MONEY.TextPx
	local over = math.floor(icon * MONEY.IconOverPill)
	local plusOn = s.moneyPlus ~= false
	local plusSize = if short then MONEY.ShortPlusPx else MONEY.PlusPx
	local plusOver = if plusOn then math.floor(plusSize * MONEY.PlusOverPill) else 0
	local words = HudLayout.textWidth(s.moneyText or "$0", textPx)
	local pillWidth = over + 4 + words + MONEY.TextPadPx + plusOver
	local w = (icon - over) + pillWidth + (if plusOn then plusSize - plusOver else 0)
	return { x = margin, y = screen.h - margin - icon, w = w, h = icon }
end

-- The left column (MenuColumn.layout) kept above `keepTop` (the money HUD's top, or the
-- highest piece over it that the column keeps above).
function HudLayout.column(screen: Screen, s: Scene, keepTop: number): Rect
	local short = HudLayout.short(screen)
	local phone = math.min(screen.w, screen.h) < SHORT_HEIGHT
	local tile = if phone then COLUMN.ShortTilePx else COLUMN.TilePx
	local gap = if phone then COLUMN.ShortGapPx else COLUMN.GapPx
	local margin = if phone then COLUMN.ShortMarginPx else COLUMN.MarginPx
	local textPx = if phone then COLUMN.ShortLabelTextPx else COLUMN.LabelTextPx
	local count = s.columnTiles or 4
	local height = count * tile + (count - 1) * gap
	-- The widest word: "FREE REWARD" (Strings.Menus.Column), as MenuColumn measures it.
	local widest = HudLayout.textWidth("FREE REWARD", textPx)
	local maxShare = if phone then COLUMN.ShortLabelMaxShare else COLUMN.LabelMaxShare
	local labelW = math.clamp(widest + 8, tile, round(tile * maxShare))
	local over = math.max(0, round((labelW - tile) / 2))
	local width = tile + 2 * over
	local badge = RANK.BadgePx * (if short then 1 else RANK.ComputerScale)
	local topBar = 58 -- Roblox's top bar, above the PoolHud screen
	local minTop = math.max(0, badge + RANK.TopMinPx - topBar) + COLUMN.BelowRankPx
	local maxBottom = keepTop - COLUMN.AboveMoneyPx
	local scale = math.clamp((maxBottom - minTop) / height, COLUMN.MinScale, 1)
	local shown = height * scale
	local top = if phone then minTop else round((screen.h - shown) / 2)
	top = math.clamp(top, minTop, math.max(minTop, maxBottom - shown))
	return { x = margin, y = top, w = width * scale, h = shown }
end

--- The pieces already in the bottom-left and centre-bottom HUD, mirrored from Config.
function HudLayout.others(screen: Screen, s: Scene): Others
	local short = HudLayout.short(screen)
	local money = moneyRect(screen, s)
	-- Invite and Plus right of the money HUD, centred on it (HubCorners).
	local small = if short then CORNERS.ShortSmallPx else CORNERS.SmallPx
	local cx = money.x + money.w + CORNERS.SmallGapPx
	local cy = money.y + money.h / 2
	local invite = { x = round(cx), y = round(cy - small / 2), w = small, h = small }
	local plus = if s.plusShown == false
		then nil
		else {
			x = round(cx + small + CORNERS.SmallGapPx),
			y = round(cy - small / 2),
			w = small,
			h = small,
		}
	-- The lucky block hotbar, centred at the bottom (LuckyHotbar.layout): its slots and bag.
	local narrow = screen.w < HOTBAR.PhoneWidthPx
	local hotbar: Rect? = nil
	local lift = 0
	if s.hotbarShown ~= false then
		local size = if narrow then HOTBAR.PhoneSlotPx else HOTBAR.SlotPx
		local cap = if narrow
			then math.min(Config.LuckyBlocks.HotbarSlots, HOTBAR.PhoneHotbarSlots)
			else Config.LuckyBlocks.HotbarSlots
		local n = math.clamp(s.blocks or 0, 0, cap)
		local width = n * size + n * HOTBAR.SlotGapPx + size
		hotbar = {
			x = round((screen.w - width) / 2),
			y = screen.h - HOTBAR.BottomPx - size,
			w = width,
			h = size,
		}
		lift = if narrow then HOTBAR.PhoneLiftPx else HOTBAR.LiftPx
	end
	-- The day's win track over the hotbar (WinTrack.layout/place), PhoneScale on a phone. Folded
	-- it is a pill at the bar's foot (an estimate of its width).
	local winTrack: Rect? = nil
	if s.winTrackShown ~= false then
		local scale = if narrow then TRACK.PhoneScale else 1
		local bottom = screen.h - (TRACK.BottomPx + lift)
		local w, h
		if s.winTrackOpen == false then
			w, h = 240 * scale, TRACK.FoldedHeightPx * scale
		else
			local tiles = 10
			local width = 2 * TRACK.PadPx + tiles * TRACK.TilePx + (tiles - 1) * TRACK.TileGapPx
			local barH = TRACK.TopPadPx + TRACK.TilePx + TRACK.UnderPadPx
			local over = TRACK.PillHeightPx / 2 + TRACK.ResetsTextPx + TRACK.ResetsGapPx
			w, h = width * scale, (barH + over) * scale
		end
		winTrack =
			{ x = round((screen.w - w) / 2), y = round(bottom - h), w = round(w), h = round(h) }
	end
	return {
		money = money,
		invite = invite,
		plus = plus,
		hotbar = hotbar,
		winTrack = winTrack,
		column = HudLayout.column(screen, s, money.y),
	}
end

local function touches(a: Rect, b: Rect, clear: number): boolean
	return a.x < b.x + b.w + clear
		and b.x < a.x + a.w + clear
		and a.y < b.y + b.h + clear
		and b.y < a.y + a.h + clear
end

local function inside(a: Rect, screen: Screen): boolean
	return a.x >= 0 and a.y >= 0 and a.x + a.w <= screen.w and a.y + a.h <= screen.h
end

-- The obstacles a piece must clear, in a fixed order (the column only when `column`: a piece
-- the column keeps above need not clear it).
local function obstaclesOf(others: Others, pill: Rect?, column: boolean): { Rect }
	local list: { Rect } = { others.money, others.invite }
	if pill then
		table.insert(list, 1, pill)
	end
	for _, r in { others.plus, others.hotbar, others.winTrack } :: { Rect? } do
		if r then
			table.insert(list, r)
		end
	end
	if column and others.column then
		table.insert(list, others.column)
	end
	return list
end

local function firstHit(r: Rect, obstacles: { Rect }, screen: Screen): Rect?
	for _, o in obstacles do
		if touches(r, o, P.ClearPx) then
			return o
		end
	end
	if not inside(r, screen) then
		return { x = screen.w, y = 0, w = 0, h = screen.h } -- the screen's right edge
	end
	return nil
end

--- Where the pill, the chip and the card go, given the other pieces' rects.
function HudLayout.boost(screen: Screen, s: Scene, others: Others): Boost
	local short = HudLayout.short(screen)
	local pw, ph, pillTextPx, lineH = HudLayout.pillSize(screen, if s.candy then 2 else 1)
	local candyPillH = if s.candyPill then HudLayout.candyPillRow(screen) else 0
	ph += candyPillH
	local infoW, infoPx = HudLayout.infoColumn(screen, s.info)
	pw += infoW
	local y = others.money.y - P.GapPx - ph
	local pill = { x = round(others.money.x + P.LeftPx), y = y, w = pw, h = ph }
	local column = others.column
	if short and column and P.ShortBesideColumn == true then
		local right = column.x + column.w + P.ColumnGapPx
		local beside = { x = round(math.max(pill.x, right)), y = y, w = pw, h = ph }
		if not firstHit(beside, obstaclesOf(others, nil, true), screen) then
			pill = beside
		end
	end
	-- Right of the column, the chip clears it too; over the money pill the column keeps above both.
	local clearColumn = column ~= nil and pill.x >= column.x + column.w
	-- Last resort: rise over a piece it touches (an iPad's full hotbar), a few pieces at most.
	local blockers = obstaclesOf(others, nil, clearColumn)
	local blocked = firstHit(pill, blockers, screen)
	local lifts = 0
	while blocked and lifts < #blockers do
		lifts += 1
		pill = { x = pill.x, y = math.min(pill.y, blocked.y - P.GapPx - ph), w = pw, h = ph }
		blocked = firstHit(pill, blockers, screen)
	end

	local chip: Rect? = nil
	local chipText: string? = nil
	local chipTextPx = if short then CHIP.ShortTextPx else CHIP.TextPx
	local compact, lifted = false, false
	local text = s.chipText
	if text and text ~= "" then
		local obstacles = obstaclesOf(others, pill, clearColumn)
		local function at(words: string, px: number, y: number?): Rect
			local w, h = HudLayout.chipSize(screen, words, px, true)
			return { x = pill.x, y = y or (pill.y - CHIP.GapPx - h), w = w, h = h }
		end
		local full = at(text, chipTextPx)
		local hit = firstHit(full, obstacles, screen)
		chip, chipText = full, text
		if hit then
			compact = true
			local short2 = HudLayout.compact(text)
			chipText = short2
			chip = at(short2, chipTextPx)
			hit = firstHit(chip :: Rect, obstacles, screen)
			if hit then
				-- Shrink the words to the room left of what it touches.
				local room = hit.x - P.ClearPx - pill.x
				local w0 = HudLayout.chipSize(screen, short2, 0, true)
				local px = math.floor((room - w0) / math.max(1, HudLayout.textWidth(short2, 1)))
				if px >= CHIP.MinTextPx and px < chipTextPx then
					chipTextPx = px
					chip = at(short2, px)
					hit = firstHit(chip :: Rect, obstacles, screen)
				end
			end
			-- Last resort: rise over what it touches, as often as needed (a few pieces at most).
			local tries = 0
			while hit and tries < #obstacles do
				tries += 1
				lifted = true
				local c = chip :: Rect
				chip = at(short2, chipTextPx, math.min(c.y, hit.y - CHIP.GapPx - c.h))
				hit = firstHit(chip :: Rect, obstacles, screen)
			end
		end
	end

	-- The card over the pill: what fits the room up to the screen's top, kept inside its width.
	local rows = s.cardRows or 6
	local feet, scale = HudLayout.cardFit(pill.y - P.Card.AbovePx, rows, s.cardFeet or 1)
	local cardW = (if short then P.Card.ShortWidthPx else P.Card.WidthPx) * scale
	local cardH = HudLayout.cardHeight(rows, feet) * scale
	local cx = math.clamp(pill.x, 0, math.max(0, screen.w - cardW))
	local cy = pill.y - P.Card.AbovePx - cardH
	return {
		pill = pill,
		pillTextPx = pillTextPx,
		lineH = lineH,
		candyPillH = candyPillH,
		infoW = infoW,
		infoPx = infoPx,
		chip = chip,
		chipText = chipText,
		chipTextPx = chipTextPx,
		chipCompact = compact,
		chipLifted = lifted,
		card = { x = cx, y = cy, w = cardW, h = cardH },
		cardFeet = feet,
		cardScale = scale,
	}
end

--- The YOUR BOOSTS card's height for `rows` part rows and `feet` foot lines (BoostPill.fillCard
--- lays it out the same way): the title, the rows, the rule, the total, the foot lines.
function HudLayout.cardHeight(rows: number, feet: number): number
	local K = P.Card
	return K.PadPx
		+ K.TitlePx
		+ 4
		+ K.GapPx
		+ rows * K.RowPx
		+ K.GapPx
		+ K.RulePx
		+ K.GapPx
		+ K.TotalPx
		+ 4
		+ feet * (K.NotePx + 4)
		+ K.PadPx
end

--- How the card fits `room` px over the pill: the foot lines it keeps (the last go first; since
--- 2026-10-30 only the Candy card has one, the Rush's words) and its scale (1, or smaller when
--- even its rows alone are too tall; never under Card.MinScale).
function HudLayout.cardFit(room: number, rows: number, feet: number): (number, number)
	local keep = feet
	while keep > 0 and HudLayout.cardHeight(rows, keep) > room do
		keep -= 1
	end
	local height = HudLayout.cardHeight(rows, keep)
	local scale = if height > room then math.max(P.Card.MinScale, room / height) else 1
	return keep, scale
end

--- The left column once the pill and chip are up: MenuColumn keeps above every piece over the
--- money pill that is not wholly right of the column (a short screen's pill and chip are).
function HudLayout.columnAfter(screen: Screen, s: Scene, others: Others, b: Boost): Rect?
	local column = others.column
	if not column then
		return nil
	end
	local keepTop = others.money.y
	for _, r in { b.pill, b.chip } :: { Rect? } do
		if r and r.x < column.x + column.w then
			keepTop = math.min(keepTop, r.y)
		end
	end
	return HudLayout.column(screen, s, keepTop)
end

--- Every pair of named rects that comes within `clear` px of each other (0 = touching or
--- overlapping), as { a, b } names in the order given.
function HudLayout.overlaps(rects: { { name: string, rect: Rect } }, clear: number?): { { string } }
	local found = {}
	local gap = clear or 0
	for i = 1, #rects do
		for j = i + 1, #rects do
			local a, b = rects[i], rects[j]
			local ra, rb = a.rect, b.rect
			if
				ra.x < rb.x + rb.w + gap
				and rb.x < ra.x + ra.w + gap
				and ra.y < rb.y + rb.h + gap
				and rb.y < ra.y + ra.h + gap
			then
				table.insert(found, { a.name, b.name })
			end
		end
	end
	return found
end

return HudLayout
