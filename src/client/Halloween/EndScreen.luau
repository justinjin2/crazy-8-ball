--!strict
-- EndScreen: the Halloween event's end (hw-core; R1.4, the M5 mock). Once per save, after the
-- server turned the save's Candy into money (Converted, ConvertedMoney: CandyService on load or
-- the tick, in any server), the first time the lobby is quiet (Progression.quiet, the tutorial's
-- invite card closed): a popup over a dim, a purple ribbon "THE HALLOWEEN EVENT HAS ENDED!"
-- between two pumpkins; the candy pile, a fat orange arrow and a cash stack; "1,240 CANDY" and
-- "$12,400" counting up on their pills; "Your leftover candy was turned into money. Thanks for
-- playing!"; the event cues the player owns as cards marked YOURS FOREVER (up to MaxCues); a
-- big green COLLECT, which flies the cash into the money HUD (the money is already saved) and
-- closes it. Shown means seen: { endSeen = true } goes to the server as it opens, so it never
-- shows again (a save with no Candy is marked seen by the server and never shows it). Gamepad:
-- COLLECT is selected; B or Esc collect too.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local Ledger = require(Shared:WaitForChild("Halloween"):WaitForChild("Ledger"))
local CueThumb = require(script.Parent.Parent.CueThumb)
local GuiQA = require(script.Parent.Parent.GuiQA)
local HudParts = require(script.Parent.Parent.HudParts)
local PadMode = require(script.Parent.Parent.PadMode)
local UIAnim = require(script.Parent.Parent.UIAnim)
local State = require(script.Parent.State)

local H = Config.Halloween
local E = Config.UI.Halloween.End
local A = Config.UI.Halloween.Art
local K = Config.UI.Kit
local W = Strings.Halloween
local SHORT = Config.Multiplayer.Style.ShortHeight

local CLOSE_ACTION = "HalloweenEndScreen"

local EndScreen = {}

-- The event cues, each once: the cue shop's in its order (Config.Halloween.Cues), then the
-- King's drop unless the shop sells it too (Halloween/Ledger.eventCues: the Jack-o'-Lantern is
-- both since 2026-10-29, and was shown twice).
local EVENT_CUES: { string } = Ledger.eventCues()

local function progression(): any?
	local ok, P = pcall(require, script.Parent.Parent.Progression)
	return if ok and type(P) == "table" then P else nil
end

-- The lobby quiet and the tutorial's invite card closed (as CandyToast's cards wait).
local function free(): boolean
	local P = progression()
	if P == nil or P.quiet() ~= true then
		return false
	end
	local player = Players.LocalPlayer
	local gui = player and player:FindFirstChild("PlayerGui")
	local soft = gui and gui:FindFirstChild("TutorialSoftGui")
	local popup = soft and soft:FindFirstChild("InvitePopup")
	return not (popup ~= nil and popup:IsA("GuiObject") and popup.Visible)
end

local function picture(parent: Instance, name: string, image: string): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.ScaleType = Enum.ScaleType.Fit
	label.Image = image
	label.Parent = parent
	return label
end

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local open = false
local showing: ScreenGui? = nil -- the end screen while it is up and not closing
local failed = false -- its build failed this session: not tried again (warned once)

--- Whether the end screen is up (Progression.quiet: the other popups wait for it).
function EndScreen.busy(): boolean
	local gui = showing
	return gui ~= nil and gui.Parent ~= nil
end

