--!strict
-- FreeTrack: the Free Reward menu's 28-day track (Config.Daily.Track), under "- TRACK -": a
-- pale panel with its navy pill ("DAY 5 OF 28": the days claimed in this round), a bar from
-- day 0 to TrackDays filled to the days claimed with a white knob at its end, and a node at
-- each reward's day: its pictures over it (a money prize's amount in gold over their foot),
-- "Day 8" under it, gold with a check once reached.
-- The track's rewards come with that day's login claim (the Daily section's Claim!), so nothing
-- here is pressed. Under the bar: "Every day you claim counts, even after a missed day." (the
-- total never resets, unlike the streak). Sizes in Config.UI.FreeReward.Track.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local FreeParts = require(script.Parent.FreeParts)
local HudParts = require(script.Parent.HudParts)
local RewardsParts = require(script.Parent.RewardsParts)
local ShopCards = require(script.Parent.ShopCards)
local Stage = require(script.Parent.Stage)
local UIAnim = require(script.Parent.UIAnim)

local B = Config.UI.ShopBlocks
local P = B.Panel
local T = Config.UI.FreeReward.Track
local DAYS = Config.Daily.TrackDays
local ROWS = #Config.Daily.Track
local INK = Config.UI.Kit.Colors.Ink
local W = Strings.FreeReward
local rgb, round = ShopCards.rgb, ShopCards.round

type Node = {
	day: number,
	holder: Frame, -- the node's pieces pop in together
	pictures: FreeParts.Pictures,
	amount: TextLabel, -- a money prize's amount
	dot: Frame,
	edge: UIStroke,
	check: ImageLabel,
	label: TextLabel, -- "Day 8"
	reached: boolean,
}

local FreeTrack = {}
FreeTrack.__index = FreeTrack

-- Draw a node's prize: its pictures and, for money, the amount.
local function setPrize(node: Node, reward: RewardsParts.Reward)
	FreeParts.setPictures(node.pictures, reward)
	local text = if reward.money > 0 then Format.money(reward.money) else ""
	if node.amount.Text ~= text then
		node.amount.Text = text
	end
	node.amount.Visible = reward.money > 0
end

-- A round frame in `tint` with an ink edge.
local function disc(parent: Instance, name: string, tint: Color3, z: number): (Frame, UIStroke)
	local frame = HudParts.frame(parent, name)
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = tint
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.ZIndex = z
	HudParts.corner(frame, 999)
	local edge = Instance.new("UIStroke")
	edge.Color = rgb(INK)
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = frame
	return frame, edge
end

--- Build the section (closed) into `parent` (the menu's Track group).
function FreeTrack.new(parent: Instance): any
	local self: any = setmetatable({}, FreeTrack)
	self.k = 1
	self.place = 0 -- days claimed in this round
	local root = HudParts.frame(parent, "TrackSection")
	root.ZIndex = 2
	self.root = root
	local panel = ShopCards.panel(root, "TrackPanel")
	self.panel = panel
	local card = panel.frame
	self.title = ShopCards.titlePill(root, "TrackTitle", W.TrackTitle:format(0, DAYS))
	local bar, barEdge = disc(card, "TrackBar", rgb(T.Empty), 3)
	self.bar, self.barEdge = bar, barEdge
	local fill = HudParts.frame(bar, "Fill")
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = rgb(T.Fill)
	fill.ZIndex = 4
	HudParts.corner(fill, 999)
	self.fill = fill
	local knob, knobEdge = disc(bar, "Knob", Color3.new(1, 1, 1), 6)
	self.knob, self.knobEdge = knob, knobEdge
	self.nodes = {} :: { Node }
	for index, row in Config.Daily.Track :: { any } do
		local holder = HudParts.frame(card, "TrackNode" .. index)
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.ZIndex = 5
		local dot, edge = disc(holder, "Dot", Color3.new(1, 1, 1), 6)
		local check = HudParts.icon(dot, "Check", "Check")
		check.AnchorPoint = Vector2.new(0.5, 0.5)
		check.Position = UDim2.fromScale(0.5, 0.5)
		check.Size = UDim2.fromScale(0.8, 0.8)
		check.ZIndex = 7
		check.Visible = false
		local label = ShopCards.label(holder, "Day", W.TrackDay:format(row.Day), nil, 6)
		label.AutoLocalize = false
		local pictures = FreeParts.pictures(holder, "Pictures", 6)
		local amount = ShopCards.label(holder, "Amount", "", rgb(Config.UI.Kit.Numbers.Money), 20)
		amount.AutoLocalize = false -- "$50,000"
		local node: Node = {
			day = row.Day,
			holder = holder,
			pictures = pictures,
			amount = amount,
			dot = dot,
			edge = edge,
			check = check,
			label = label,
			reached = false,
		}
		setPrize(node, RewardsParts.reward({ money = row.Money, blocks = row.Blocks }))
		table.insert(self.nodes, node)
	end
	local note = HudParts.note(card, "TrackNote", ShopCards.textPx(T.NoteUnits, 1), W.TrackNote)
	note.AnchorPoint = Vector2.new(0.5, 0.5)
	note.ZIndex = 4
	self.note = note
	return self
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

--- The section's height at the scale `k`.
function FreeTrack.heightFor(k: number): number
	return round((B.TitlePill.HeightUnits / 2 + T.Units[2]) * k)
end

-- The x of day `day` on the bar, in units.
local function xOf(day: number): number
	local Bar = T.Bar
	return Bar.Left + (Bar.Right - Bar.Left) * math.clamp(day / DAYS, 0, 1)
end

--- Lay the section out across `width` pixels at the scale `k`, its top `y` pixels down its
--- group; returns its height.
function FreeTrack.layout(self: any, width: number, k: number, y: number): number
	self.k = k
	local Wd, Hd = T.Units[1], T.Units[2]
	local top = B.TitlePill.HeightUnits / 2
	local cardW = round(Wd * k)
	local height = FreeTrack.heightFor(k)
	self.root.Position = UDim2.fromOffset(math.floor((width - cardW) / 2), y)
	self.root.Size = UDim2.fromOffset(cardW, height)
	ShopCards.put(self.panel.frame, k, Wd / 2, top + Hd / 2, Wd, Hd)
	ShopCards.sizeBox(self.panel, k, P.CornerUnits, P.EdgeUnits)
	ShopCards.layoutTitlePill(self.title, k, Wd / 2, top)
	local Bar = T.Bar
	local edge = ShopCards.strokePx(k)
	ShopCards.put(
		self.bar,
		k,
		(Bar.Left + Bar.Right) / 2,
		Bar.Y,
		Bar.Right - Bar.Left,
		Bar.HeightUnits
	)
	self.barEdge.Thickness = edge
	self.knobEdge.Thickness = edge
	-- Each node: its holder spans from the pictures' top to the day's foot, centred on its x.
	local S = T.Pictures
	local holderTop = S[1] - S[2] / 2
	local holderBottom = T.DayY + T.DayUnits / 2 + 4
	local holderH = holderBottom - holderTop
	for _, node in self.nodes :: { Node } do
		local x = xOf(node.day)
		ShopCards.put(node.holder, k, x, holderTop + holderH / 2, S[3], holderH)
		FreeParts.layoutPictures(node.pictures, k, S[3] / 2, S[1] - holderTop, S[2], S[3])
		local amountPx = ShopCards.textPx(T.AmountUnits, k)
		ShopCards.line(node.amount, k, S[3] / 2, T.AmountY - holderTop, S[3], amountPx)
		ShopCards.put(node.dot, k, S[3] / 2, Bar.Y - holderTop, T.NodeUnits, T.NodeUnits)
		ShopCards.line(
			node.label,
			k,
			S[3] / 2,
			T.DayY - holderTop,
			S[3],
			ShopCards.textPx(T.DayUnits, k)
		)
		node.edge.Thickness = edge
	end
	ShopCards.line(self.note, k, Wd / 2, T.NoteY, Wd - 80, ShopCards.textPx(T.NoteUnits, k))
	self:layoutFill()
	return height
end

-- The fill and its knob, to the days claimed.
function FreeTrack.layoutFill(self: any)
	local k = self.k
	local Bar = T.Bar
	local share = math.clamp(self.place / DAYS, 0, 1)
	local barW = round((Bar.Right - Bar.Left) * k)
	local barH = round(Bar.HeightUnits * k)
	self.fill.Size = UDim2.fromOffset(math.max(barH, round(barW * share)), barH)
	self.fill.Visible = self.place > 0
	local knob = round(T.KnobUnits * k)
	self.knob.Position = UDim2.fromOffset(round(barW * share), round(barH / 2))
	self.knob.Size = UDim2.fromOffset(knob, knob)
end

--------------------------------------------------------------------------------------------
-- What the server says
--------------------------------------------------------------------------------------------

--- Draw a RewardState (nil before the first: an empty track).
function FreeTrack.refresh(self: any, state: any)
	if type(state) ~= "table" then
		return
	end
	self.place = RewardsParts.whole(state.trackPlace)
	local days = RewardsParts.whole(state.trackDays)
	local word = W.TrackTitle:format(self.place, if days > 0 then days else DAYS)
	if self.title.word.Text ~= word then
		self.title.word.Text = word
		ShopCards.layoutTitlePill(self.title, self.k, T.Units[1] / 2, B.TitlePill.HeightUnits / 2)
	end
	local rows = if type(state.track) == "table" then state.track else {}
	for index, node in self.nodes :: { Node } do
		local view = rows[index]
		local reached = type(view) == "table" and view.reached == true
		node.reached = reached
		node.dot.BackgroundColor3 = if reached then rgb(T.NodeReached) else Color3.new(1, 1, 1)
		node.check.Visible = reached
		if type(view) == "table" then
			setPrize(node, RewardsParts.reward(view.reward))
			local S = T.Pictures
			FreeParts.layoutPictures(node.pictures, self.k, S[3] / 2, S[2] / 2, S[2], S[3])
		end
	end
	self:layoutFill()
end

--------------------------------------------------------------------------------------------
-- Stage
--------------------------------------------------------------------------------------------

--- Register every piece with the menu's `stage` (ids in Config.UI.FreeReward.Open).
function FreeTrack.register(self: any, stage: Stage.Stage, _keep: (UIAnim.Handle) -> ())
	stage:add("TrackPanel", self.panel.frame)
	stage:add("TrackTitle", self.title.pill)
	stage:add("TrackBar", self.bar)
	for index, node in self.nodes :: { Node } do
		if index <= ROWS then
			stage:add("TrackNode" .. index, node.holder)
		end
	end
	stage:add("TrackNote", self.note)
end

return FreeTrack
