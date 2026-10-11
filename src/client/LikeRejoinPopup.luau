--!strict
-- LikeRejoinPopup: the Like + Favorite card's "ALMOST THERE!" popup (the designer's pick "A" on
-- the concept page, 2026-10-11). The first Verify that finds the game favorited is answered
-- "Rejoin" by the server (Config.Social.LikeRejoin), and the Free Reward menu shows this over
-- its panel: the gold title and a line, three step cards in a row (leave the game, press the
-- thumbs up on the game's page, rejoin and press Verify; the like step lit gold, its thumbs up
-- rocking) with arrows between them, the reward in a white pill under them (its words, each
-- block's picture, the money), then Later (blue) and Leave & Like (green, shining). No X: Later
-- closes it. Leave & Like answers true (the menu sends the player out with the steps).
--
-- It slams in (the house popup entrance) with no burst, its cards popping in one by one after.
-- Laid out in its own units (Config.UI.FreeReward.LikePopup) scaled by one factor to fit the
-- panel. A clear layer under it takes every press, so the menu waits; the tutorial's rings on
-- the menu's frames wait too (TutorialAnchors.setCovered). Gamepad: it lands on
-- Later; B and Escape answer Later. Words in Strings.FreeReward.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local FreeParts = require(script.Parent.FreeParts)
local HudParts = require(script.Parent.HudParts)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local ShopCards = require(script.Parent.ShopCards)
local TutorialAnchors = require(script.Parent.TutorialAnchors)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local L = Config.UI.FreeReward.LikePopup
local K = Config.UI.Kit
local B = Config.UI.ShopBlocks
local ICONS: { [string]: string } = K.Icons :: any
local W = Strings.FreeReward
local rgb, round = ShopCards.rgb, ShopCards.round
local PRIORITY = Enum.ContextActionPriority.High.Value + 40 -- over the menu and its dialogs

export type Dialog = {
	cancel: () -> (), -- close it as if Later was pressed (nothing happens once closed)
	isOpen: () -> boolean,
}

-- A reward as RewardView.reward sends it: { money, blocks = { { kind, count } } }.
export type Reward = { money: number, blocks: { { kind: string, count: number } } }

local LikeRejoinPopup = {}

local count = 0

local function isGamepad(kind: Enum.UserInputType): boolean
	return kind.Name:sub(1, 7) == "Gamepad"
end

-- A step card: its box, number badge, picture and caption.
type Step = {
	box: ShopCards.Box,
	badge: Frame,
	badgeEdge: UIStroke,
	number: TextLabel,
	icon: ImageLabel,
	caption: TextLabel,
}

local function step(parent: Instance, index: number, hot: boolean): Step
	local box = if hot
		then ShopCards.box(parent, "Step" .. index, rgb(L.StepHot.Fill), rgb(L.StepHot.Edge), 3)
		else ShopCards.inner(parent, "Step" .. index, 3)
	local badge = HudParts.frame(box.frame, "Badge")
	badge.BackgroundTransparency = 0
	badge.BackgroundColor3 = rgb(if hot then L.Badge.Gold else L.Badge.Blue)
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.ZIndex = 5
	HudParts.corner(badge, 999)
	local badgeEdge = Instance.new("UIStroke")
	badgeEdge.Color = rgb(K.Colors.Ink)
	badgeEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	badgeEdge.Parent = badge
	local number = ShopCards.label(badge, "Number", tostring(index), nil, 6)
	number.Position = UDim2.fromScale(0.5, 0.5)
	number.Size = UDim2.fromScale(0.9, 0.9)
	local key = if index == 1 then "Door" elseif index == 2 then "ThumbsUp" else "Check"
	local icon = ShopCards.image(box.frame, "Icon", ICONS[key] or "", 5)
	local caption = ShopCards.note(box.frame, "Caption", W.RejoinSteps[index] or "", 5)
	caption.TextWrapped = true
	return {
		box = box,
		badge = badge,
		badgeEdge = badgeEdge,
		number = number,
		icon = icon,
		caption = caption,
	}
end

--- Show the popup over `parent` (the menu's panel) for `reward` (the favorite card's, may be
--- nil: then no reward pill). `callback(leave)` runs once: true for Leave & Like.
function LikeRejoinPopup.show(parent: GuiObject, reward: Reward?, callback: (boolean) -> ()): Dialog
	count += 1
	local action = "8ballLikeRejoin" .. count
	local open = true
	local previous = GuiService.SelectedObject
	local loops: { UIAnim.Handle } = {}

	-- The clear layer that takes every press while it is up.
	local layer = Instance.new("TextButton")
	layer.Name = "LikeRejoin"
	layer.Text = ""
	layer.AutoButtonColor = false
	layer.Selectable = false
	layer.BorderSizePixel = 0
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = L.ZIndex
	layer.Parent = parent
	TutorialAnchors.setCovered(action, true) -- the tutorial's rings wait while it is up
	local card = HudParts.card(layer, "Card")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.ZIndex = L.ZIndex + 1
	card.SelectionGroup = true
	card.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorRight = Enum.SelectionBehavior.Stop

	local title = ShopCards.label(card, "Title", W.RejoinTitle, rgb(K.Numbers.Money), 6)
	local sub = ShopCards.note(card, "Sub", W.RejoinSub, 6)
	local steps: { Step } = {}
	for index = 1, 3 do
		steps[index] = step(card, index, index == 2)
	end
	local arrows: { ImageLabel } = {}
	for index = 1, 2 do
		arrows[index] = ShopCards.image(card, "Arrow" .. index, ICONS.Arrow or "", 5)
	end

	-- The reward pill: its words, each block's picture, the money.
	local pill: Frame? = nil
	local pillEdge: UIStroke? = nil
	local pillWords: TextLabel? = nil
	local pictures: { ImageLabel } = {}
	local cash: ImageLabel? = nil
	local money: TextLabel? = nil
	if reward then
		local made = HudParts.frame(card, "Reward")
		made.BackgroundTransparency = 0
		made.BackgroundColor3 = Color3.new(1, 1, 1)
		made.AnchorPoint = Vector2.new(0.5, 0.5)
		made.ZIndex = 4
		HudParts.corner(made, 999)
		local edge = Instance.new("UIStroke")
		edge.Color = rgb(K.Colors.Ink)
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Parent = made
		pill, pillEdge = made, edge
		pillWords = ShopCards.note(made, "Words", W.RejoinReward, 5)
		for _, entry in reward.blocks do
			for _ = 1, math.max(1, entry.count) do
				local picture = ShopCards.image(
					made,
					"Block" .. entry.kind,
					FreeParts.blockImage(entry.kind),
					5
				)
				table.insert(pictures, picture)
			end
		end
		if reward.money > 0 then
			cash = ShopCards.image(made, "Cash", ICONS.CashStack or "", 5)
			money =
				ShopCards.label(made, "Money", Format.money(reward.money), rgb(K.Numbers.Money), 5)
		end
	end

	local finish: (boolean) -> ()
	local later = HudParts.candy(card, W.RejoinLater, function()
		UISound.play("Click")
		finish(false)
	end, "Blue")
	later.Name = "Later"
	later.AnchorPoint = Vector2.new(0.5, 0.5)
	later.ZIndex = 6
	local leave = HudParts.candy(card, W.RejoinLeave, function()
		UISound.play("Click")
		finish(true)
	end, "Green", "Door")
	leave.Name = "Leave"
	leave.AnchorPoint = Vector2.new(0.5, 0.5)
	leave.ZIndex = 6
	later.NextSelectionRight = leave
	leave.NextSelectionLeft = later

	-- Layout: the card's units scaled by one factor to fit the panel.
	local room = parent.AbsoluteSize / MenuFrame.scaleOf(parent) -- the panel may be scaled
	local fit = math.min(
		(room.X - 2 * L.MarginPx) / L.Units[1],
		(room.Y - 2 * L.MarginPx) / L.Units[2],
		L.MaxScale
	)
	local k = math.max(0.2, fit)
	card.Size = UDim2.fromOffset(round(L.Units[1] * k), round(L.Units[2] * k))
	local fill = card:FindFirstChild("Fill")
	local corner = if fill then fill:FindFirstChildOfClass("UICorner") else nil
	if corner then
		corner.CornerRadius = UDim.new(0, round(L.CornerUnits * k))
	end
	local cx = L.Units[1] / 2
	ShopCards.line(title, k, cx, L.TitleY, L.Units[1] - 80, ShopCards.textPx(L.TitleUnits, k))
	ShopCards.line(sub, k, cx, L.SubY, L.Units[1] - 80, ShopCards.textPx(L.SubUnits, k))
	local S = L.Step
	local captionPx = ShopCards.textPx(L.CaptionUnits, k)
	for index, s in steps do
		local x = S.Xs[index]
		ShopCards.put(s.box.frame, k, x, S.Top + S.H / 2, S.W, S.H)
		ShopCards.sizeBox(s.box, k, L.StepCornerUnits, L.StepEdgeUnits)
		local bu = L.Badge.Units
		ShopCards.put(s.badge, k, S.W / 2, 0, bu, bu)
		s.badgeEdge.Thickness = ShopCards.strokePx(k)
		HudParts.setTextSize(s.number, ShopCards.textPx(L.Badge.TextUnits, k))
		ShopCards.put(s.icon, k, S.W / 2, L.IconY, L.IconUnits, L.IconUnits)
		ShopCards.putPx(s.caption, S.W / 2 * k, L.CaptionY * k, (S.W - 24) * k, 3 * captionPx + 8)
		HudParts.setTextSize(s.caption, captionPx)
	end
	for index, arrow in arrows do
		local x = (S.Xs[index] + S.W / 2 + S.Xs[index + 1] - S.W / 2) / 2
		ShopCards.put(arrow, k, x, S.Top + S.H / 2, L.ArrowUnits, L.ArrowUnits)
	end
	if pill and pillEdge and pillWords then
		local R = L.Reward
		local textPx = ShopCards.textPx(R.TextUnits, k)
		local gap = R.GapUnits * k
		local img = R.ImageUnits * k
		local wordsW = ShopCards.measure(pillWords.Text, textPx)
		local moneyW = if money then ShopCards.measure(money.Text, textPx) else 0
		local width = R.PadUnits * k * 2 + wordsW
		width += #pictures * (img + gap)
		if money then
			width += (img * 0.8 + gap) + moneyW + gap
		end
		local h = math.max(round(R.H * k), textPx + 2 * B.PillPadPx)
		ShopCards.putPx(pill, cx * k, R.Y * k, width, h)
		pillEdge.Thickness = ShopCards.strokePx(k)
		local x = R.PadUnits * k
		ShopCards.putPx(pillWords, x + wordsW / 2, h / 2, wordsW, textPx + B.TextBoxPx)
		HudParts.setTextSize(pillWords, textPx)
		x += wordsW + gap
		for _, picture in pictures do
			ShopCards.putPx(picture, x + img / 2, h / 2, img, img)
			x += img + gap
		end
		if cash and money then
			ShopCards.putPx(cash, x + img * 0.4, h / 2, img * 0.8, img * 0.8)
			x += img * 0.8 + gap
			ShopCards.putPx(money, x + moneyW / 2, h / 2, moneyW, textPx + B.TextBoxPx)
			HudParts.setTextSize(money, textPx)
		end
	end
	local Bt = L.Buttons
	local buttonH = ShopCards.buttonPx(Bt.H, k)
	local both = Bt.LaterW + Bt.GapUnits + Bt.LeaveW
	local left = cx - both / 2
	later.Position = UDim2.fromOffset(round((left + Bt.LaterW / 2) * k), round(Bt.Y * k))
	later.Size = UDim2.fromOffset(round(Bt.LaterW * k), buttonH)
	leave.Position = UDim2.fromOffset(
		round((left + Bt.LaterW + Bt.GapUnits + Bt.LeaveW / 2) * k),
		round(Bt.Y * k)
	)
	leave.Size = UDim2.fromOffset(round(Bt.LeaveW * k), buttonH)
	for _, button in { later, leave } do
		HudParts.setButtonTextSize(button, ShopCards.textPx(Bt.TextUnits, k))
		HudParts.setMinHit(button, Config.UI.Menu.Frame.TouchMinPx)
	end

	-- The open: the card slams in, then its step cards pop in one by one; the thumbs up rocks
	-- and Leave & Like shines while it is up.
	UIAnim.slam(card, nil, { burst = false, shake = "Nudge" })
	for index, s in steps do
		s.box.frame.Visible = false
		task.delay(L.StepStaggerSeconds * index, function()
			if open then
				UIAnim.popIn(s.box.frame)
			end
		end)
	end
	local R = L.ThumbRock
	table.insert(loops, UIAnim.turn(steps[2].icon, 0, R[1], R[2]))
	table.insert(loops, ShopCards.buttonShine(leave, B.ButtonShineEvery, 0))

	local escape: RBXScriptConnection? = nil
	finish = function(answer: boolean)
		if not open then
			return
		end
		open = false
		TutorialAnchors.setCovered(action, false)
		ContextActionService:UnbindAction(action)
		if escape then
			escape:Disconnect()
		end
		for _, handle in loops do
			handle.stop()
		end
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(layer) then
			GuiService.SelectedObject = if previous and previous:IsDescendantOf(game)
				then previous
				else nil
		end
		layer.Active = false
		UIAnim.popOut(card, function()
			layer:Destroy()
		end)
		callback(answer)
	end
	-- B answers Later before the menu hears it.
	ContextActionService:BindActionAtPriority(
		action,
		function(_name: string, state: Enum.UserInputState, _input: InputObject)
			if state == Enum.UserInputState.Begin then
				finish(false)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		PRIORITY,
		Enum.KeyCode.ButtonB
	)
	escape = UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Escape then
			Menus.swallowEscape(input) -- the menu under it stays open
			finish(false)
		end
	end)
	if isGamepad(UserInputService:GetLastInputType()) then
		GuiService.SelectedObject = later
	end
	return {
		cancel = function()
			finish(false)
		end,
		isOpen = function(): boolean
			return open
		end,
	}
end

return LikeRejoinPopup
