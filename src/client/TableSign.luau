--!strict
-- TableSign: the card floating over a table's queue box. It says what the table is doing
-- (the modes, or the game being played), who hosts, how many are in, the chosen difficulty,
-- and whether you can step in.
--
-- Only one shows, over the table you walk right up to (Config.UI.Sign, measured by
-- Placement.nearestArea), and never while you are in a box or playing: the host menu or the
-- top bar says it all then. It pops in when you arrive and pops out when you walk away
-- (designer, 2026-09-25: it used to hang over all sixteen tables all the time).
--
-- It is drawn from the table snapshot every client already has, so everyone near a table
-- reads the same thing; the server only keeps the box itself (TableService).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Placement = require(Shared:WaitForChild("Placement"))
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local Copy = Strings.Match
local M = Config.Multiplayer
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
	gui.Size = UDim2.fromOffset(Sign.WidthPx, Sign.HeightPx)
	gui.StudsOffsetWorldSpace = Vector3.new(0, Sign.HeightStuds, 0)
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = playerGui
	self.gui = gui
	-- The card leaves room round it for its shadow, the pop's overshoot and the status pill.
	local card = HudParts.card(gui, "Card")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.new(0.5, 0, 0.5, -8)
	card.Size = UDim2.new(1, -28, 1, -44)
	card.Visible = false
	self.card = card
	local pad = 10
	self.mode = HudParts.text(card, "Mode", K.Text.Heading - 4, "")
	self.mode.TextWrapped = false
	self.mode.Position = UDim2.fromOffset(pad, 6)
	self.mode.Size = UDim2.new(1, -pad * 2, 0, 30)
	-- A crown by the host's name.
	local rowHeight = 28
	self.crown = HudParts.icon(card, "Crown")
	self.crown.Position = UDim2.fromOffset(pad, 40)
	self.crown.Size = UDim2.fromOffset(rowHeight, rowHeight)
	self.host = HudParts.text(card, "Host", K.Text.Body, "")
	self.host.AutoLocalize = false
	self.host.TextScaled = false
	self.host.TextWrapped = false
	self.host.TextTruncate = Enum.TextTruncate.AtEnd
	self.host.TextXAlignment = Enum.TextXAlignment.Left
	self.host.Position = UDim2.fromOffset(pad + rowHeight + 6, 40)
	self.host.Size = UDim2.new(1, -pad * 2 - rowHeight - 6, 0, rowHeight)
	-- People n/6 on the left, the difficulty's picture and name on the right.
	local infoTop = 40 + rowHeight + 4
	self.people = HudParts.icon(card, "People")
	self.people.Position = UDim2.fromOffset(pad, infoTop)
	self.people.Size = UDim2.fromOffset(rowHeight, rowHeight)
	self.count = HudParts.text(card, "Count", K.Text.Body, "")
	self.count.AutoLocalize = false -- only numbers
	self.count.TextXAlignment = Enum.TextXAlignment.Left
	self.count.Position = UDim2.fromOffset(pad + rowHeight + 4, infoTop)
	self.count.Size = UDim2.new(0.4, -rowHeight, 0, rowHeight)
	self.level = HudParts.icon(card, "Classic", "LevelIcon")
	self.level.Position = UDim2.new(0.42, 0, 0, infoTop)
	self.level.Size = UDim2.fromOffset(rowHeight, rowHeight)
	self.levelName = HudParts.text(card, "Level", K.Text.Body, "")
	self.levelName.TextXAlignment = Enum.TextXAlignment.Left
	self.levelName.Position = UDim2.new(0.42, rowHeight + 4, 0, infoTop)
	self.levelName.Size = UDim2.new(0.58, -rowHeight - 4 - pad, 0, rowHeight)
	-- The status pill hangs off the bottom edge: step in, waiting, full or playing.
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

-- Write the card from the table's snapshot (nil until it has arrived: an empty box).
function TableSign.fill(self: any, snapshot: any?)
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
	self.mode.Text = if solo
		then Copy.SoloTitle
		elseif waiting then Copy.AnyMode
		else Copy.Mode:format(snapshot.teamSize, snapshot.teamSize)
	self.crown.Visible = hostName ~= nil
	self.host.Text = hostName or Copy.StepIn
	self.host.Position = UDim2.fromOffset(if hostName then 44 else 10, 40)
	self.count.Text = Copy.Queue.PlayerCount:format(count, M.Queue.Capacity)
	local difficulty = snapshot and snapshot.settings and snapshot.settings.difficulty
		or Config.Difficulty.Default
	HudParts.setIcon(self.level, difficulty)
	self.levelName.Text = Copy.Queue.Levels[difficulty] or ""
	local words, colour
	if not waiting then
		words, colour = Copy.SignPlaying, "Blue"
	elseif count >= M.Queue.Capacity then
		words, colour = Copy.BoxFull, "Red"
	elseif count > 0 then
		words, colour = Copy.Waiting, "Gold"
	else
		words, colour = Copy.SignStepIn, "Green"
	end
	self.statusText.Text = words
	self.status.BackgroundColor3 = tone(colour)
end

local function boxPart(zones: Instance, id: number): BasePart?
	local part = zones:FindFirstChild(("QueueBox_%02d"):format(id))
	return if part and part:IsA("BasePart") then part else nil
end

--- Step the sign. `position` is the local character's (nil without one); `busy` is true
--- while the player is in a box or playing; `snapshotFor` gives a table's latest snapshot.
function TableSign.update(
	self: any,
	position: Vector3?,
	busy: boolean,
	zones: Instance,
	snapshotFor: (number) -> any?
)
	local target: number? = nil
	if position and not busy then
		local id, distance = Placement.nearestArea(position.X, position.Z)
		local limit = if id == self.id then Sign.HideStuds else Sign.ShowStuds
		if id and distance <= limit and boxPart(zones, id) then
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
				self.gui.Adornee = boxPart(zones, target)
				self.gui.Enabled = true
				self:fill(snapshotFor(target))
				UIAnim.popIn(self.card)
			else
				self.gui.Enabled = false
			end
		end
		-- Pop the old sign out first (it may be over another table), then show the new one.
		UIAnim.popOut(self.card, arrive)
	end
	if self.id and self.card.Visible then
		self:fill(snapshotFor(self.id))
	end
end

return TableSign
