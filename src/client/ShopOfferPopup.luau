--!strict
-- ShopOfferPopup: the one join popup for limited offers (GUI lane, designer 2026-10-03, C4):
-- once a session, a little after the save loads, if any limited offer is open for this player
-- (the Starter Pack, VIP's welcome offer, a Limited cue on the shelf, the release sale), one
-- card shows them in turn, changing every Config.UI.Shop.OfferPopup.RotateSeconds, each with
-- its countdown. "See offer" opens the Shop on that offer's section; the X, B or Escape close
-- it. It waits in the Popups queue (never in a match, during the tutorial or over a menu) and
-- never stacks with another popup.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local CueThumb = require(script.Parent.CueThumb)
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local Menus = require(script.Parent.Menus)
local Popups = require(script.Parent.Popups)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local O = Config.UI.Shop.OfferPopup
local K = Config.UI.Kit
local COPY: { [string]: any } = Strings.Menus.Shop :: any
local ACTION = "8ballOfferPopupClose"
local PRIORITY = Enum.ContextActionPriority.High.Value + 30

local ShopOfferPopup = {}

type Slide = {
	icon: string,
	title: string,
	big: string?,
	line: string?,
	endsAt: number,
	section: string, -- the Shop section "See offer" opens
}

--- The open offers for this player in ShopState, in a fixed order.
function ShopOfferPopup.slides(state: any, now: number): { Slide }
	local list: { Slide } = {}
	if type(state) ~= "table" then
		return list
	end
	local offers = if type(state.offers) == "table" then state.offers else {}
	local function open(window: any): boolean
		return type(window) == "table"
			and window.open == true
			and type(window.endsAt) == "number"
			and window.endsAt > now
	end
	if open(offers.StarterPack) and state.starterBought ~= true then
		table.insert(list, {
			icon = "StarterPack",
			title = COPY.StarterPack,
			big = Format.money(Config.Shop.StarterMoney),
			line = COPY.StarterPerks:format(CueThumb.cueName(Config.Shop.StarterCue)),
			endsAt = offers.StarterPack.endsAt,
			section = "Offer",
		})
	end
	if open(offers.VipOffer) and state.vip ~= true then
		table.insert(list, {
			icon = "Vip",
			title = COPY.Vip,
			big = COPY.Off:format(50),
			line = COPY.VipPerks,
			endsAt = offers.VipOffer.endsAt,
			section = "Vip",
		})
	end
	for _, row in (if type(state.limited) == "table" then state.limited else {}) do
		if
			type(row) == "table"
			and row.open == true
			and row.owned ~= true
			and row.soldOut ~= true
		then
			table.insert(list, {
				icon = "Limited",
				title = COPY.GrandOpening:format(CueThumb.cueName(row.cue)),
				line = COPY.OnePerPlayer,
				endsAt = if type(row.endsAt) == "number" then row.endsAt else 0,
				section = "Limited",
			})
		end
	end
	local sale = if type(state.releaseSale) == "table" then state.releaseSale else {}
	if sale.open == true and type(sale.endsAt) == "number" and sale.endsAt > now then
		table.insert(list, {
			icon = "Deals",
			title = COPY.ReleaseSale,
			big = COPY.Off:format(if type(sale.percent) == "number" then sale.percent else 0),
			line = COPY.ReleaseLine:format(
				if type(sale.percent) == "number" then sale.percent else 0
			),
			endsAt = sale.endsAt,
			section = "Money",
		})
	end
	return list
end

-- Build the card and show it until closed; `done` frees the queue.
local function show(screen: ScreenGui, slides: { Slide }, done: () -> ())
	local gui = Instance.new("ScreenGui")
	gui.Name = "OfferPopup"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = screen.DisplayOrder + 12
	gui.Parent = screen.Parent
	local size = gui.AbsoluteSize
	local t = math.clamp((size.Y - 360) / (1080 - 360), 0, 1)
	local function span(pair: { number }): number
		return math.floor(pair[1] + (pair[2] - pair[1]) * t + 0.5)
	end
	local w = math.min(span(O.WidthPx), size.X - 32)
	local h = math.min(span(O.HeightPx), size.Y - 32)
	local card = HudParts.popupCard(gui, "Card")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(w, h)
	card.Visible = false
	local pad = math.floor(12 + 6 * t)
	local titleSize = math.max(K.Text.Min, span({ 22, 30 }))
	local header = HudParts.text(
		card,
		"Header",
		titleSize,
		COPY.OfferTitle,
		HudParts.color(Config.UI.Shop.Page.HeaderColor)
	)
	header.TextWrapped = false
	header.Position = UDim2.fromOffset(pad, pad)
	header.Size = UDim2.fromOffset(w - 2 * pad - 44, titleSize + 6)
	header.ZIndex = 3
	local headShake = UIAnim.shake(header, "Text")

	local closed = false
	local close: () -> ()
	local xButton = HudParts.candy(card, "", function()
		UISound.play("Click")
		close()
	end, "Red", "X")
	xButton.AnchorPoint = Vector2.new(1, 0)
	xButton.Size = UDim2.fromOffset(40, 40)
	xButton.Position = UDim2.fromOffset(w - pad, pad - 2)
	xButton.ZIndex = 4
	HudParts.setMinHit(xButton, Config.UI.Menu.Frame.TouchMinPx)

	local body = HudParts.frame(card, "Slide")
	body.Position = UDim2.fromOffset(pad, pad + titleSize + 10)
	local buttonH = math.max(44, span({ 44, 52 }))
	body.Size = UDim2.fromOffset(w - 2 * pad, h - 2 * pad - titleSize - 10 - buttonH - 8)
	body.ZIndex = 3
	local artSize = math.min(body.Size.Y.Offset, math.floor(w * 0.32))
	local art = HudParts.icon(body, "Vip", "Art")
	art.Size = UDim2.fromOffset(artSize, artSize)
	art.Position = UDim2.fromOffset(0, math.floor((body.Size.Y.Offset - artSize) / 2))
	art.ZIndex = 3
	local tx = artSize + pad
	local tw = body.Size.X.Offset - tx
	local nameSize = math.max(K.Text.Min, span({ 20, 28 }))
	local bigSize = math.max(K.Text.Min, span({ 26, 40 }))
	local lineSize = math.max(K.Text.Min, span({ 15, 18 }))
	local name = HudParts.text(body, "Name", nameSize, "")
	name.TextWrapped = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 3
	local rainbow = UIAnim.rainbow(name)
	local big = HudParts.text(body, "Big", bigSize, "", HudParts.color(K.Numbers.Money))
	big.AutoLocalize = false
	big.TextWrapped = false
	big.TextXAlignment = Enum.TextXAlignment.Left
	big.ZIndex = 3
	local line = HudParts.note(body, "Line", lineSize, "")
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.ZIndex = 3
	local timer = HudParts.text(body, "Timer", lineSize, "", HudParts.color(K.Numbers.Count))
	timer.AutoLocalize = false
	timer.TextWrapped = false
	timer.TextXAlignment = Enum.TextXAlignment.Left
	timer.ZIndex = 3
	local block = nameSize + 4 + bigSize + 2 * (lineSize + 4) + lineSize + 4
	local y = math.max(0, math.floor((body.Size.Y.Offset - block) / 2))
	name.Position, name.Size = UDim2.fromOffset(tx, y), UDim2.fromOffset(tw, nameSize + 4)
	y += nameSize + 4
	big.Position, big.Size = UDim2.fromOffset(tx, y), UDim2.fromOffset(tw, bigSize)
	y += bigSize
	line.Position, line.Size = UDim2.fromOffset(tx, y), UDim2.fromOffset(tw, 2 * (lineSize + 4))
	y += 2 * (lineSize + 4)
	timer.Position, timer.Size = UDim2.fromOffset(tx, y), UDim2.fromOffset(tw, lineSize + 4)
	local sparkle = UIAnim.sparkle(card, HudParts.color(K.Numbers.Money))

	local index = 1
	local function paint()
		local slide = slides[index]
		HudParts.setIcon(art, slide.icon)
		name.Text = slide.title
		big.Text = slide.big or ""
		big.Visible = slide.big ~= nil
		line.Text = slide.line or ""
	end
	local see = HudParts.candy(card, COPY.SeeShop, function()
		UISound.play("Click")
		local section = slides[index].section
		close()
		Menus.open("Shop", section)
	end, "Green")
	see.AnchorPoint = Vector2.new(0.5, 1)
	see.Size = UDim2.fromOffset(math.min(w - 2 * pad, 260), buttonH)
	see.Position = UDim2.new(0.5, 0, 1, -pad)
	see.ZIndex = 4
	HudParts.setButtonTextSize(see, math.max(K.Text.Min, span({ 18, 24 })))

	local nextSwap = os.clock() + O.RotateSeconds
	local ticker = RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		local slide = slides[index]
		timer.Text = COPY.OfferEnds:format(ShopParts.timeLeft(slide.endsAt - now))
		if #slides > 1 and os.clock() >= nextSwap then
			nextSwap = os.clock() + O.RotateSeconds
			index = index % #slides + 1
			paint()
			body.Visible = false
			UIAnim.popIn(body)
		end
	end)
	local escape = UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Escape then
			close()
		end
	end)
	ContextActionService:BindActionAtPriority(ACTION, function(_n, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			close()
		end
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, Enum.KeyCode.ButtonB)

	close = function()
		if closed then
			return
		end
		closed = true
		ticker:Disconnect()
		escape:Disconnect()
		ContextActionService:UnbindAction(ACTION)
		headShake.stop()
		rainbow.stop()
		sparkle.stop()
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
		UIAnim.popOut(card, function()
			gui:Destroy()
			done()
		end)
	end

	paint()
	UIAnim.popIn(card)
	UIAnim.glowBurst(card, HudParts.color(K.Numbers.Money), 0.3)
	UISound.play("Claim")
	if ShopParts.gamepad() then
		GuiService.SelectedObject = see
	end
end

--- Watch for the first ShopState after the save loads (once a session) and queue the popup
--- when an offer is open. `screen` is the HUD's ScreenGui.
function ShopOfferPopup.start(screen: ScreenGui)
	local player = Players.LocalPlayer
	if not player then
		return
	end
	local function queue(force: boolean?)
		local now = workspace:GetServerTimeNow()
		local slides = ShopOfferPopup.slides(ItemState.shop(), now)
		if #slides == 0 and force then
			slides = {
				{
					icon = "Deals",
					title = COPY.ReleaseSale,
					big = COPY.Off:format(30),
					line = COPY.ReleaseLine:format(30),
					endsAt = now + 3600,
					section = "Money",
				},
			}
		end
		if #slides > 0 then
			Popups.push({
				id = "OfferPopup",
				show = function(done)
					show(screen, slides, done)
				end,
			})
		end
	end
	GuiQA.add("offerPopup", function()
		queue(true)
		return true
	end)
	task.spawn(function()
		while player:GetAttribute("DataLoaded") ~= true do
			player:GetAttributeChangedSignal("DataLoaded"):Wait()
		end
		task.wait(O.AfterJoinSeconds)
		local tries = 0
		while type(ItemState.shop()) ~= "table" and tries < 30 do
			tries += 1
			task.wait(1)
		end
		queue()
	end)
end

return ShopOfferPopup