--- Shows the end screen for `candy` Candy that became `money`, with the owned cues `owned`
--- ({ [cueId] = true }). `onShown` runs as it opens (the server's endSeen).
function EndScreen.show(
	parentGui: Instance,
	candy: number,
	money: number,
	owned: { [string]: boolean },
	onShown: (() -> ())?
)
	local holder: { screen: ScreenGui? } = {}
	local ok, err = pcall(function(): any
		EndScreen.build(parentGui, candy, money, owned, onShown, holder)
		return nil
	end)
	if not ok then
		-- Half built: its dim must not stay over the game, nor busy() hold the lobby's popups.
		local screen = holder.screen
		if screen then
			screen:Destroy()
		end
		showing = nil
		open = false
		failed = true
		warn("[8ball] Halloween end screen: " .. tostring(err))
	end
end

function EndScreen.build(
	parentGui: Instance,
	candy: number,
	money: number,
	owned: { [string]: boolean },
	onShown: (() -> ())?,
	holder: { screen: ScreenGui? }
)
	if open then
		return
	end
	open = true
	local screen = Instance.new("ScreenGui")
	screen.Name = "HalloweenEnd"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = E.DisplayOrder
	screen.Parent = parentGui
	holder.screen = screen
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Selectable = false
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = E.DimTransparency
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 10
	dim.Parent = screen
	local size = screen.AbsoluteSize
	local short = size.Y < SHORT
	local w = if short then E.ShortWidthPx else E.WidthPx
	local function px(share: number): number
		return math.floor(w * share)
	end

	-- The cues the player owns (the shop's order, then the King's drop), up to MaxCues.
	local cues: { string } = {}
	for _, id in EVENT_CUES do
		if owned[id] == true and #cues < E.MaxCues then
			table.insert(cues, id)
		end
	end

	local pad = px(0.04)
	local ribbonH = px(0.11)
	local artPx = px(0.22)
	local pillH = px(0.075)
	local notePx = px(0.032)
	local cardW, cardH = px(0.19), px(0.22)
	local collectH = px(0.1)
	local y = ribbonH / 2 + pad
	local rowTop = y
	y += artPx + pillH * 0.6 + pad * 0.6
	local noteTop = y
	y += notePx + pad
	local cardsTop = y
	if #cues > 0 then
		y += cardH + pad
	end
	local collectTop = y
	y += collectH + pad
	local h = y

	local card = HudParts.popupCard(dim, "Card")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.52)
	card.Size = UDim2.fromOffset(w, h)
	card.ZIndex = 11
	local fit = Instance.new("UIScale")
	fit.Scale =
		math.min(1, (size.X - 24) / (w + 2 * px(0.06)), size.Y * E.HeightShare / (h + ribbonH))
	fit.Parent = card

	-- The ribbon over the top edge, a pumpkin at each end.
	local ribbon = HudParts.pill(card, "Ribbon", rgb(E.RibbonTint))
	ribbon.AnchorPoint = Vector2.new(0.5, 0.5)
	ribbon.Position = UDim2.fromScale(0.5, 0)
	ribbon.Size = UDim2.fromOffset(px(0.96), ribbonH)
	ribbon.ZIndex = 14
	local title = HudParts.text(ribbon, "Title", px(0.05), W.Ended, HudParts.tone("Gold"))
	title.TextWrapped = false
	title.Size = UDim2.new(1, -2 * ribbonH, 0.8, 0)
	title.Position = UDim2.new(0, ribbonH, 0.1, 0)
	HudParts.setTextSize(title, px(0.05), 10) -- shrinks to fit between the pumpkins
	title.ZIndex = 15
	local pumpkin = if A.Header ~= "" then A.Header else H.CandyIcon
	for i, side in { 0, 1 } do
		local p = picture(ribbon, "Pumpkin" .. i, pumpkin)
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Position = UDim2.fromScale(side, 0.5)
		p.Size = UDim2.fromOffset(math.floor(ribbonH * 1.3), math.floor(ribbonH * 1.3))
		p.ZIndex = 16
	end

	-- Candy pile -> arrow -> cash, each with its pill.
	local leftX, rightX = w * 0.27, w * 0.73
	local pile = picture(card, "Pile", if A.CandyPile ~= "" then A.CandyPile else H.CandyIcon)
	pile.AnchorPoint = Vector2.new(0.5, 0)
	pile.Position = UDim2.fromOffset(leftX, rowTop)
	pile.Size = UDim2.fromOffset(artPx, artPx)
	pile.ZIndex = 12
	local cash = picture(card, "Cash", if A.CashStack ~= "" then A.CashStack else K.Icons.CashStack)
	cash.AnchorPoint = Vector2.new(0.5, 0)
	cash.Position = UDim2.fromOffset(rightX, rowTop)
	cash.Size = UDim2.fromOffset(artPx, artPx)
	cash.ZIndex = 12
	local arrow = picture(card, "Arrow", K.Icons.ArrowWhite)
	arrow.ImageColor3 = rgb(E.ArrowTint)
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.fromOffset(w / 2, rowTop + artPx / 2)
	arrow.Size = UDim2.fromOffset(px(0.12), px(0.12))
	arrow.ZIndex = 12
	local function pill(x: number, tint: Color3, name: string): TextLabel
		local frame = HudParts.pill(card, name, tint)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromOffset(x, rowTop + artPx)
		frame.Size = UDim2.fromOffset(px(0.34), pillH)
		frame.ZIndex = 13
		local text = HudParts.text(frame, "Words", math.floor(pillH * 0.62), "")
		text.TextWrapped = false
		text.AutoLocalize = false
		text.Size = UDim2.fromScale(1, 1)
		text.ZIndex = 14
		return text
	end
	local candyText = pill(leftX, rgb(E.CandyTint), "CandyPill")
	local moneyText = pill(rightX, HudParts.tone("Green"), "MoneyPill")
	local note = HudParts.note(card, "Note", notePx, W.EndNote)
	note.Position = UDim2.fromOffset(pad, noteTop)
	note.Size = UDim2.fromOffset(w - 2 * pad, notePx + 6)
	note.ZIndex = 12

	-- The cues: cards in a row, centred.
	local gap = px(0.025)
	local rowW = #cues * cardW + math.max(0, #cues - 1) * gap
	for i, id in cues do
		local c = HudParts.card(card, "Cue" .. i, px(0.02))
		c.BackgroundColor3 = CueThumb.accentColor(CueThumb.rarityOf(id))
		c.Position = UDim2.fromOffset((w - rowW) / 2 + (i - 1) * (cardW + gap), cardsTop)
		c.Size = UDim2.fromOffset(cardW, cardH)
		c.ZIndex = 12
		local thumb = CueThumb.new(c, id)
		thumb.Position = UDim2.fromScale(0.08, 0.04)
		thumb.Size = UDim2.fromScale(0.84, 0.56)
		thumb.ZIndex = 13
		local name = HudParts.text(c, "Name", px(0.026), CueThumb.cueName(id))
		name.Position = UDim2.fromScale(0.04, 0.6)
		name.Size = UDim2.fromScale(0.92, 0.16)
		name.ZIndex = 14
		local tag = HudParts.pill(c, "Yours", HudParts.tone("Purple"))
		tag.Position = UDim2.fromScale(0.06, 0.78)
		tag.Size = UDim2.fromScale(0.88, 0.16)
		tag.ZIndex = 14
		local tagText = HudParts.text(tag, "Words", px(0.022), W.YoursForever)
		tagText.Size = UDim2.fromScale(1, 1)
		tagText.ZIndex = 15
		local check = HudParts.icon(c, "Check", "Check")
		check.AnchorPoint = Vector2.new(0.5, 0.5)
		check.Position = UDim2.fromScale(0.92, 0.06)
		check.Size = UDim2.fromOffset(px(0.05), px(0.05))
		check.ZIndex = 16
	end

	local closed = false
	local collect: TextButton
	local function close()
		if closed then
			return
		end
		closed = true
		showing = nil
		ContextActionService:UnbindAction(CLOSE_ACTION)
		local P = progression()
		if P and money > 0 then
			P.flyMoney(money, collect.AbsolutePosition + collect.AbsoluteSize / 2)
		end
		if
			GuiService.SelectedObject ~= nil and GuiService.SelectedObject:IsDescendantOf(screen)
		then
			GuiService.SelectedObject = nil
		end
		UIAnim.popOut(card, function()
			screen:Destroy()
			open = false
		end)
	end
	collect = HudParts.candy(card, W.Collect, close, "Green", nil)
	collect.Name = "Collect"
	collect.AnchorPoint = Vector2.new(0.5, 0)
	collect.Position = UDim2.fromOffset(w / 2, collectTop)
	collect.Size = UDim2.fromOffset(px(0.42), collectH)
	collect.ZIndex = 14
	HudParts.setButtonTextSize(collect, math.floor(collectH * 0.55))

	UIAnim.popIn(card)
	UIAnim.slam(title, HudParts.tone("Gold"), { burst = true })
	UIAnim.countUp(0, candy, function(n: number)
		candyText.Text = W.EndCandy:format(Format.commas(n))
	end, E.CountUpSeconds)
	UIAnim.countUp(0, money, function(n: number)
		moneyText.Text = Format.money(n)
	end, E.CountUpSeconds)
	if PadMode.active() then
		GuiService.SelectedObject = collect
	end
	ContextActionService:BindActionAtPriority(
		CLOSE_ACTION,
		function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
			if state == Enum.UserInputState.Begin then
				close()
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.Escape
	)
	showing = screen
	if onShown then
		onShown()
	end
