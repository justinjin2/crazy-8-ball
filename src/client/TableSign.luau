--!strict
-- TableSign: the small card floating over a table's queue pad. It says the table's mode big
-- (1v1, 2v2 or 3v3), who hosts, how many are on the pad, the difficulty, and whether it is
-- waiting, about to start, full or playing. An empty pad's sign has no host row and no pill:
-- stepping on is the way in. No abilities: they are not in the release (designer, 2026-09-27).
--
-- Only one shows: over the table you walk right up to (Config.UI.Sign, measured by
-- Placement.nearestArea). Never while you are on a pad (the matchmaking bar, MatchBar, says
-- it all, host or guest; 2026-10-07) or play. It pops in when you arrive and pops out when
-- you walk away (designer, 2026-09-25: it used to hang over all sixteen tables
-- all the time).
--
-- It is drawn from the table snapshot every client already has, so everyone near a table
-- reads the same thing; the server only keeps the pad itself (TableService).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Placement = require(Shared:WaitForChild("Placement"))
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local Copy = Strings.Match
local Sign = Config.UI.Sign
local K = Config.UI.Kit
local tone = HudParts.tone
local TableSign = {}
TableSign.__index = TableSign

function TableSign.new(playerGui: Instance): any
	local self: any = setmetatable({}, TableSign)
	self.id = nil -- the table the sign is over (or on its way to)
	self.token = 0 -- the latest show or hide, so a finished pop-out never undoes a newer one
	local gui = Instance.new("BillboardGui")
	gui.Name = "TableSign"
	gui.Size = UDim2.fromOffset(Sign.WidthPx, 0) -- its height follows the rows (fill)
	gui.StudsOffsetWorldSpace = Vector3.new(0, Sign.HeightStuds, 0)
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = playerGui
	self.gui = gui
	-- The card leaves room round it for its shadow and the pop's overshoot, and below it for
	-- the status pill.
	local card = HudParts.card(gui, "Card")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, Sign.MarginPx)
	card.Size = UDim2.new(1, -Sign.MarginPx * 2, 0, 0)
	card.Visible = false
	self.card = card
	local pad = 10
	-- The mode, big: 1v1, 2v2 or 3v3 (designer, 2026-09-27).
	self.mode = HudParts.text(card, "Mode", Sign.ModeTextPx, "")
	self.mode.TextWrapped = false
	self.mode.Position = UDim2.fromOffset(pad, 4)
	self.mode.Size = UDim2.new(1, -pad * 2, 0, Sign.ModeTextPx + 2)
	-- A crown by the host's name, once somebody is on the pad.
	local rowHeight = 28
	self.crown = HudParts.icon(card, "Crown")
	self.crown.Size = UDim2.fromOffset(rowHeight, rowHeight)
	self.host = HudParts.text(card, "Host", K.Text.Body, "")
	self.host.AutoLocalize = false
	self.host.TextScaled = false
	self.host.TextWrapped = false
	self.host.TextTruncate = Enum.TextTruncate.AtEnd
	self.host.TextXAlignment = Enum.TextXAlignment.Left
	self.host.Size = UDim2.new(1, -pad * 2 - rowHeight - 6, 0, rowHeight)
	-- People n/6 and the difficulty, side by side and centred, Sign.InfoGapPx apart.
	local info = HudParts.frame(card, "Info")
	info.Size = UDim2.new(1, -pad * 2, 0, rowHeight)
	local infoList = Instance.new("UIListLayout")
	infoList.FillDirection = Enum.FillDirection.Horizontal
	infoList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	infoList.VerticalAlignment = Enum.VerticalAlignment.Center
	infoList.SortOrder = Enum.SortOrder.LayoutOrder
	infoList.Padding = UDim.new(0, Sign.InfoGapPx)
	infoList.Parent = info
	self.info = info
	-- An icon and its words, sized to the words.
	local function item(order: number, iconKey: string, iconName: string): (ImageLabel, TextLabel)
		local group = HudParts.frame(info, iconName .. "Item")
		group.LayoutOrder = order
		group.AutomaticSize = Enum.AutomaticSize.X
		group.Size = UDim2.fromOffset(0, rowHeight)
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Horizontal
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, 4)
		list.Parent = group
		local icon = HudParts.icon(group, iconKey, iconName)
		icon.LayoutOrder = 1
		icon.Size = UDim2.fromOffset(rowHeight, rowHeight)
		local words = HudParts.text(group, "Text", Sign.InfoTextPx, "")
		words.LayoutOrder = 2
		words.TextScaled = false
		words.TextWrapped = false
		words.AutomaticSize = Enum.AutomaticSize.X
		words.Size = UDim2.fromOffset(0, rowHeight)
		return icon, words
	end
	self.people, self.count = item(1, "People", "People")
	self.count.AutoLocalize = false -- only numbers
	self.level, self.levelName = item(2, "Classic", "LevelIcon")
	self.rowHeight, self.pad = rowHeight, pad
	-- The status pill hangs off the bottom edge: waiting, starting, full or playing. An empty
	-- pad has none: stepping on is the way in (designer, 2026-09-27).
	self.status = HudParts.pill(card, "Status")
	self.status.AnchorPoint = Vector2.new(0.5, 0.5)
	self.status.Position = UDim2.fromScale(0.5, 1)
	self.status.Size = UDim2.fromOffset(150, 32)
	self.statusText = HudParts.text(self.status, "Text", K.Text.Body, "")
	self.statusText.TextWrapped = false
	self.statusText.Position = UDim2.fromOffset(8, 2)
	self.statusText.Size = UDim2.new(1, -16, 1, -4)
	return self
