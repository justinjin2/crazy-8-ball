--!strict
-- LobbyBoards: the two lobby boards, Most wins and Top countries (designer, 2026-10-25; the
-- concept approved on a private page). The server builds the stands (workspace.Leaderboards,
-- src/server/Leaderboards.luau); each screen draws a lively card on each stand's board: the
-- scrolling 8-ball header with its icon and title, the white sheet with a scrolling list, and
-- a pinned You row under it (your place, or your country's).
-- - Cheap on a phone: a list of hundreds of rows (the countries) is drawn with Card.Pool row frames, reused as it
--   scrolls (LeaderboardMath.window); avatar pictures load only for the rows on screen.
-- - The lists are asked of the server (LeaderboardRead) only while the stands are within
--   FetchStuds, at most every FetchSeconds; the wins' later pages only when scrolled to.
-- - Scrolling: the mouse wheel and a finger drag (the list's own); a gamepad's right stick
--   while standing near and facing a board (the camera stick again when walking away).
-- - Measured: the Leaderboard event (Viewed once a session, Scrolled deeper; the server logs it).
-- No per-frame work: a CheckSeconds pass, and repaints when scrolled or when lists arrive.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Net = require(Shared:WaitForChild("Net"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local PlayerListView = require(Shared:WaitForChild("Progression"):WaitForChild("PlayerListView"))
local LeaderboardMath = require(Shared:WaitForChild("LeaderboardMath"))
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local PadMode = require(script.Parent.PadMode)
local GuiQA = require(script.Parent.GuiQA)

local LB = Config.Leaderboards.Lobby
local C = LB.Card
local K = Config.UI.Kit
local W = Strings.LobbyBoards
local NAMES: { [string]: string } = Strings.Countries
local PAD_ACTION = "LobbyBoardScroll"

type Row = {
	frame: Frame,
	place: Frame,
	placeText: TextLabel,
	picture: ImageLabel,
	flag: TextLabel,
	name: TextLabel,
	value: TextLabel,
	cup: ImageLabel,
	shown: number, -- the list row it shows (0: none)
}

type Board = {
	key: string, -- "Wins" | "Countries"
	face: BasePart,
	gui: SurfaceGui,
	list: ScrollingFrame,
	empty: TextLabel,
	rows: { Row },
	you: TextLabel,
	youValue: TextLabel,
	youCup: ImageLabel,
	youFlag: TextLabel,
	padHint: Frame,
	data: { any }, -- the rows known, by place (the wins' later pages fill in as fetched)
	total: number, -- the list's length
	popped: boolean, -- the first rows have popped in
	lod: UIScale, -- the board drawn smaller when far (LodSteps)
	pps: number, -- its PixelsPerStud now
	want: number, -- the PixelsPerStud the last pass asked for (twice in a row to switch)
}

local LobbyBoards = {}

local player = Players.LocalPlayer
local boards: { [string]: Board } = {}
local readRemote: RemoteFunction? = nil
local lastFetch = -math.huge
local pageAsked: { [number]: number } = {} -- a wins page -> when it was last asked for (os.clock)
local top: any = nil -- the last "top" answer
local deepestSent: { [string]: number } = {}
local seenSent: { [string]: boolean } = {}
local padBoard: Board? = nil
local padY = 0
local padStep: RBXScriptConnection? = nil

local function rowPx(): number
	return C.RowPx
end

-- A fixed-size number (not scaled to its box), so its width is known and the trophy can sit
-- just left of it (designer, 2026-10-25).
local function fixNumber(value: TextLabel, px: number)
	value.TextScaled = false
	value.TextSize = px
end

-- Show `text` in `value` (right-aligned `rightPx` in from its parent's right end) with the trophy
-- `cup` just left of the number.
local function setValue(value: TextLabel, cup: ImageLabel, text: string, rightPx: number)
	local px = value.TextSize
	value.Text = text
	cup.Visible = text ~= ""
	local width =
		TextService:GetTextSize(text, px, HudParts.measureFont(value), Vector2.new(1000, 1000)).X
	cup.Position = UDim2.new(1, -(rightPx + width + C.TrophyGapPx), 0.5, 0)
end

local function invoke(...: any): any
	local remote = readRemote
	if not remote then
		return nil
	end
	local args = table.pack(...)
	local ok, answer = pcall(function(): any
		return remote:InvokeServer(table.unpack(args, 1, args.n))
	end)
	if ok and type(answer) == "table" and answer.ok == true then
		return answer
	end
	return nil
end

---------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------

local function stroke(parent: Instance, px: number)
	local s = Instance.new("UIStroke")
	s.Color = HudParts.tone("Ink")
	s.Thickness = px
	s.Parent = parent
end

local function newRow(board: Board, index: number): Row
	local frame = HudParts.frame(board.list, "Row" .. index)
	frame.Size = UDim2.new(1, -12, 0, rowPx() - C.RowGapPx)
	frame.BackgroundColor3 = HudParts.color(C.StripeColor)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	HudParts.corner(frame, 12)
	local place = HudParts.frame(frame, "Place")
	place.Size = UDim2.fromOffset(C.PlacePx, C.PlacePx)
	place.AnchorPoint = Vector2.new(0, 0.5)
	place.Position = UDim2.new(0, 4, 0.5, 0)
	HudParts.corner(place, C.PlacePx / 2)
	stroke(place, 2.5)
	local placeText = HudParts.text(place, "N", C.RowTextPx - 2, "")
	placeText.Size = UDim2.fromScale(1, 1)
	placeText.AutoLocalize = false
	local x = 4 + C.PlacePx + C.PictureGapPx
	local picture = Instance.new("ImageLabel")
	picture.Name = "Picture"
	picture.BackgroundColor3 = Color3.fromRGB(190, 214, 245)
	picture.Size = UDim2.fromOffset(C.PlacePx, C.PlacePx)
	picture.AnchorPoint = Vector2.new(0, 0.5)
	picture.Position = UDim2.new(0, x, 0.5, 0)
	picture.Parent = frame
	HudParts.corner(picture, C.PlacePx / 2)
	stroke(picture, 2)
	local flag = Instance.new("TextLabel")
	flag.Name = "Flag"
	flag.BackgroundTransparency = 1
	flag.AutoLocalize = false
	flag.TextScaled = true
	flag.Text = ""
	flag.Size = UDim2.fromOffset(C.PlacePx + 8, C.PlacePx)
	flag.AnchorPoint = Vector2.new(0, 0.5)
	flag.Position = UDim2.new(0, x, 0.5, 0)
	flag.Parent = frame
	x += C.PlacePx + 8 + C.PictureGapPx
	local name = HudParts.text(frame, "Name", C.RowTextPx, "")
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Position = UDim2.fromOffset(x, 0)
	name.Size = UDim2.new(1, -x - C.ValueWidthPx - C.TrophyPx - 8, 1, 0)
	local trophy = HudParts.icon(frame, "Trophy", "Cup")
	trophy.Size = UDim2.fromOffset(C.TrophyPx, C.TrophyPx)
	trophy.AnchorPoint = Vector2.new(1, 0.5)
	trophy.Position = UDim2.new(1, -C.ValueWidthPx - 4, 0.5, 0)
	trophy.Visible = false
	local value = HudParts.text(frame, "Value", C.RowTextPx, "", HudParts.color(K.Numbers.Money))
	value.AutoLocalize = false
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -6, 0, 0)
	value.Size = UDim2.new(0, C.ValueWidthPx - 8, 1, 0)
	fixNumber(value, C.RowTextPx)
	return {
		frame = frame,
		place = place,
		placeText = placeText,
		picture = picture,
		flag = flag,
		name = name,
		value = value,
		cup = trophy,
		shown = 0,
	}
end

-- Put list row `index`'s entry on `row` (or leave it blank while its page is on its way).
local function paintRow(board: Board, row: Row, index: number)
	local entry = board.data[index]
	row.shown = index
	row.frame.Position = UDim2.fromOffset(4, (index - 1) * rowPx())
	row.frame.BackgroundTransparency = if index % 2 == 1 then C.StripeTransparency else 1
	local medal = C.Medals[index]
	row.place.BackgroundTransparency = if medal then 0 else 1
	if medal then
		row.place.BackgroundColor3 = HudParts.color(medal)
	end
	local ring = row.place:FindFirstChildOfClass("UIStroke")
	if ring then
		ring.Enabled = medal ~= nil
	end
	row.placeText.Text = tostring(index)
	if board.key == "Wins" then
		row.flag.Visible = false
		row.picture.Visible = true
		row.name.AutoLocalize = false -- a player's name is never translated
		if entry then
			row.picture.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=%d&h=%d"):format(
				entry.u,
				C.HeadshotPx,
				C.HeadshotPx
			)
			row.name.Text = entry.n
			setValue(row.value, row.cup, Format.commas(entry.v), 6)
		else
			row.picture.Image = ""
			row.name.Text = W.Loading
			setValue(row.value, row.cup, "", 6)
		end
	else
		row.picture.Visible = false
		row.flag.Visible = true
		row.name.AutoLocalize = true -- country names go through Roblox's translation
		if entry then
			row.flag.Text = PlayerListView.flag(entry.c)
			row.name.Text = NAMES[entry.c] or entry.c
			setValue(row.value, row.cup, Format.commas(entry.v), 6)
		else
			row.flag.Text = ""
			row.name.Text = ""
			setValue(row.value, row.cup, "", 6)
		end
	end
end

local function wantPage(page: number)
	local now = os.clock()
	if page < 2 or now - (pageAsked[page] or -math.huge) < LB.DeepReadSeconds then
		return
	end
	pageAsked[page] = now
	task.spawn(function()
		local answer = invoke("wins", page)
		local board = boards.Wins
		if not answer or not board or type(answer.rows) ~= "table" then
			pageAsked[page] = nil
			return
		end
		local from = (page - 1) * LB.PageRows
		for i, entry in answer.rows do
			board.data[from + i] = entry
		end
		LobbyBoards.repaint(board)
	end)
end

--- Redraw the rows on screen (the reused frames take the rows the list is scrolled to).
function LobbyBoards.repaint(board: Board)
	local list = board.list
	local first, count = LeaderboardMath.window(
		list.CanvasPosition.Y / board.lod.Scale, -- the list's positions are drawn-size pixels
		rowPx(),
		list.AbsoluteWindowSize.Y / board.lod.Scale,
		board.total,
		#board.rows
	)
	for i, row in board.rows do
		local index = first + i - 1
		if i <= count then
			if row.shown ~= index or not row.frame.Visible then
				paintRow(board, row, index)
			end
			if not board.popped then
				row.frame.Visible = false
				task.delay((i - 1) * C.PopStaggerSeconds, function()
					UIAnim.popIn(row.frame)
				end)
			else
				row.frame.Visible = true
			end
		else
			row.frame.Visible = false
			row.shown = 0
		end
	end
	if count > 0 then
		board.popped = true
	end
	-- The wins' later pages: asked for when the rows on screen reach them.
	if board.key == "Wins" and count > 0 then
		local last = first + count - 1
		if board.data[last] == nil and last <= board.total then
			wantPage(LeaderboardMath.pageOf(last, LB.PageRows))
		end
		if board.data[first] == nil then
			wantPage(LeaderboardMath.pageOf(first, LB.PageRows))
		end
	end
	local deepest = math.min(board.total, first + count - 1)
	if deepest > (deepestSent[board.key] or 0) + LB.PageRows / 10 then
		deepestSent[board.key] = deepest
		task.spawn(invoke, "seen", board.key, deepest)
	end
end

local function paintYou(board: Board)
	local answer = top
	if not answer then
		return
	end
	if board.key == "Wins" then
		local mine = tonumber(answer.wins_mine) or 0
		local place = answer.you
		board.youFlag.Visible = false
		if place then
			board.you.Text = W.You .. "   " .. W.Place:format(Format.commas(place))
		elseif mine > 0 and board.total >= LB.WinsRows then
			board.you.Text = W.You .. "   " .. W.PastList:format(Format.commas(LB.WinsRows))
		elseif mine > 0 then
			board.you.Text = W.You
		else
			board.you.Text = W.NotRanked
		end
		setValue(board.youValue, board.youCup, if mine > 0 then Format.commas(mine) else "", 12)
	else
		local code = answer.country
		local place = answer.countryPlace
		board.youFlag.Visible = code ~= nil
		board.youFlag.Text = PlayerListView.flag(code)
		if place then
			local entry = board.data[place]
			board.you.Text = W.YourCountry .. "   " .. W.Place:format(Format.commas(place))
			setValue(board.youValue, board.youCup, if entry then Format.commas(entry.v) else "", 12)
		else
			board.you.Text = W.NoCountry
			setValue(board.youValue, board.youCup, "", 12)
		end
	end
end

local function setData(board: Board, rows: { any }, total: number)
	board.total = total
	for i, entry in rows do
		board.data[i] = entry
	end
	-- Rows past a shorter list are gone.
	for i = total + 1, #board.data do
		board.data[i] = nil
	end
	board.list.CanvasSize = UDim2.fromOffset(0, total * rowPx())
	board.empty.Visible = total == 0
	for _, row in board.rows do
		row.shown = 0
	end
	paintYou(board)
	LobbyBoards.repaint(board)
end

local function build(model: Model, key: string, playerGui: Instance)
	local face = model:WaitForChild("Face", 30) :: BasePart?
	if not face then
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LobbyBoard" .. key
	gui.Adornee = face
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = C.PixelsPerStud
	-- Far away the board is drawn at fewer pixels a stud, its contents scaled to match, so its
	-- letters are drawn near their size on screen (a board drawn big and shrunk far away looks
	-- jagged; designer, 2026-10-25). The layout stays in full-size pixels.
	local lod = Instance.new("UIScale")
	lod.Name = "LodScale"
	lod.Scale = 1
	lod.Parent = gui
	gui.LightInfluence = 0
	gui.Brightness = 1.2
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ResetOnSpawn = false
	gui.MaxDistance = LB.FetchStuds + 60 -- not drawn from past the roof's far end
	local px = Vector2.new(face.Size.X, face.Size.Y) * C.PixelsPerStud
	local card = HudParts.menuCard(gui, "Card", C.CornerPx)
	card.Position = UDim2.fromOffset(C.MarginPx, C.MarginPx)
	card.Size = UDim2.fromOffset(px.X - 2 * C.MarginPx, px.Y - 2 * C.MarginPx)
	HudParts.livelyCard(card)
	HudParts.setSheetTop(card, C.HeaderPx)
	local cardW, cardH = px.X - 2 * C.MarginPx, px.Y - 2 * C.MarginPx
	local icon = HudParts.icon(card, if key == "Wins" then "Trophy" else "Globe", "Icon")
	icon.Size = UDim2.fromOffset(C.IconPx, C.IconPx)
	icon.Position = UDim2.fromOffset(28, (C.HeaderPx - C.IconPx) / 2)
	icon.ZIndex = 5
	local title =
		HudParts.text(card, "Title", C.TitlePx, if key == "Wins" then W.Wins else W.Countries)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(28 + C.IconPx + 12, 8)
	title.Size = UDim2.new(1, -(28 + C.IconPx + 12) - 24, 0, C.HeaderPx - 16)
	title.ZIndex = 5
	-- The right stick's glyph on an ink disc (as the pad's other glyphs), while a pad scrolls it.
	local padHint = HudParts.frame(card, "PadHint")
	padHint.BackgroundTransparency = 0
	padHint.BackgroundColor3 = HudParts.tone("Ink")
	padHint.Size = UDim2.fromOffset(C.PadHintPx, C.PadHintPx)
	padHint.AnchorPoint = Vector2.new(1, 0.5)
	padHint.Position = UDim2.new(1, -22, 0, C.HeaderPx / 2)
	padHint.ZIndex = 6
	padHint.Visible = false
	HudParts.corner(padHint, C.PadHintPx / 2)
	local glyph = Instance.new("ImageLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.Image = PadMode.glyph(Enum.KeyCode.Thumbstick2)
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Size = UDim2.fromScale(0.8, 0.8)
	glyph.ZIndex = 7
	glyph.Parent = padHint
	local listTop = C.HeaderPx + C.ListTopGapPx + C.ColumnsPx
	-- The numbers' column title, over them (as the player list's "Wins").
	local column = HudParts.note(card, "WinsColumn", C.ColumnsTextPx, W.WinsColumn)
	column.TextXAlignment = Enum.TextXAlignment.Right
	column.Position = UDim2.fromOffset(C.ListPadPx, C.HeaderPx + C.ListTopGapPx)
	column.Size = UDim2.fromOffset(cardW - 2 * C.ListPadPx - 14, C.ColumnsPx)
	column.ZIndex = 5
	local listH = cardH - listTop - C.YouGapPx - C.YouPx - C.ListPadPx / 2
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(C.ListPadPx, listTop)
	list.Size = UDim2.fromOffset(cardW - 2 * C.ListPadPx, listH)
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = HudParts.tone("Ink")
	list.ScrollBarImageTransparency = 0.4
	list.ElasticBehavior = Enum.ElasticBehavior.Never
	list.ZIndex = 5
	list.Parent = card
	-- An empty board (the country board's first minutes) asks for the first win.
	local empty = HudParts.text(card, "Empty", C.TitlePx * 0.6, W.Empty)
	empty.Position = UDim2.fromOffset(C.ListPadPx, listTop)
	empty.Size = UDim2.fromOffset(cardW - 2 * C.ListPadPx, listH)
	empty.ZIndex = 5
	empty.Visible = false
	local youBar = HudParts.frame(card, "You")
	youBar.BackgroundTransparency = 0
	youBar.BackgroundColor3 = HudParts.color(C.YouColor)
	youBar.Position = UDim2.fromOffset(C.ListPadPx, listTop + listH + C.YouGapPx)
	youBar.Size = UDim2.fromOffset(cardW - 2 * C.ListPadPx, C.YouPx)
	youBar.ZIndex = 5
	HudParts.corner(youBar, 14)
	stroke(youBar, 2)
	local youFlag = Instance.new("TextLabel")
	youFlag.Name = "Flag"
	youFlag.BackgroundTransparency = 1
	youFlag.AutoLocalize = false
	youFlag.TextScaled = true
	youFlag.Text = ""
	youFlag.Size = UDim2.fromOffset(C.YouTextPx + 12, C.YouTextPx + 4)
	youFlag.AnchorPoint = Vector2.new(0, 0.5)
	youFlag.Position = UDim2.new(0, 12, 0.5, 0)
	youFlag.ZIndex = 6
	youFlag.Parent = youBar
	local youLeft = if key == "Countries" then 12 + C.YouTextPx + 24 else 14
	local you = HudParts.text(youBar, "Words", C.YouTextPx, W.Loading)
	you.TextXAlignment = Enum.TextXAlignment.Left
	you.Position = UDim2.fromOffset(youLeft, 4)
	you.Size = UDim2.new(1, -youLeft - C.ValueWidthPx - C.YouTrophyPx - 12, 1, -8)
	you.ZIndex = 6
	local cup = HudParts.icon(youBar, "Trophy", "Cup")
	cup.Size = UDim2.fromOffset(C.YouTrophyPx, C.YouTrophyPx)
	cup.AnchorPoint = Vector2.new(1, 0.5)
	cup.Position = UDim2.new(1, -C.ValueWidthPx - 4, 0.5, 0)
	cup.ZIndex = 6
	cup.Visible = false
	local youValue =
		HudParts.text(youBar, "Value", C.YouTextPx, "", HudParts.color(K.Numbers.Money))
	youValue.AutoLocalize = false
	youValue.TextXAlignment = Enum.TextXAlignment.Right
	youValue.AnchorPoint = Vector2.new(1, 0)
	youValue.Position = UDim2.new(1, -12, 0, 4)
	youValue.Size = UDim2.new(0, C.ValueWidthPx - 8, 1, -8)
	youValue.ZIndex = 6
	fixNumber(youValue, C.YouTextPx)
	local board: Board = {
		key = key,
		face = face,
		gui = gui,
		list = list,
		empty = empty,
		rows = {},
		you = you,
		youValue = youValue,
		youCup = cup,
		youFlag = youFlag,
		padHint = padHint,
		data = {},
		total = 0,
		popped = false,
		lod = lod,
		pps = C.PixelsPerStud,
		want = C.PixelsPerStud,
	}
	for i = 1, C.Pool do
		local row = newRow(board, i)
		row.frame.ZIndex = 6
		for _, d in row.frame:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 7
			end
		end
		table.insert(board.rows, row)
	end
	gui.Parent = playerGui
	list:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		LobbyBoards.repaint(board)
	end)
	boards[key] = board
end

---------------------------------------------------------------------------------------------
-- The lists
---------------------------------------------------------------------------------------------

local function fetch()
	lastFetch = os.clock()
	local answer = invoke("top")
	if not answer then
		lastFetch = -math.huge + 1 -- try again on the next pass
		return
	end
	top = answer
	-- A fresh read on the server: the later pages are asked for again when scrolled to.
	table.clear(pageAsked)
	local wins = boards.Wins
	if wins and type(answer.wins) == "table" then
		setData(wins, answer.wins, math.max(#answer.wins, tonumber(answer.total) or 0))
	end
	local countries = boards.Countries
	if countries and type(answer.countries) == "table" then
		setData(countries, answer.countries, #answer.countries)
	end
end

---------------------------------------------------------------------------------------------
-- The gamepad: the right stick scrolls the board you stand at
---------------------------------------------------------------------------------------------

local function padScroll(
	_: string,
	state: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	if state == Enum.UserInputState.Cancel or state == Enum.UserInputState.End then
		padY = 0
	else
		local y = input.Position.Y
		padY = if math.abs(y) < LB.PadDeadzone then 0 else y
	end
	return Enum.ContextActionResult.Sink
end

local function setPadBoard(board: Board?)
	if padBoard == board then
		return
	end
	if padBoard then
		padBoard.padHint.Visible = false
	end
	padBoard = board
	padY = 0
	if board then
		board.padHint.Visible = true
		ContextActionService:BindActionAtPriority(
			PAD_ACTION,
			padScroll,
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.KeyCode.Thumbstick2
		)
		if not padStep then
			padStep = RunService.Heartbeat:Connect(function(dt: number)
				local b = padBoard
				if b and padY ~= 0 then
					local list = b.list
					local maxY = math.max(0, list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y)
					local y = list.CanvasPosition.Y
						- padY * LB.PadScrollRowsPerSecond * rowPx() * b.lod.Scale * dt
					list.CanvasPosition = Vector2.new(0, math.clamp(y, 0, maxY))
				end
			end)
		end
	else
		ContextActionService:UnbindAction(PAD_ACTION)
		if padStep then
			padStep:Disconnect()
			padStep = nil
		end
	end
end

---------------------------------------------------------------------------------------------
-- The pass: near enough to fetch, close and facing to count as seen (and for the pad)
---------------------------------------------------------------------------------------------

-- Draw `board` at the fewest pixels a stud (LodSteps) that still give its letters about
-- LodOversample canvas pixels for each pixel on screen; a level changes after two passes agree.
-- Each text's size limits at full detail: a UIScale shrinks a text's box but not its
-- UITextSizeConstraint, so a scaled text would fill its box and grow on the board from far away
-- (designer, 2026-10-25: "just keep it one consistent font size"). The limits scale with it.
local textBase: { [UITextSizeConstraint]: { max: number, min: number } } = setmetatable(
	{},
	{ __mode = "k" }
) :: any

local function scaleTexts(board: Board, was: number, scale: number)
	for _, limit in board.gui:GetDescendants() do
		if limit:IsA("UITextSizeConstraint") then
			local base = textBase[limit]
			if not base then
				base = { max = limit.MaxTextSize / was, min = limit.MinTextSize / was }
				textBase[limit] = base
			end
			limit.MaxTextSize = math.max(1, math.floor(base.max * scale + 0.5))
			limit.MinTextSize = math.max(1, math.floor(base.min * scale + 0.5))
		end
	end
end

local function sharpen(board: Board, camera: Camera)
	local distance = (camera.CFrame.Position - board.face.Position).Magnitude
	local onScreen = camera.ViewportSize.Y
		/ (2 * math.max(1, distance) * math.tan(math.rad(camera.FieldOfView) / 2))
	local ideal = onScreen * C.LodOversample
	local pick = C.PixelsPerStud
	for _, step in C.LodSteps do
		if step >= ideal and step < pick then
			pick = step
		end
	end
	if pick == board.pps then
		board.want = pick
		return
	end
	if pick ~= board.want then
		board.want = pick
		return
	end
	local list = board.list
	local was = board.lod.Scale
	local scale = pick / C.PixelsPerStud
	board.gui.PixelsPerStud = pick
	board.lod.Scale = scale
	scaleTexts(board, was, scale)
	board.pps = pick
	list.CanvasPosition = Vector2.new(0, list.CanvasPosition.Y * scale / was)
end

local function pass()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local camera = workspace.CurrentCamera
	if not root or not camera then
		return
	end
	local nearest: Board? = nil
	local nearestDistance = math.huge
	local anyNear = false
	for key, board in boards do
		local to = board.face.Position - root.Position
		local distance = Vector3.new(to.X, 0, to.Z).Magnitude
		if distance <= LB.FetchStuds then
			anyNear = true
		end
		local look = camera.CFrame.LookVector
		local flat = Vector3.new(to.X, 0, to.Z)
		local facing = flat.Magnitude > 0
			and Vector3.new(look.X, 0, look.Z).Unit:Dot(flat.Unit) >= LB.FacingDot
		-- The board's front must face the player too (a stand seen from behind is no view).
		local front = board.face.CFrame.LookVector
		local fromFront = front:Dot(-to) > 0
		if distance <= LB.ViewStuds and facing and fromFront then
			if not seenSent[key] then
				seenSent[key] = true
				task.spawn(invoke, "seen", key, 0)
			end
			if distance < nearestDistance then
				nearest = board
				nearestDistance = distance
			end
		end
	end
	if anyNear and os.clock() - lastFetch >= LB.FetchSeconds then
		task.spawn(fetch)
	end
	setPadBoard(if PadMode.active() then nearest else nil)
	for _, board in boards do
		sharpen(board, camera)
	end
end

--- Draw the lobby boards on the stands the server built (a lobby server only).
function LobbyBoards.start(playerGui: Instance)
	if LB.Enabled ~= true then
		return
	end
	task.spawn(function()
		local folder = workspace:WaitForChild("Leaderboards", 60)
		if not folder then
			return
		end
		readRemote = Net.get("LeaderboardRead") :: RemoteFunction
		for _, key in { "Wins", "Countries" } do
			local model = folder:WaitForChild(key, 30)
			if model and model:IsA("Model") then
				build(model, key, playerGui)
			end
		end
		while true do
			local ok, err = pcall(function()
				pass()
			end)
			if not ok then
				warn("[8ball] LobbyBoards: " .. tostring(err))
			end
			task.wait(LB.CheckSeconds)
		end
	end)
end

-- Studio checks: fill the boards with `n` made-up rows, scroll one, read their state.
GuiQA.add("boardsFake", function(n: number?): any
	local count = n or LB.WinsRows
	local wins, countries = {}, {}
	local codes = { "US", "BR", "PH", "GB", "MX", "CA", "ID", "DE", "AU", "FR", "XX" }
	for i = 1, count do
		wins[i] = { u = player.UserId, n = ("Player_%d"):format(i), v = 2000 - i }
	end
	for i, code in codes do
		countries[i] = { c = code, v = 5000 - i * 300 }
	end
	top = {
		wins_mine = 52,
		you = 37,
		country = "US",
		countryPlace = 1,
	}
	pageAsked = {}
	for page = 2, 10 do
		pageAsked[page] = os.clock() -- the fake rows are all here: ask the server for none
	end
	if boards.Wins then
		setData(boards.Wins, wins, count)
	end
	if boards.Countries then
		setData(boards.Countries, countries, #countries)
	end
	return true
end)
GuiQA.add("boardsScroll", function(key: string?, y: number?): any
	local board = boards[key or "Wins"]
	if board then
		board.list.CanvasPosition = Vector2.new(0, y or 0)
		return board.list.CanvasPosition.Y
	end
	return nil
end)
GuiQA.add("boardsInfo", function(): any
	local out = {}
	for key, board in boards do
		local shown = {}
		for _, row in board.rows do
			if row.frame.Visible then
				table.insert(shown, row.shown)
			end
		end
		table.sort(shown)
		out[key] = {
			total = board.total,
			instances = #board.gui:GetDescendants(),
			first = shown[1],
			last = shown[#shown],
			you = board.you.Text,
			youValue = board.youValue.Text,
		}
	end
	return out
end)

return LobbyBoards
