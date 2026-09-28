--!strict
-- TradeMenu: the Trade menu (docs/prompts/ECONOMY_UI_PROMPT.md section 11), opened from the left
-- column's Trade tile (or the D-pad's left in the hub) through Menus. No tabs. Trading itself
-- is a later session: this is its frame, marked Soon.
--   * At the top, a note: a gold SOON pill, "Trading is coming soon!" and a line about it.
--   * Under it, every other player in this server, one row each (sorted by name): their
--     headshot (Players:GetUserThumbnailAsync, cached, fetched in the background), their rank
--     badge (from their RankTier and RankDivision attributes, RankBadge), their username (never
--     translated; a long one ends in "...") with their rank's name under it, and a greyed
--     Trade button that only says trading is coming soon. No trading code.
--   * Alone in the server: "No one else is in this server yet."
-- The list is built when the menu opens and follows players joining and leaving and their
-- ranks changing while it is open; it is taken down when the menu closes (so the badges stop
-- shining). Gamepad: opening lands on the first row's Trade button; the list scrolls with the
-- selection (MenuFrame.scroller); B closes (Menus). Sizes in Config.UI.Trade.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Ranks = require(Shared:WaitForChild("Progression"):WaitForChild("Ranks"))
local HudParts = require(script.Parent.HudParts)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local RankBadge = require(script.Parent.RankBadge)

local NAME = "Trade"
local C = Config.UI.Trade
local K = Config.UI.Kit
local CARD = Config.UI.Menu.Card
local SC = Config.UI.Menu.Scroll
local W = Strings.Menus.Trade
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local THUMB_SIZE: Enum.ThumbnailSize = (Enum.ThumbnailSize :: any)[C.Thumbnail]
	or Enum.ThumbnailSize.Size150x150
local color = HudParts.color

type Row = {
	player: Player,
	root: Frame,
	headshot: ImageLabel,
	badge: RankBadge.Badge,
	name: TextLabel,
	rank: TextLabel,
	button: TextButton,
	connections: { RBXScriptConnection },
}

-- Headshots fetched this session, by user id.
local headshots: { [number]: string } = {}

local function round(n: number): number
	return math.floor(n + 0.5)
end

-- A { phone, full } pair at t, in whole pixels.
local function span(pair: { number }, t: number): number
	return round(pair[1] + (pair[2] - pair[1]) * t)
end

local function gamepadInUse(): boolean
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

-- Put a player's headshot in `image` (cached; fetched once, in the background).
local function loadHeadshot(userId: number, image: ImageLabel)
	local cached = headshots[userId]
	if cached then
		image.Image = cached
		return
	end
	if userId <= 0 then
		return
	end
	task.spawn(function()
		local ok, content, ready = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, THUMB_SIZE)
		end)
		if ok and type(content) == "string" and ready then
			headshots[userId] = content
			if image.Parent then
				image.Image = content
			end
		end
	end)
end

-- A player's rank from their attributes (Unranked until known).
local function rankOf(player: Player): (string, number)
	local tier = player:GetAttribute("RankTier")
	local division = player:GetAttribute("RankDivision")
	return if type(tier) == "string" then tier else "Unranked",
		if type(division) == "number" then division else 0
end

local TradeMenu = {}