end

--- Built once by Progression: watches the event's view and shows the end once, when free.
function EndScreen.start(screen: ScreenGui)
	local parentGui = screen.Parent :: Instance
	local waiting = false
	local function due(): boolean
		local view = State.view()
		return State.on()
			and type(view) == "table"
			and view.converted == true
			and view.endSeen ~= true
			and (view.convertedMoney or 0) > 0
	end
	local function check()
		if waiting or open or failed or not due() then
			return
		end
		waiting = true
		task.spawn(function()
			while due() and not free() do
				task.wait(0.5)
			end
			waiting = false
			if not due() or open then
				return
			end
			local view = State.view() :: any
			local money = view.convertedMoney or 0
			local candy = money // H.Convert.MoneyPerCandy
			EndScreen.show(parentGui, candy, money, view.owned or {}, function()
				State.send({ endSeen = true })
			end)
		end)
	end
	State.Changed:Connect(check)
	check()
	-- Studio QA: GuiQA:Invoke("hwEnd", candy, { cueIds }) previews it (nothing is sent).
	GuiQA.add("hwEnd", function(candy: number?, cueIds: { string }?): boolean
		local owned = {}
		local ids: { string } = cueIds or {}
		for _, id in ids do
			owned[id] = true
		end
		local n = candy or 1240
		EndScreen.show(parentGui, n, n * H.Convert.MoneyPerCandy, owned, nil)
		return true
	end)
end

return EndScreen