end

-- Lay the rows out top to bottom, the host's only when there is one, and fit the card and
-- the sign round them.
function TableSign.arrange(self: any, hasHost: boolean, hasPill: boolean)
	local rowHeight, pad, gap = self.rowHeight, self.pad, 2
	local top = 4 + Sign.ModeTextPx + 2 + gap
	self.crown.Visible = hasHost
	self.host.Visible = hasHost
	if hasHost then
		self.crown.Position = UDim2.fromOffset(pad, top)
		self.host.Position = UDim2.fromOffset(pad + rowHeight + 6, top)
		top += rowHeight + gap
	end
	self.info.Position = UDim2.fromOffset(pad, top)
	local height = top + rowHeight + (if hasPill then 16 else 8)
	self.status.Visible = hasPill
	self.card.Size = UDim2.new(1, -Sign.MarginPx * 2, 0, height)
	self.gui.Size = UDim2.fromOffset(Sign.WidthPx, height + Sign.MarginPx * 2 + 16)
end

-- Write table `id`'s card from its snapshot (nil until it has arrived: an empty pad).
function TableSign.fill(self: any, id: number, snapshot: any?, now: number)
	local teamSize = if snapshot then snapshot.teamSize else Placement.teamSizeOf(id) or 1
	local capacity = teamSize * 2
	local phase = if snapshot then snapshot.phase else "Waiting"
	local waiting = phase == "Waiting"
	local count, hostName = 0, nil
	for _, seat in (if snapshot then snapshot.seats else {}) do
		if seat.connected ~= false then
			count += 1
			if seat.userId == snapshot.hostId then
				hostName = seat.displayName or seat.name
			end
		end
	end
	local solo = snapshot and snapshot.solo
	-- The table's own mode, SOLO while somebody plays it alone.
	self.mode.Text = if solo then Copy.SoloTitle else Copy.Mode:format(teamSize, teamSize)
	self.host.Text = hostName or ""
	self.count.Text = Copy.Queue.PlayerCount:format(count, capacity)
	local difficulty = snapshot and snapshot.settings and snapshot.settings.difficulty
		or Config.Difficulty.Default
	HudParts.setIcon(self.level, difficulty)
	self.levelName.Text = Copy.Queue.Levels[difficulty] or ""
	local words: string?, colour: string? = nil, nil
	local startsAt = snapshot and snapshot.startsAt
	if not waiting then
		words, colour = Copy.PadPlaying, "Blue"
	elseif startsAt then
		words, colour = Copy.Starting:format(math.max(1, math.ceil(startsAt - now))), "Green"
	elseif count >= capacity then
		words, colour = Copy.PadFull, "Red"
	elseif count > 0 then
		words, colour = Copy.Waiting, "Gold"
	end
	self.statusText.Text = words or ""
	if colour then
		self.status.BackgroundColor3 = tone(colour)
	end
	self:arrange(hostName ~= nil, words ~= nil)
end

-- The sign hangs over the table's pad. Its StudsOffsetWorldSpace is measured in the pad's own
-- axes, so it rises straight up only because the pad lies level (TableService.buildPad).
local function padPart(zones: Instance, id: number): BasePart?
	local part = zones:FindFirstChild(("QueuePad_%02d"):format(id))
	return if part and part:IsA("BasePart") then part else nil
end

--- Step the sign. `position` is the local character's (nil without one); `busy` is true
--- while the player hosts or plays (no sign at all); `guestOf` is the table whose pad the
--- player waits on as a guest, whose sign shows wherever they stand on it; `snapshotFor`
--- gives a table's latest snapshot; `now` is the server's clock, for the countdown.
function TableSign.update(
	self: any,
	position: Vector3?,
	busy: boolean,
	guestOf: number?,
	zones: Instance,
	snapshotFor: (number) -> any?,
	now: number
)
	local target: number? = nil
	if busy then
		target = nil
	elseif guestOf then
		target = guestOf
	elseif position then
		local id, distance = Placement.nearestArea(position.X, position.Z)
		local limit = if id == self.id then Sign.HideStuds else Sign.ShowStuds
		if id and distance <= limit and padPart(zones, id) then
			target = id
		end
	end
	if target ~= self.id then
		self.id = target
		self.token += 1
		local token = self.token
		local function arrive()
			if token ~= self.token then
				return
			end
			if target then
				self.gui.Adornee = padPart(zones, target)
				self.gui.Enabled = true
				self:fill(target, snapshotFor(target), now)
				UIAnim.popIn(self.card)
			else
				self.gui.Enabled = false
			end
		end
		-- Pop the old sign out first (it may be over another table), then show the new one.
		UIAnim.popOut(self.card, arrive)
	end
	if self.id and self.card.Visible then
		self:fill(self.id, snapshotFor(self.id), now)
	end
end

return TableSign
