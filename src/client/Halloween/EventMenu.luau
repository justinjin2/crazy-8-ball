--!strict
-- EventMenu: the Halloween event's menu (hw-core; the mock M4_quest_board). The lively frame
-- (MenuFrame: the panel unrolls, the header, the red X, the 8-ball flair) round:
--   * the player's Candy and "ENDS IN 5d 23h";
--   * the Candy track to the Witch's Broom: 11 nodes evenly spaced on a bar filled by share
--     between them, cue nodes as cards (a Preview button when the GUI lane's CuePreview is on),
--     gifts as boxes, the Broom bigger and gold; a reached node gets a gold frame and a check;
--     on a phone it scrolls sideways;
--   * the quest board: DAY 1..6 tabs (future days locked, "Unlocks in 13:22:10"), four rows
--     each with its icon, line, bar, "7/10" and its Candy chip or a bouncing CLAIM;
--   * the Spider panel: the playtime cue, "1h 12m / 3h 01m" on a bar, "Only active play
--     counts";
--   * Get Candy: the two packs (while Config.Halloween.Packs is on);
--   * the Rush strip pinned at the foot: "CANDY RUSH 2x CANDY starts in 12:05" / "ends in 7:42",
--     on Oct 31 "HALLOWEEN NIGHT 2x CANDY ALL DAY 9:12:44".
-- A computer shows the quests and the Spider side by side; a phone one scrolling column. Built
-- once, redrawn from Halloween/State's view; one 1 s clock while open, never per frame.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared.Progression.Format)
local Clock = require(Shared.Halloween.Clock)
local Event = require(Shared.Halloween.Event)
local HudParts = require(script.Parent.Parent.HudParts)
local PadMode = require(script.Parent.Parent.PadMode)
local ItemState = require(script.Parent.Parent.ItemState)
local MenuFrame = require(script.Parent.Parent.MenuFrame)
local Menus = require(script.Parent.Parent.Menus)
local ShopParts = require(script.Parent.Parent.ShopParts)
local UIAnim = require(script.Parent.Parent.UIAnim)
local UISound = require(script.Parent.Parent.UISound)
local State = require(script.Parent.State)

local NAME = "Halloween"
local H = Config.Halloween
local M = Config.UI.Halloween.Menu
local ART = Config.UI.Halloween.Art
local QICONS: { [string]: string } = Config.UI.Halloween.QuestIcons :: any
local K = Config.UI.Kit
local W = Strings.Halloween
local CUE_NAMES: { [string]: string } = Strings.Items.Cues :: any
local QUEST_TEXT: { [string]: { One: string, Many: string } } = W.Quests :: any
local CUE_SHORT: { [string]: string } = W.CueShort :: any

local EventMenu = {}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function round(n: number): number
	return math.floor(n + 0.5)
end

-- An image label (plain picture) under `parent`.
local function picture(parent: Instance, name: string, image: string): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.ScaleType = Enum.ScaleType.Fit
	label.Image = image
	label.Parent = parent
	return label
end

-- A Kit icon or a raw image id ("rbxassetid://...").
local function imageOf(key: string): string
	if string.sub(key, 1, 13) == "rbxassetid://" then
		return key
	end
	return (K.Icons :: any)[key] or ""
end

-- A rounded panel with the ink edge, filled with `tint`.
local function panel(parent: Instance, name: string, tint: Color3, cornerPx: number?): Frame
	local f = HudParts.frame(parent, name)
	f.BackgroundTransparency = 0
	f.BackgroundColor3 = tint
	HudParts.corner(f, cornerPx or 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = HudParts.tone("Ink")
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = f
	return f
end

-- A quest's line ("Win 3 matches", "Play 30 min").
local function questText(kind: string, need: number): string
	local t = QUEST_TEXT[kind]
	if t == nil then
		return kind
	end
	local n = if kind == "Active" then math.floor(need / 60) else need
	return if n == 1 then t.One else t.Many:format(n)
end

-- A duration for the Spider panel: "1h 12m", "45m".
local function hm(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h, m = s // 3600, (s % 3600) // 60
	return if h > 0 then ("%dh %02dm"):format(h, m) else ("%dm"):format(m)
end

-- The CuePreview module (the GUI lane's), when it is there and switched on.
local function cuePreview(): any?
	local found = script.Parent.Parent:FindFirstChild("CuePreview")
	if found == nil or not found:IsA("ModuleScript") then
		return nil
	end
	local ok, module = pcall(require, found :: any)
	if not ok or type(module) ~= "table" or type(module.open) ~= "function" then
		return nil
	end
	local enabled = type(module.enabled) == "function"
		and pcall(module.enabled)
		and module.enabled()
	return if enabled then module else nil
end

-- The prize words under a gift node: "2 SPINS", "$5,000".
local function giftWords(step: any): string
	if step.Spins ~= nil then
		return if step.Spins == 1 then W.Spins.One else W.Spins.Many:format(step.Spins)
	end
	return Format.money(step.Money or 0)
end

--- Build the menu (closed) and register it with Menus.
function EventMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local frame = MenuFrame.new(screen, {
		name = NAME,
		title = W.Title,
		money = false,
		widthShare = M.WidthShare,
		phoneWidthShare = M.PhoneWidthShare,
	})
	-- The header's jack-o'-lantern.
	local headerArt = if ART.Header ~= "" then ART.Header else H.CandyIcon
	if headerArt ~= "" and frame.icon then
		frame.icon.Image = headerArt
		frame.icon.Visible = true
	end
	local page = frame:page()
	local geo: MenuFrame.Geo? = nil
	local short = false
	local selectedBoard = 0 -- 0: pick the oldest unfinished board on the next draw
	local claiming: { [string]: boolean } = {}
	local idles: { UIAnim.Handle } = {}
	local _ = deps

	-- The scrolling body, and the Rush strip pinned under it.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Body"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ZIndex = 2
	scroll.Parent = page

	-- Candy and the end.
	local candyPill = HudParts.pill(scroll, "HwCandy", rgb(M.TrackColor))
	candyPill.ZIndex = 3
	local candyIcon = picture(candyPill, "Icon", H.CandyIcon)
	candyIcon.ZIndex = 4
	local candyText = HudParts.text(candyPill, "Count", M.TextPx, "0")
	candyText.AutoLocalize = false
	candyText.TextXAlignment = Enum.TextXAlignment.Left
	candyText.ZIndex = 4
	-- The Pumpkin King's drop (Halloween.KingDrop): his cue and its chance, OWNED once owned.
	local kingPill = HudParts.pill(scroll, "HwKingDrop", rgb(M.HeadTint))
	kingPill.ZIndex = 3
	kingPill.Visible = H.KingDrop.Enabled == true
	local kingArt = picture(kingPill, "Art", (ART :: any)[H.KingDrop.Cue] or "")
	kingArt.ZIndex = 4
	local kingText = HudParts.text(kingPill, "Text", M.TextPx, "")
	kingText.AutoLocalize = false
	kingText.TextXAlignment = Enum.TextXAlignment.Left
	kingText.ZIndex = 4
	local endsPill = HudParts.pill(scroll, "HwEnds", HudParts.tone("Purple"))
	endsPill.ZIndex = 3
	local endsText = HudParts.text(endsPill, "Time", M.TextPx, "")
	endsText.AutoLocalize = false
	endsText.Size = UDim2.fromScale(1, 1)
	endsText.ZIndex = 4

	-- The track.
	local trackBox = panel(scroll, "HwTrack", rgb(M.BarBack), 14)
	trackBox.ZIndex = 2
	local trackTitle = HudParts.text(trackBox, "Title", M.HeadPx, W.TrackTitle)
	trackTitle.TextColor3 = rgb(M.HeadTint)
	trackTitle.ZIndex = 3
	local trackScroll = Instance.new("ScrollingFrame")
	trackScroll.Name = "Nodes"
	trackScroll.BackgroundTransparency = 1
	trackScroll.BorderSizePixel = 0
	trackScroll.ScrollBarThickness = 4
	trackScroll.ScrollingDirection = Enum.ScrollingDirection.X
	trackScroll.ZIndex = 3
	trackScroll.Parent = trackBox
	local barBack = HudParts.frame(trackScroll, "Bar")
	barBack.BackgroundTransparency = 0
	barBack.BackgroundColor3 = Color3.fromRGB(30, 18, 50)
	HudParts.corner(barBack, 6)
	barBack.ZIndex = 3
	local barFill = HudParts.frame(barBack, "Fill")
	barFill.BackgroundTransparency = 0
	barFill.BackgroundColor3 = rgb(M.TrackColor)
	HudParts.corner(barFill, 6)
	barFill.ZIndex = 4
	type Node = {
		index: number,
		step: any,
		card: Frame,
		art: ImageLabel,
		at: TextLabel,
		label: TextLabel,
		check: ImageLabel,
		edge: UIStroke,
		preview: TextButton?,
	}
	local nodes: { Node } = {}
	local steps = H.Track.Steps
	for index, step in steps do
		local isCue = step.Cue ~= nil
		local card = panel(
			trackScroll,
			"HwNode" .. index,
			if isCue then rgb(M.CardTint) else rgb(M.GiftTint),
			12
		)
		card.ZIndex = 5
		local edge = card:FindFirstChildOfClass("UIStroke") :: UIStroke
		local image = if isCue
			then (ART :: any)[step.Cue] or ""
			elseif step.Money ~= nil then (if ART.CashStack ~= ""
				then ART.CashStack
				else imageOf("CashStack"))
			else (if ART.Gift ~= "" then ART.Gift else imageOf("Gift"))
		local art = picture(card, "Art", image)
		art.ZIndex = 6
		local at = HudParts.text(card, "At", M.TextPx, Format.commas(step.At))
		at.ZIndex = 7
		local label = HudParts.text(card, "Label", M.TextPx - 4, "")
		label.ZIndex = 7
		label.TextWrapped = true
		local cueId: string = step.Cue or ""
		label.Text = if isCue
			then (CUE_SHORT[cueId] or CUE_NAMES[cueId] or cueId)
			else giftWords(step)
		local check = picture(card, "Check", imageOf("Check"))
		check.ZIndex = 8
		check.Visible = false
		local node: Node = {
			index = index,
			step = step,
			card = card,
			art = art,
			at = at,
			label = label,
			check = check,
			edge = edge,
			preview = nil,
		}
		if isCue then
			local preview = HudParts.candy(card, W.Preview, function()
				local module = cuePreview()
				if module then
					UISound.play("Click")
					pcall(module.open, step.Cue, { from = "Track", note = Format.commas(step.At) })
				end
			end, "Blue", nil)
			preview.Name = "Preview"
			preview.ZIndex = 8
			preview.Visible = false
			node.preview = preview
		end
		if index == #steps then
			UIAnim.glowPulse(art, 0, 0.25, 1.8)
		end
		table.insert(nodes, node)
	end

	-- The quest board.
	local questBox = panel(scroll, "HwQuests", HudParts.tone("White"), 14)
	questBox.ZIndex = 2
	local questTitle = HudParts.text(questBox, "Title", M.HeadPx, W.QuestsTitle)
	questTitle.TextColor3 = rgb(M.HeadTint)
	questTitle.ZIndex = 3
	local tabs: { TextButton } = {}
	local tabLocks: { TextLabel } = {}
	for n = 1, H.Boards do
		local tab = HudParts.candy(questBox, W.Day:format(n), function()
			UISound.play("Click")
			selectedBoard = n
			EventMenu.redraw()
		end, "White", nil)
		tab.Name = "Day" .. n
		tab.ZIndex = 4
		table.insert(tabs, tab)
		local lock = HudParts.note(questBox, "Unlock" .. n, M.TextPx - 6, "")
		lock.AutoLocalize = false
		lock.ZIndex = 4
		table.insert(tabLocks, lock)
	end
	type Row = {
		frame: Frame,
		icon: ImageLabel,
		text: TextLabel,
		barBack: Frame,
		bar: Frame,
		count: TextLabel,
		chip: Frame,
		chipIcon: ImageLabel,
		chipText: TextLabel,
		claim: TextButton,
		key: string?,
	}
	local rows: { Row } = {}
	for slot = 1, 4 do
		local f = panel(questBox, "Row" .. slot, Color3.fromRGB(245, 238, 255), 10)
		f.ZIndex = 4
		local icon = picture(f, "Icon", "")
		icon.ZIndex = 5
		local text = HudParts.note(f, "Text", M.TextPx, "")
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.ZIndex = 5
		local back = HudParts.frame(f, "BarBack")
		back.BackgroundTransparency = 0
		back.BackgroundColor3 = Color3.fromRGB(220, 210, 235)
		HudParts.corner(back, 5)
		back.ZIndex = 5
		local bar = HudParts.frame(back, "Bar")
		bar.BackgroundTransparency = 0
		bar.BackgroundColor3 = rgb(M.TrackColor)
		HudParts.corner(bar, 5)
		bar.ZIndex = 6
		local count = HudParts.note(f, "Count", M.TextPx - 2, "")
		count.AutoLocalize = false
		count.ZIndex = 5
		local chip = HudParts.pill(f, "Chip", HudParts.tone("Gold"))
		chip.ZIndex = 5
		local chipIcon = picture(chip, "Icon", H.CandyIcon)
		chipIcon.ZIndex = 6
		chipIcon.Size = UDim2.fromScale(0.34, 0.9)
		chipIcon.Position = UDim2.fromScale(0.04, 0.05)
		local chipText = HudParts.text(chip, "Text", M.TextPx, "")
		chipText.AutoLocalize = false
		chipText.Size = UDim2.fromScale(0.62, 1)
		chipText.Position = UDim2.fromScale(0.36, 0)
		chipText.ZIndex = 6
		local row: Row = {
			frame = f,
			icon = icon,
			text = text,
			barBack = back,
			bar = bar,
			count = count,
			chip = chip,
			chipIcon = chipIcon,
			chipText = chipText,
			claim = nil :: any,
			key = nil,
		}
		row.claim = HudParts.candy(f, W.Claim, function()
			local key = row.key
			if key == nil or claiming[key] then
				return
			end
			claiming[key] = true
			UISound.play("Claim")
			UIAnim.glowBurst(row.chip, HudParts.tone("Gold"), 0.5)
			-- The claimed Candy flies out of this button (CandyToast).
			EventMenu.lastClaim = {
				at = os.clock(),
				from = row.claim.AbsolutePosition + row.claim.AbsoluteSize / 2,
			}
			State.send({ claim = key })
			task.delay(3, function()
				claiming[key] = nil
			end)
			EventMenu.redraw()
			-- A controller's selection moves on from the CLAIM that just hid: to the next waiting
			-- CLAIM, else the X, so nothing hidden stays selected.
			if GuiService.SelectedObject == row.claim and not row.claim.Visible then
				local nextClaim: GuiObject? = nil
				for _, other in rows do
					if other.claim.Visible and other.claim.Parent ~= nil then
						nextClaim = other.claim
						break
					end
				end
				if nextClaim then
					GuiService.SelectedObject = nextClaim
				else
					frame:focus()
				end
			end
		end, "Green", nil)
		row.claim.Name = "Claim"
		row.claim.ZIndex = 6
		row.claim.Visible = false
		table.insert(rows, row)
	end
	local questsSoon = HudParts.note(questBox, "Soon", M.TextPx, W.QuestsSoon)
	questsSoon.ZIndex = 5
	questsSoon.Visible = false

	-- The Spider panel.
	local spiderBox = panel(scroll, "HwSpider", rgb(M.SpiderTint), 14)
	spiderBox.ZIndex = 2
	local spiderTitle = HudParts.text(spiderBox, "Title", M.HeadPx, W.Spider)
	spiderTitle.TextColor3 = rgb(M.HeadTint)
	spiderTitle.ZIndex = 3
	local spiderArt = picture(spiderBox, "Art", ART.SpiderCue)
	spiderArt.ZIndex = 3
	UIAnim.glowPulse(spiderArt, 0, 0.2, 2.2)
	local spiderBarBack = HudParts.frame(spiderBox, "BarBack")
	spiderBarBack.BackgroundTransparency = 0
	spiderBarBack.BackgroundColor3 = Color3.fromRGB(30, 18, 50)
	HudParts.corner(spiderBarBack, 6)
	spiderBarBack.ZIndex = 3
	local spiderBar = HudParts.frame(spiderBarBack, "Bar")
	spiderBar.BackgroundTransparency = 0
	spiderBar.BackgroundColor3 = Color3.fromRGB(190, 190, 210)
	HudParts.corner(spiderBar, 6)
	spiderBar.ZIndex = 4
	local spiderText = HudParts.text(spiderBox, "Time", M.TextPx, "")
	spiderText.AutoLocalize = false
	spiderText.ZIndex = 3
	local spiderNote = HudParts.text(spiderBox, "Note", M.TextPx - 4, W.SpiderNote)
	spiderNote.TextColor3 = HudParts.tone("Soft")
	spiderNote.TextYAlignment = Enum.TextYAlignment.Top
	spiderNote.ZIndex = 3

	-- Get Candy: the two packs.
	local packBox = panel(scroll, "HwPacks", HudParts.tone("White"), 14)
	packBox.ZIndex = 2
	local packTitle = HudParts.text(packBox, "Title", M.HeadPx, W.GetCandy)
	packTitle.TextColor3 = rgb(M.HeadTint)
	packTitle.ZIndex = 3
	local packButtons: { TextButton } = {}
	for i, key in H.Packs.Keys do
		local button = HudParts.candy(packBox, "", function()
			UISound.play("Click")
			State.send({ pack = key })
			task.spawn(ItemState.request, "StoreRequest", "Buy", key)
		end, "Green", nil)
		button.Name = "Pack" .. i
		button.ZIndex = 4
		table.insert(packButtons, button)
	end

	-- The Rush strip.
	local strip = panel(page, "HwRush", rgb(M.StripTint), 10)
	strip.ZIndex = 3
	local stripText = HudParts.text(strip, "Text", M.TextPx, "")
	stripText.AutoLocalize = false
	stripText.RichText = true
	stripText.Size = UDim2.fromScale(1, 1)
	stripText.ZIndex = 4

	local stage = frame.stage
	if stage then
		stage:add("HwCandy", candyPill)
		stage:add("HwKingDrop", kingPill)
		stage:add("HwEnds", endsPill)
		stage:add("HwTrack", trackBox)
		for _, node in nodes do
			stage:add("HwNode" .. node.index, node.card)
		end
		stage:add("HwQuests", questBox)
		stage:add("HwSpider", spiderBox)
		stage:add("HwPacks", packBox)
		stage:add("HwRush", strip)
	end

	-- The oldest board with a quest still to finish or claim (else the newest open one).
	local function defaultBoard(view: any): number
		local open = view.open or 0
		for _, board in view.boards or {} do
			if board.n <= open then
				for _, q in board.quests or {} do
					if not q.claimed then
						return board.n
					end
				end
			end
		end
		return math.max(1, open)
	end

	local packTextPx = M.TextPx -- the packs' text size at the last layout
	local packFit = "" -- the packs' width, text size and labels when last fitted

	local function sizeText(label: TextLabel, px: number)
		HudParts.setTextSize(label, px)
	end

	-- Lays everything out for the panel's size (MenuFrame's onLayout).
	local function layout()
		local g = geo
		if g == nil then
			return
		end
		short = g.short or g.phone == true
		local width, height = g.content.X, g.content.Y
		local pad, gap = M.PadPx, M.GapPx
		local textPx = if short then M.ShortTextPx else M.TextPx
		local headPx = if short then M.ShortHeadPx else M.HeadPx
		local pillPx = if short then M.ShortPillPx else M.PillPx
		local stripPx = if short then M.ShortStripPx else M.StripPx
		scroll.Size = UDim2.fromOffset(width, height - stripPx - gap)
		strip.Position = UDim2.fromOffset(0, height - stripPx)
		strip.Size = UDim2.fromOffset(width, stripPx)
		sizeText(stripText, textPx)
		local inner = width - 12 -- room for the scroll bar
		local y = 0
		-- Candy and the end.
		candyPill.Size = UDim2.fromOffset(round(pillPx * 4), pillPx)
		candyPill.Position = UDim2.fromOffset(0, y)
		candyIcon.Size = UDim2.fromOffset(pillPx - 6, pillPx - 6)
		candyIcon.Position = UDim2.fromOffset(6, 3)
		candyText.Size = UDim2.fromOffset(round(pillPx * 4) - pillPx - 6, pillPx)
		candyText.Position = UDim2.fromOffset(pillPx + 4, 0)
		sizeText(candyText, textPx + 2)
		endsPill.Size = UDim2.fromOffset(round(pillPx * 5), pillPx)
		endsPill.Position = UDim2.fromOffset(inner - round(pillPx * 5), y)
		sizeText(endsText, textPx)
		-- The King's pill in the gap between the two, as wide as its words need.
		local kingX = round(pillPx * 4) + gap
		local kingW = math.min(round(pillPx * 8), inner - round(pillPx * 5) - gap - kingX)
		kingPill.Size = UDim2.fromOffset(math.max(0, kingW), pillPx)
		kingPill.Position = UDim2.fromOffset(kingX, y)
		kingArt.Size = UDim2.fromOffset(pillPx - 4, pillPx - 4)
		kingArt.Position = UDim2.fromOffset(4, 2)
		kingText.Size = UDim2.fromOffset(math.max(0, kingW - pillPx - 8), pillPx)
		kingText.Position = UDim2.fromOffset(pillPx + 2, 0)
		sizeText(kingText, textPx)
		y += pillPx + gap
		-- The track.
		local nodePx = if short then M.ShortNodePx else M.NodePx
		local titleH = headPx + 8
		trackTitle.Size = UDim2.fromOffset(inner, titleH)
		trackTitle.Position = UDim2.fromOffset(0, 2)
		sizeText(trackTitle, headPx)
		local count = #nodes
		-- A computer fits all eleven (the cards shrink on a narrow window); a phone scrolls.
		if not short then
			local room = inner - 2 * pad - (count - 1) * M.NodeGapPx
			nodePx = math.min(nodePx, math.floor(room / (count - 1 + M.GrandScale)))
		end
		local grand = round(nodePx * M.GrandScale)
		local slotMin = if short then math.max(M.NodeMinPx, nodePx + M.NodeGapPx) else 0
		local slotW = math.max(slotMin, (inner - 2 * pad - grand) / math.max(1, count - 1))
		local trackW = math.max(inner - 2 * pad, slotW * (count - 1) + grand)
		local barPx = if short then M.ShortBarPx else M.BarPx
		local cardTop = textPx + 6
		local previewH = if cuePreview() ~= nil then textPx + 8 else 0
		local nodesH = cardTop + grand + 8 + barPx + previewH + 4
		trackScroll.Position = UDim2.fromOffset(pad, titleH)
		trackScroll.Size = UDim2.fromOffset(inner - 2 * pad, nodesH + 6)
		trackScroll.CanvasSize = UDim2.fromOffset(trackW, 0)
		-- The bar runs under the cards, from the first's middle to the Broom's.
		local barY = cardTop + grand + 6 + previewH
		barBack.Position = UDim2.fromOffset(round(nodePx / 2), barY)
		barBack.Size = UDim2.fromOffset(round(trackW - nodePx / 2 - grand / 2), barPx)
		for i, node in nodes do
			local isGrand = i == count
			local px = if isGrand then grand else nodePx
			local cx = if isGrand then trackW - grand / 2 else nodePx / 2 + (i - 1) * slotW
			node.card.Size = UDim2.fromOffset(px, px)
			node.card.Position =
				UDim2.fromOffset(round(cx - px / 2), cardTop + round((grand - px) / 2))
			node.art.Size = UDim2.fromScale(0.86, 0.7)
			node.art.Position = UDim2.fromScale(0.07, 0.04)
			node.at.Size = UDim2.fromOffset(px, textPx + 2)
			node.at.Position = UDim2.fromOffset(0, -textPx - 4)
			sizeText(node.at, textPx)
			node.label.Size = UDim2.fromScale(1, 0.28)
			node.label.Position = UDim2.fromScale(0, 0.72)
			HudParts.setTextSize(node.label, math.max(9, textPx - 6), M.NodeLabelMinPx)
			node.check.Size = UDim2.fromOffset(round(px * 0.32), round(px * 0.32))
			node.check.Position = UDim2.fromOffset(round(px * 0.7), -round(px * 0.1))
			if node.preview then
				local pw = round(px * 0.9)
				node.preview.Size = UDim2.fromOffset(pw, textPx + 6)
				node.preview.Position = UDim2.fromOffset(round((px - pw) / 2), px + 2)
				HudParts.setButtonTextSize(node.preview, math.max(10, textPx - 4))
			end
		end
		trackBox.Position = UDim2.fromOffset(0, y)
		trackBox.Size = UDim2.fromOffset(inner, titleH + nodesH + 10)
		y += titleH + nodesH + 10 + gap
		-- The quests (left on a computer, full width on a phone) and the Spider and packs.
		local rowPx = if short then M.ShortRowPx else M.RowPx
		local tabPx = if short then M.ShortTabPx else M.TabPx
		local questW = if short then inner else round((inner - gap) * M.QuestShare)
		local qPad = pad
		questTitle.Size = UDim2.fromOffset(questW, titleH)
		questTitle.Position = UDim2.fromOffset(0, 2)
		sizeText(questTitle, headPx)
		local tabW = (questW - 2 * qPad - (H.Boards - 1) * 4) / H.Boards
		for n, tab in tabs do
			tab.Size = UDim2.fromOffset(round(tabW), tabPx)
			tab.Position = UDim2.fromOffset(round(qPad + (n - 1) * (tabW + 4)), titleH + 2)
			HudParts.setButtonTextSize(tab, math.max(10, textPx - 2))
			local lock = tabLocks[n]
			lock.Size = UDim2.fromOffset(round(tabW + 4), textPx)
			lock.Position =
				UDim2.fromOffset(round(qPad + (n - 1) * (tabW + 4) - 2), titleH + tabPx + 3)
			sizeText(lock, math.max(9, textPx - 6))
		end
		local rowY = titleH + tabPx + textPx + 8
		for slot, row in rows do
			local rw = questW - 2 * qPad
			row.frame.Size = UDim2.fromOffset(rw, rowPx)
			row.frame.Position = UDim2.fromOffset(qPad, rowY + (slot - 1) * (rowPx + 6))
			row.icon.Size = UDim2.fromOffset(rowPx - 12, rowPx - 12)
			row.icon.Position = UDim2.fromOffset(6, 6)
			local chipW = round(rowPx * 1.9)
			local left = rowPx
			local right = rw - chipW - 10
			row.text.Size = UDim2.fromOffset(right - left - 60, round(rowPx * 0.5))
			row.text.Position = UDim2.fromOffset(left, 2)
			sizeText(row.text, textPx)
			row.barBack.Size = UDim2.fromOffset(right - left - 70, round(rowPx * 0.22))
			row.barBack.Position = UDim2.fromOffset(left, round(rowPx * 0.6))
			row.count.Size = UDim2.fromOffset(60, round(rowPx * 0.5))
			row.count.Position = UDim2.fromOffset(right - 64, round(rowPx * 0.42))
			sizeText(row.count, math.max(10, textPx - 2))
			row.chip.Size = UDim2.fromOffset(chipW, round(rowPx * 0.62))
			row.chip.Position = UDim2.fromOffset(rw - chipW - 8, round(rowPx * 0.19))
			sizeText(row.chipText, textPx)
			row.claim.Size = UDim2.fromOffset(chipW, round(rowPx * 0.72))
			row.claim.Position = UDim2.fromOffset(rw - chipW - 8, round(rowPx * 0.14))
			HudParts.setButtonTextSize(row.claim, textPx)
		end
		questsSoon.Size = UDim2.fromOffset(questW, rowPx)
		questsSoon.Position = UDim2.fromOffset(0, rowY)
		sizeText(questsSoon, textPx)
		local questH = rowY + 4 * (rowPx + 6) + qPad
		questBox.Position = UDim2.fromOffset(0, y)
		questBox.Size = UDim2.fromOffset(questW, questH)
		-- The Spider and Get Candy.
		local sideX = if short then 0 else questW + gap
		local sideW = if short then inner else inner - questW - gap
		local sideY = if short then y + questH + gap else y
		local spiderH = if short then round(rowPx * 2.6) else round(questH * 0.58)
		spiderBox.Position = UDim2.fromOffset(sideX, sideY)
		spiderBox.Size = UDim2.fromOffset(sideW, spiderH)
		spiderTitle.Size = UDim2.fromOffset(sideW, titleH)
		spiderTitle.Position = UDim2.fromOffset(0, 2)
		sizeText(spiderTitle, headPx)
		local artPx = spiderH - titleH - 10
		spiderArt.Size = UDim2.fromOffset(artPx, artPx)
		spiderArt.Position = UDim2.fromOffset(8, titleH + 2)
		local textX = artPx + 16
		local textW = sideW - textX - 10
		spiderText.Size = UDim2.fromOffset(textW, textPx + 6)
		spiderText.Position = UDim2.fromOffset(textX, titleH + round(artPx * 0.15))
		sizeText(spiderText, textPx + 2)
		spiderBarBack.Size = UDim2.fromOffset(textW, 12)
		spiderBarBack.Position = UDim2.fromOffset(textX, titleH + round(artPx * 0.15) + textPx + 12)
		-- Two lines' room: a narrow column (an iPad) wraps the note instead of cutting it.
		spiderNote.Size = UDim2.fromOffset(textW, 2 * textPx + 4)
		spiderNote.Position = UDim2.fromOffset(textX, titleH + round(artPx * 0.15) + textPx + 30)
		sizeText(spiderNote, math.max(10, textPx - 4))
		local packY = sideY + spiderH + gap
		local packH = if short then round(rowPx * 2.2) else questH - spiderH - gap
		packBox.Position = UDim2.fromOffset(sideX, packY)
		packBox.Size = UDim2.fromOffset(sideW, packH)
		packTitle.Size = UDim2.fromOffset(sideW, titleH)
		packTitle.Position = UDim2.fromOffset(0, 2)
		sizeText(packTitle, headPx)
		local bw = (sideW - 3 * qPad) / 2
		for i, button in packButtons do
			button.Size = UDim2.fromOffset(round(bw), math.max(40, packH - titleH - 16))
			button.Position = UDim2.fromOffset(round(qPad + (i - 1) * (bw + qPad)), titleH + 4)
			HudParts.setButtonTextSize(button, textPx)
		end
		packTextPx = textPx
		local bottom = if short then packY + packH else y + questH
		scroll.CanvasSize = UDim2.fromOffset(0, bottom + gap)
	end

	-- Draws the view (cheap: texts, sizes, visibility).
	local function draw()
		local view = State.view()
		local now = Clock.now()
		local candy = State.candy()
		candyText.Text = Format.commas(candy)
		endsText.Text = W.EndsIn:format(Event.short(Event.endsIn(now)))
		if type(view) ~= "table" then
			return
		end
		local kingOwned = type(view.owned) == "table" and view.owned[H.KingDrop.Cue] == true
		kingText.Text = if kingOwned
			then W.KingDropOwned
			else W.KingDrop:format(tostring(math.floor(H.KingDrop.Chance * 100 + 0.5)))
		-- The track: the bar fills each segment by share; reached nodes framed gold.
		local given: { [number]: boolean } = {}
		for _, i in view.given or {} do
			given[i] = true
		end
		local count = #nodes
		local fillShare = 0
		for i = 1, count - 1 do
			local a, b = steps[i].At, steps[i + 1].At
			if candy >= b then
				fillShare = i / (count - 1)
			elseif candy >= a then
				fillShare = (i - 1 + (candy - a) / (b - a)) / (count - 1)
				break
			end
		end
		if candy >= steps[count].At then
			fillShare = 1
		end
		barFill.Size = UDim2.fromScale(math.clamp(fillShare, 0, 1), 1)
		local preview = cuePreview()
		for _, node in nodes do
			local reached = given[node.index] == true or candy >= node.step.At
			node.check.Visible = reached
			node.edge.Color = if reached then rgb(M.GivenTint) else HudParts.tone("Ink")
			node.edge.Thickness = if reached then 4 else 2
			if node.preview then
				node.preview.Visible = preview ~= nil
			end
		end
		-- The quests.
		local on = type(view.on) == "table" and view.on.quests == true
		if selectedBoard == 0 or selectedBoard > math.max(1, view.open or 0) then
			selectedBoard = defaultBoard(view)
		end
		for n, tab in tabs do
			local board = view.boards and view.boards[n]
			local open = n <= (view.open or 0)
			local done = false
			if open and board then
				done = #board.quests > 0
				for _, q in board.quests do
					if not q.claimed then
						done = false
					end
				end
			end
			HudParts.setTone(
				tab,
				if n == selectedBoard then "Blue" elseif open then "White" else "Grey"
			)
			HudParts.setEnabled(tab, open, not open)
			HudParts.setText(tab, if done then W.Day:format(n) .. " ✓" else W.Day:format(n))
			local lock = tabLocks[n]
			lock.Visible = not open and board ~= nil
			if lock.Visible then
				local wait = board.opensAt - now
				lock.Text = if wait >= 86400 then Event.short(wait) else Event.clock(wait)
			end
		end
		local board = view.boards and view.boards[selectedBoard]
		questsSoon.Visible = not on
		for slot, row in rows do
			local q = if on and board then board.quests[slot] else nil
			row.frame.Visible = q ~= nil
			row.key = if q then q.key else nil
			if q then
				row.icon.Image = if q.icon == "Candy"
					then H.CandyIcon
					else imageOf(QICONS[q.icon] or "Star")
				row.text.Text = questText(q.kind, q.need)
				local have = math.min(q.have, q.need)
				local share = if q.need > 0 then have / q.need else 0
				row.bar.Size = UDim2.fromScale(share, 1)
				row.count.Text = if q.kind == "Active"
					then ("%d/%d"):format(have // 60, q.need // 60)
					else ("%d/%d"):format(have, q.need)
				local claimable = have >= q.need and not q.claimed and not claiming[q.key]
				row.claim.Visible = claimable
				row.chip.Visible = not claimable
				row.chipText.Text = if q.claimed then W.Claimed else W.Reward:format(q.reward)
				-- CLAIMED takes the whole chip (beside the icon it was cut to "CLAIME" on a phone).
				row.chipIcon.Visible = not q.claimed
				row.chipText.Size = UDim2.fromScale(if q.claimed then 0.92 else 0.62, 1)
				row.chipText.Position = UDim2.fromScale(if q.claimed then 0.04 else 0.36, 0)
				row.chip.BackgroundColor3 = if q.claimed
					then HudParts.tone("Green")
					else HudParts.tone("Gold")
			end
		end
		-- The Spider.
		local spiderOn = type(view.on) == "table" and view.on.spider == true
		spiderBox.Visible = true
		local active = view.active or 0
		local need = H.Spider.Seconds
		spiderText.Text = if view.spider
			then W.SpiderDone
			else W.SpiderOf:format(hm(active), hm(need))
		spiderBar.Size = UDim2.fromScale(math.clamp(active / need, 0, 1), 1)
		spiderNote.Visible = spiderOn
		-- The packs.
		local packsOn = type(view.on) == "table" and view.on.packs == true
		packBox.Visible = packsOn
		if packsOn then
			local shop = ItemState.shop()
			local products = if type(shop) == "table" and type(shop.products) == "table"
				then shop.products
				else {}
			local labels: { { words: string, price: string? } } = {}
			local fitKey = ("%d|%d|"):format(packButtons[1].Size.X.Offset, packTextPx)
			for i, key in H.Packs.Keys do
				local row = products[key]
				local robux = if type(row) == "table" and type(row.robux) == "number"
					then row.robux
					else nil
				local spec = (Config.Products.List :: any)[key]
				local candyCount = if type(spec) == "table" then spec.Candy or 0 else 0
				local words = W.PackCandy:format(Format.commas(candyCount))
				local price = if robux then ShopParts.robux(robux) else nil
				labels[i] = { words = words, price = price }
				fitKey ..= words .. (price or "")
			end
			if packFit ~= fitKey then
				packFit = fitKey
				-- Too wide for a narrow column (an iPad) even at the smallest text: both packs put
				-- the price on a second line, so the two buttons still match.
				local floorPx = math.min(packTextPx, K.Text.Min)
				local twoLines = false
				for i, label in labels do
					local button = packButtons[i]
					HudParts.setText(
						button,
						if label.price then label.words .. "  " .. label.price else label.words
					)
					if
						label.price
						and HudParts.candyWidth(button, button.Size.Y.Offset, floorPx)
							> button.Size.X.Offset
					then
						twoLines = true
					end
				end
				if twoLines then
					for i, label in labels do
						if label.price then
							HudParts.setText(packButtons[i], label.words .. "\n" .. label.price)
						end
					end
				end
			end
		end
		-- The Rush strip.
		local chip = Event.rushChip(now)
		if Event.doubleDay(now) and chip then
			stripText.Text = ("%s  %s"):format(
				W.Night,
				W.NightNow:format(Event.clock(chip.endsAt - now))
			)
		elseif chip then
			stripText.Text = ("%s  %s"):format(
				W.Rush,
				W.RushNow:format(Event.clock(chip.endsAt - now))
			)
		else
			-- No next Rush: switched off, or the event's last hour.
			local nextAt = Event.nextRushAt(now)
			stripText.Text = ("%s  %s"):format(
				W.Rush,
				if nextAt then W.RushSoon:format(Event.clock(nextAt - now)) else W.RushDone
			)
		end
	end
	EventMenu.redraw = draw
	-- The Candy pill's middle while the menu is open (where a claim's Candy lands), and its bump.
	EventMenu.candyTarget = function(): Vector2?
		if not frame:isOpen() or not candyPill.Visible then
			return nil
		end
		return candyPill.AbsolutePosition + candyPill.AbsoluteSize / 2
	end
	EventMenu.bumpCandy = function()
		UIAnim.bounce(candyPill)
	end

	frame.onLayout = function(g: MenuFrame.Geo)
		geo = g
		layout()
		draw()
	end
	-- As tall as the content, at most MaxHeightShare of the screen.
	frame.fitHeight = function(_width: number): number
		return math.floor(screen.AbsoluteSize.Y * M.MaxHeightShare)
	end
	-- The 1 s redraw loop: each open starts one and bumps the generation, so a loop left from a
	-- close and quick reopen stops on its next wake (never two loops).
	local tickGen = 0
	frame.onOpen = function()
		State.send({ seen = true })
		layout()
		draw()
		tickGen += 1
		local gen = tickGen
		task.spawn(function()
			local warned = false -- a failing redraw warns once; the loop goes on
			while gen == tickGen do
				local ok, err = pcall(function(): any
					draw()
					return nil
				end)
				if not ok and not warned then
					warned = true
					warn("[8ball] Halloween menu: " .. tostring(err))
				end
				task.wait(1)
			end
		end)
		-- Waiting CLAIMs bounce.
		for _, row in rows do
			table.insert(
				idles,
				UIAnim.loop(row.claim, function(clock: number)
					if row.claim.Visible and clock % M.ClaimBounceSeconds < 0.05 then
						UIAnim.bounce(row.claim)
					end
				end)
			)
		end
		-- A controller lands on the first waiting CLAIM once the panel has unrolled (the content
		-- is hidden until then, so nothing in it can be selected before).
		task.delay(Config.UI.Halloween.Open.OpenSeconds, function()
			if not frame:isOpen() or not PadMode.active() then
				return
			end
			for _, row in rows do
				if row.claim.Visible and row.claim.Parent ~= nil then
					GuiService.SelectedObject = row.claim
					return
				end
			end
		end)
	end
	frame.onClose = function()
		tickGen += 1
		for _, handle in idles do
			handle.stop()
		end
		table.clear(idles)
	end
	State.Changed:Connect(function()
		if frame:isOpen() then
			draw()
		end
	end)

	local handle: Menus.Handle = {
		open = function()
			frame:open()
		end,
		close = function()
			frame:close()
		end,
		isOpen = function(): boolean
			return frame:isOpen()
		end,
		root = frame.root,
	}
	Menus.register(NAME, handle)
	return handle
end

-- Redraws the open menu (set by new).
function EventMenu.redraw() end

-- Set by new: the Candy pill's middle while the menu is open (nil otherwise), and its bounce.
function EventMenu.candyTarget(): Vector2?
	return nil
end
function EventMenu.bumpCandy() end

-- The last CLAIM press: when (os.clock) and where (its middle, absolute pixels).
EventMenu.lastClaim = nil :: { at: number, from: Vector2 }?

return EventMenu