--- Build the Trade menu (closed) and register it with Menus. `deps`: see InventoryMenu.new
--- (nothing here needs them yet).
function TradeMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local frame = MenuFrame.new(screen, {
		name = NAME,
		title = Strings.Menus.Titles.Trade,
		icon = "Trade",
	})
	local page = frame:page()
	local _ = deps

	-- The note: a gold SOON pill, the words, a line about it.
	local note = HudParts.frame(page, "Note")
	note.ZIndex = 3
	local noteFill = HudParts.frame(note, "Fill")
	noteFill.Size = UDim2.fromScale(1, 1)
	noteFill.BackgroundTransparency = 0
	noteFill.BackgroundColor3 = HudParts.tone("White")
	noteFill.ZIndex = 3
	HudParts.corner(noteFill, CARD.CornerPx)
	local noteEdge = Instance.new("UIStroke")
	noteEdge.Color = color(CARD.EdgeColor)
	noteEdge.Thickness = CARD.StrokePx
	noteEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	noteEdge.Parent = noteFill
	local soon = HudParts.pill(note, "Soon", HudParts.tone("Gold"))
	soon.AnchorPoint = Vector2.new(0, 0.5)
	soon.ZIndex = 4
	local soonWords = HudParts.text(soon, "Words", C.SoonTextPx[2], W.Soon)
	soonWords.TextWrapped = false
	soonWords.Size = UDim2.fromScale(1, 1)
	soonWords.ZIndex = 5
	local headline = HudParts.text(note, "Headline", C.NoteTextPx[2], W.Note)
	headline.TextWrapped = false
	headline.TextXAlignment = Enum.TextXAlignment.Left
	headline.ZIndex = 4
	local detail = HudParts.note(note, "Detail", C.NoteDetailPx[2], W.Detail)
	detail.TextWrapped = false
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.ZIndex = 4

	-- The list.
	local listArea = HudParts.frame(page, "Players")
	listArea.ZIndex = 3
	local scroll, list = MenuFrame.scroller(listArea, { kind = "List", name = "List" })
	local empty = MenuFrame.placeholder(listArea, W.Empty)
	empty.Visible = false

	local rows: { [Player]: Row } = {}
	local order: { Row } = {}
	local geo: MenuFrame.Geo? = nil
	local connections: { RBXScriptConnection } = {}
	local rebuildQueued = false
	-- Players whose PlayerRemoving fired (they are still in Players for a moment).
	local leaving: { [Player]: boolean } = {}

	local function sizeRow(row: Row, rowW: number, rowH: number, t: number)
		row.root.Size = UDim2.fromOffset(rowW, rowH)
		local pad = span(C.RowPadPx, t)
		local head = round(rowH * C.HeadshotShare)
		row.headshot.Size = UDim2.fromOffset(head, head)
		row.headshot.Position = UDim2.fromOffset(pad, round((rowH - head) / 2))
		local badgePx = round(rowH * C.BadgeShare)
		row.badge:setSize(badgePx)
		row.badge.root.Position = UDim2.fromOffset(pad + head + pad, round((rowH - badgePx) / 2))
		local buttonW = span(C.ButtonWidthPx, t)
		local buttonH = math.min(C.ButtonPx, rowH - 2 * pad)
		row.button.Size = UDim2.fromOffset(buttonW, buttonH)
		row.button.Position = UDim2.fromOffset(rowW - pad - buttonW, round((rowH - buttonH) / 2))
		HudParts.setButtonTextSize(
			row.button,
			math.max(K.Text.Min, if geo then geo.button else K.Text.Button)
		)
		local x = pad + head + pad + badgePx + pad
		local textW = math.max(1, rowW - x - buttonW - 2 * pad)
		local namePx = span(C.NameTextPx, t)
		local rankPx = span(C.RankTextPx, t)
		local nameH, rankH = namePx + 6, rankPx + 4
		local top = round((rowH - nameH - rankH) / 2)
		row.name.TextSize = namePx
		local stroke = row.name:FindFirstChild("Outline")
		if stroke and stroke:IsA("UIStroke") then
			stroke.Thickness = if namePx < K.TextOutlineThinBelowPx
				then K.TextOutlineThinPx
				else math.max(K.TextOutlineMinPx, round(namePx * K.TextOutlineRatio))
		end
		row.name.Position = UDim2.fromOffset(x, top)
		row.name.Size = UDim2.fromOffset(textW, nameH)
		HudParts.setTextSize(row.rank, rankPx)
		row.rank.Position = UDim2.fromOffset(x, top + nameH)
		row.rank.Size = UDim2.fromOffset(textW, rankH)
	end

	-- Size and place the note and the list from the menu's layout.
	local function layout()
		local g = geo
		if not g then
			return
		end
		local width, height = g.content.X, g.content.Y
		local t = g.t
		local noteH = span(C.NotePx, t)
		local listW = math.min(width, C.MaxWidthPx)
		local x = round((width - listW) / 2)
		note.Position = UDim2.fromOffset(x, 0)
		note.Size = UDim2.fromOffset(listW, noteH)
		local pad = span(C.RowPadPx, t)
		local soonPx = span(C.SoonTextPx, t)
		local soonH = soonPx + 10
		local soonW = math.ceil(
			TextService:GetTextSize(W.Soon, soonPx, FONT, Vector2.new(400, 100)).X
		) + 20
		soon.Position = UDim2.fromOffset(pad, round(noteH / 2))
		soon.Size = UDim2.fromOffset(soonW, soonH)
		HudParts.setTextSize(soonWords, soonPx)
		local textX = pad + soonW + pad
		local textW = math.max(1, listW - textX - pad)
		local headPx = span(C.NoteTextPx, t)
		local detailPx = span(C.NoteDetailPx, t)
		local headH, detailH = headPx + 4, detailPx + 4
		local top = round((noteH - headH - detailH) / 2)
		HudParts.setTextSize(headline, headPx)
		headline.Position = UDim2.fromOffset(textX, top)
		headline.Size = UDim2.fromOffset(textW, headH)
		HudParts.setTextSize(detail, detailPx)
		detail.Position = UDim2.fromOffset(textX, top + headH)
		detail.Size = UDim2.fromOffset(textW, detailH)

		local gap = span(C.RowGapPx, t)
		listArea.Position = UDim2.fromOffset(0, noteH + gap)
		listArea.Size = UDim2.fromOffset(width, math.max(1, height - noteH - gap))
		if list:IsA("UIListLayout") then
			list.Padding = UDim.new(0, gap)
		end
		local rowW = math.max(1, listW - 2 * SC.PadPx - SC.BarPx)
		local rowH = span(C.RowPx, t)
		for _, row in order do
			sizeRow(row, rowW, rowH, t)
		end
	end

	local function showRank(row: Row)
		local tier, division = rankOf(row.player)
		row.badge:set(tier, division)
		row.rank.Text = Ranks.name({ tier = tier, division = division } :: any)
	end

	local function makeRow(player: Player): Row
		local root = HudParts.frame(scroll, "Player")
		root.ZIndex = 3
		local fill = HudParts.frame(root, "Fill")
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundTransparency = 0
		fill.BackgroundColor3 = HudParts.tone("White")
		fill.ZIndex = 3
		HudParts.corner(fill, CARD.CornerPx)
		local edge = Instance.new("UIStroke")
		edge.Color = color(CARD.EdgeColor)
		edge.Thickness = CARD.StrokePx
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Parent = fill
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Color = ColorSequence.new(HudParts.tone("White"), color(K.PanelFade))
		fade.Parent = fill
		local headshot = Instance.new("ImageLabel")
		headshot.Name = "Headshot"
		headshot.BackgroundTransparency = 0
		headshot.BackgroundColor3 = color(K.PanelFade)
		headshot.BorderSizePixel = 0
		headshot.ScaleType = Enum.ScaleType.Fit
		headshot.ZIndex = 4
		local roundness = Instance.new("UICorner")
		roundness.CornerRadius = UDim.new(0.5, 0)
		roundness.Parent = headshot
		local ring = Instance.new("UIStroke")
		ring.Color = HudParts.tone("Ink")
		ring.Thickness = 2
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.Parent = headshot
		headshot.Parent = root
		loadHeadshot(player.UserId, headshot)
		local badge = RankBadge.new(root, { size = 40, name = "Badge", zIndex = 4, rays = false })
		local name = HudParts.text(root, "Name", C.NameTextPx[2], player.Name)
		name.AutoLocalize = false -- a username is never translated
		name.TextScaled = false
		name.TextWrapped = false
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.ZIndex = 5
		local rank = HudParts.note(root, "Rank", C.RankTextPx[2], "")
		rank.TextWrapped = false
		rank.TextXAlignment = Enum.TextXAlignment.Left
		rank.ZIndex = 5
		local button = HudParts.candy(root, W.Button, function()
			frame:notice(W.Pressed, "Ink")
		end, "Grey", "Trade")
		button.Name = "Trade"
		button.ZIndex = 6
		HudParts.setMinHit(button, C.ButtonPx)
		local row: Row = {
			player = player,
			root = root,
			headshot = headshot,
			badge = badge,
			name = name,
			rank = rank,
			button = button,
			connections = {},
		}
		showRank(row)
		for _, attribute in { "RankTier", "RankDivision" } do
			table.insert(
				row.connections,
				player:GetAttributeChangedSignal(attribute):Connect(function()
					showRank(row)
				end)
			)
		end
		return row
	end

	local function dropRow(row: Row)
		for _, connection in row.connections do
			connection:Disconnect()
		end
		row.badge:destroy()
		row.root:Destroy()
	end

	-- Every other player, sorted by name (then user id), one row each.
	local function rebuild()
		local players: { Player } = {}
		local present: { [Player]: boolean } = {}
		for _, player in Players:GetPlayers() do
			present[player] = true
			if player ~= Players.LocalPlayer and not leaving[player] then
				table.insert(players, player)
			end
		end
		for player in leaving do
			if not present[player] then
				leaving[player] = nil
			end
		end
		table.sort(players, function(a: Player, b: Player): boolean
			local an, bn = string.lower(a.Name), string.lower(b.Name)
			if an ~= bn then
				return an < bn
			end
			return a.UserId < b.UserId
		end)
		local keep: { [Player]: boolean } = {}
		for _, player in players do
			keep[player] = true
		end
		for player, row in rows do
			if not keep[player] then
				dropRow(row)
				rows[player] = nil
			end
		end
		table.clear(order)
		for index, player in players do
			local row = rows[player] or makeRow(player)
			rows[player] = row
			row.root.LayoutOrder = index
			table.insert(order, row)
		end
		-- Straight up and down the list with the D-pad.
		for index, row in order do
			local above = order[index - 1]
			local below = order[index + 1]
			row.button.NextSelectionUp = (if above then above.button else nil) :: any
			row.button.NextSelectionDown = (if below then below.button else nil) :: any
		end
		empty.Visible = #order == 0
		layout()
		-- A selection on a row that left goes to the first row, or the red X.
		local selected = GuiService.SelectedObject
		if
			gamepadInUse()
			and frame:isOpen()
			and (selected == nil or not selected:IsDescendantOf(game))
		then
			GuiService.SelectedObject = if order[1] then order[1].button else nil
			if GuiService.SelectedObject == nil then
				frame:focus()
			end
		end
	end

	local function queueRebuild()
		if rebuildQueued then
			return
		end
		rebuildQueued = true
		task.defer(function()
			rebuildQueued = false
			if frame:isOpen() then
				rebuild()
			end
		end)
	end

	local function clear()
		for player, row in rows do
			dropRow(row)
			rows[player] = nil
		end
		table.clear(order)
	end

	frame.onLayout = function(g: MenuFrame.Geo)
		geo = g
		layout()
	end
	frame.onOpen = function()
		rebuild()
		table.insert(connections, Players.PlayerAdded:Connect(queueRebuild))
		table.insert(
			connections,
			Players.PlayerRemoving:Connect(function(player: Player)
				leaving[player] = true
				queueRebuild()
			end)
		)
		if gamepadInUse() and order[1] then
			GuiService.SelectedObject = order[1].button
		end
	end
	frame.onClose = function()
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		-- Taken down once it has popped out (the badges stop shining with it).
		task.delay(Config.UI.Kit.Motion.OutSeconds + 0.05, function()
			if not frame:isOpen() then
				clear()
			end
		end)
	end

	local handle: Menus.Handle = {
		open = function(_tab: string?)
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

return TradeMenu
