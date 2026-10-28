--!strict
-- CandyToast: the Halloween event's moments on screen (hw-core). The server's CandyService sends
-- them on the Halloween remote (Halloween/State's Moment):
--   { toast = { candy, source, x2 } }: a Candy chip "+57" (with a purple "2x" tag in a Candy
--     Rush or on Oct 31) pops in and flies to the HALLOWEEN tile, which bounces; while the event
--     menu is open it flies to the menu's Candy pill instead, out of the CLAIM just pressed.
--     With nowhere to fly (no tile, as in an arena) it stays a moment and fades. A match's chip
--     waits until the player is free again (its result screen closed, back in the lobby);
--     quests, the King and packs show at once. The server never sends "+0".
--   { step = index }: a track prize. Spins and money fly to their HUD targets (Progression's
--     RewardsFlyer: the Ults button, the money HUD); a cue gets a small NEW CUE! card (its
--     thumbnail, name, tier tag, OK) once the player is free (no match, result, menu, popup or
--     lucky-block reel). A step reached in a match waits with that match's chip.
--   { spider = true }: the Spider Cue's NEW CUE! card the same way.
-- Nothing shows before HwOn (the tutorial not over). Purely visual: the server already saved it.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local CueThumb = require(script.Parent.Parent.CueThumb)
local HudParts = require(script.Parent.Parent.HudParts)
local PadMode = require(script.Parent.Parent.PadMode)
local UIAnim = require(script.Parent.Parent.UIAnim)
local GuiQA = require(script.Parent.Parent.GuiQA)
local EventMenu = require(script.Parent.EventMenu)
local State = require(script.Parent.State)

local H = Config.Halloween
local T = Config.UI.Halloween.Toast
local K = Config.UI.Kit
local W = Strings.Halloween
local DIM = Config.UI.Progress.Roadmap -- a menu's ScreenGui sits DisplayOrderAbove the HUD's
local SHORT = Config.Multiplayer.Style.ShortHeight

local CLOSE_ACTION = "HalloweenCueCard"

local CandyToast = {}
CandyToast.__index = CandyToast

type Gate = "now" | "free" | "card"
type Item = { gate: Gate, run: () -> (), at: number }

-- Progression, read late (it builds this module): whether the lobby is quiet, and its flyer.
local function progression(): any?
	local ok, P = pcall(require, script.Parent.Parent.Progression)
	return if ok and type(P) == "table" then P else nil
end

-- The tutorial's soft popups (the invite card) wait for a quiet lobby too: a card waits for them.
local function softPopupUp(): boolean
	local player = Players.LocalPlayer
	local gui = player and player:FindFirstChild("PlayerGui")
	local soft = gui and gui:FindFirstChild("TutorialSoftGui")
	local popup = soft and soft:FindFirstChild("InvitePopup")
	return popup ~= nil and popup:IsA("GuiObject") and popup.Visible
end

local function free(): boolean
	local P = progression()
	return P ~= nil and P.quiet() == true and not softPopupUp()
end

-- When the NEW CUE! card up now was shown (os.clock), nil when none is.
local cardShownAt: number? = nil

--- Whether a NEW CUE! card is up (Progression.quiet: the other popups wait for it). Never
--- longer than its auto-close, so a card that failed to close cannot hold the lobby's popups.
function CandyToast.busy(): boolean
	local at = cardShownAt
	return at ~= nil and os.clock() - at < T.AutoCloseSeconds + 1
end

local function font(): Enum.Font
	return (Enum.Font :: any)[K.Font]
end

--- Built once by Progression with the HUD's screen and its shared deps (deps.corners: the
--- HubCorners whose eventTile is the chip's target).
function CandyToast.new(screen: ScreenGui, deps: any): any
	local self: any = setmetatable({}, CandyToast)
	self.deps = deps
	self.queue = {} :: { Item }
	self.pumping = false
	self.card = nil :: Frame?
	self.matchUntil = 0 -- steps arriving with a match's chip wait with it
	local gui = Instance.new("ScreenGui")
	gui.Name = "HalloweenToast"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = screen.DisplayOrder
		+ DIM.DisplayOrderAbove
		+ Config.UI.Rewards.Fly.DisplayOrderAbove
	gui.Parent = screen.Parent
	self.gui = gui
	local layer = HudParts.frame(gui, "Layer")
	layer.Size = UDim2.fromScale(1, 1)
	self.layer = layer
	State.Moment:Connect(function(msg: any)
		local ok, err = pcall(function(): any
			self:moment(msg)
			return nil
		end)
		if not ok then
			warn("[8ball] CandyToast: " .. tostring(err))
		end
	end)
	-- Studio QA: GuiQA:Invoke("hwToast", msg) shows a moment as the server would send it.
	GuiQA.add("hwToast", function(msg: any): boolean
		self:moment(msg)
		return true
	end)
	return self
end

function CandyToast.moment(self: any, msg: any)
	if not State.on() then
		return
	end
	if type(msg.toast) == "table" then
		local candy = msg.toast.candy
		if type(candy) ~= "number" or candy < 1 then
			return
		end
		local x2 = msg.toast.x2 == true
		if msg.toast.source == "Match" then
			self.matchUntil = os.clock() + 1
			self:push("free", function()
				self:chip(candy, x2, nil)
			end)
		else
			local from = self:claimFrom(msg.toast.source)
			self:push("now", function()
				self:chip(candy, x2, from)
			end)
		end
	elseif type(msg.step) == "number" then
		local step = H.Track.Steps[msg.step]
		if step == nil then
			return
		end
		local gate: Gate = if os.clock() < self.matchUntil then "free" else "now"
		if step.Cue then
			self:push("card", function()
				self:showCard(step.Cue :: string, W.FromTrack)
			end)
		else
			local from = self:claimFrom("Quest")
			self:push(gate, function()
				local P = progression()
				if P then
					P.flyReward(
						{ spins = step.Spins or 0, money = step.Money or 0 },
						from or self:centre()
					)
				end
			end)
		end
	elseif msg.spider == true then
		self:push("card", function()
			self:showCard(H.Spider.Cue, W.FromSpider)
		end)
	end
end

-- Where a claim's Candy starts: the CLAIM just pressed (absolute pixels), else nil.
function CandyToast.claimFrom(_self: any, source: any): Vector2?
	local last = EventMenu.lastClaim
	if source == "Quest" and last and os.clock() - last.at <= T.ClaimFromSeconds then
		return last.from
	end
	return nil
end

function CandyToast.centre(self: any): Vector2
	local size = self.layer.AbsoluteSize
	return self.layer.AbsolutePosition + Vector2.new(size.X / 2, size.Y * T.StartYShare)
end

-- Queues a moment; it runs once its gate opens ("now" at once, "free" when the lobby is quiet,
-- "card" when quiet with no card up). Gates do not block each other; within one, order holds.
function CandyToast.push(self: any, gate: Gate, run: () -> ())
	table.insert(self.queue, { gate = gate, run = run, at = os.clock() })
	self:pump()
end

function CandyToast.pump(self: any)
	if self.pumping then
		return
	end
	self.pumping = true
	task.spawn(function()
		while #self.queue > 0 and self.gui.Parent ~= nil do
			local quiet = free()
			local blocked: { [string]: boolean } = {}
			local i = 1
			while i <= #self.queue do
				local item = self.queue[i]
				local open = item.gate == "now"
					or (item.gate == "free" and quiet)
					or (item.gate == "card" and quiet and self.card == nil)
				-- A chip or a prize's flight goes stale; a NEW CUE! card (once a cue) waits as long
				-- as the player is busy (a menu left open, back-to-back matches).
				if item.gate ~= "card" and os.clock() - item.at > T.MaxWaitSeconds then
					table.remove(self.queue, i)
				elseif open and not blocked[item.gate] then
					table.remove(self.queue, i)
					local ok, err = pcall(item.run)
					if not ok then
						warn("[8ball] CandyToast: " .. tostring(err))
					end
					if item.gate == "card" then
						blocked.card = true -- one card at a time
					end
				else
					blocked[item.gate] = true -- keep the order within a gate
					i += 1
				end
			end
			if #self.queue > 0 then
				task.wait(T.PollSeconds)
			end
		end
		self.pumping = false
	end)
end

-- Where the chip lands and what bounces then: the open menu's Candy pill, else the tile.
function CandyToast.target(self: any): (Vector2?, (() -> ())?)
	local menuAt = EventMenu.candyTarget()
	if menuAt then
		return menuAt, EventMenu.bumpCandy
	end
	local corners = self.deps and self.deps.corners
	local tile = corners and corners.eventTile
	local at = tile and tile:target()
	if at then
		return at, function()
			tile:bump()
		end
	end
	return nil, nil
end

--- A Candy chip "+57" (a "2x" tag when `x2`) from `from` (absolute pixels; nil: low middle).
function CandyToast.chip(self: any, candy: number, x2: boolean, from: Vector2?)
	local short = self.layer.AbsoluteSize.Y < SHORT
	local height = if short then T.ShortChipPx else T.ChipPx
	local textPx = math.floor(height * 0.66)
	local tagPx = if short then T.ShortTagPx else T.TagPx
	local words = W.Toast:format(Format.commas(candy))
	local textW = TextService:GetTextSize(words, textPx, font(), Vector2.new(10000, 1000)).X + 6
	local tagW = if x2 then math.floor(tagPx * 1.7) else 0
	local frame = HudParts.frame(self.layer, "CandyChip")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(height + textW + tagW, height)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Candy"
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = H.CandyIcon
	icon.Size = UDim2.fromOffset(height, height)
	icon.ZIndex = 2
	icon.Parent = frame
	local text = HudParts.text(frame, "Amount", textPx, words, HudParts.color(T.ChipTint))
	text.AutoLocalize = false -- only a number
	text.TextWrapped = false
	text.Position = UDim2.fromOffset(height, 0)
	text.Size = UDim2.fromOffset(textW, height)
	text.ZIndex = 2
	if x2 then
		local tag = HudParts.pill(frame, "Double", HudParts.tone("Purple"))
		tag.AnchorPoint = Vector2.new(0, 0.5)
		tag.Position = UDim2.new(0, height + textW, 0.3, 0)
		tag.Size = UDim2.fromOffset(tagW, tagPx)
		tag.Rotation = -8
		tag.ZIndex = 3
		local tagText = HudParts.text(tag, "Words", math.floor(tagPx * 0.75), W.Double)
		tagText.TextWrapped = false
		tagText.Size = UDim2.fromScale(1, 1)
		tagText.ZIndex = 4
	end
	local start = (from or self:centre()) - self.layer.AbsolutePosition
	frame.Position = UDim2.fromOffset(start.X, start.Y)
	UIAnim.popIn(frame)
	task.delay(T.HoldSeconds, function()
		if frame.Parent == nil then
			return
		end
		local target, bump = self:target()
		if target == nil then
			task.wait(T.StillSeconds)
			local fade = TweenInfo.new(0.25)
			TweenService:Create(icon, fade, { ImageTransparency = 1 }):Play()
			HudParts.setTextTransparency(text, 1)
			task.wait(0.25)
			frame:Destroy()
			return
		end
		local to = target - self.layer.AbsolutePosition
		local scale = UIAnim.scaleOf(frame)
		local info = TweenInfo.new(T.FlySeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(frame, info, { Position = UDim2.fromOffset(to.X, to.Y) }):Play()
		local shrink = TweenService:Create(scale, info, { Scale = 0.55 })
		shrink.Completed:Connect(function()
			frame:Destroy()
			if bump then
				bump()
			end
		end)
		shrink:Play()
	end)
end

--- The NEW CUE! card for `cueId` (a small Slam popup: thumbnail, name, tier tag, `note`, OK).
--- Laid out at its natural size from its width, then scaled down to fit a short screen.
function CandyToast.showCard(self: any, cueId: string, note: string)
	local size = self.layer.AbsoluteSize
	local short = size.Y < SHORT
	local width = if short then T.ShortCardWidthPx else T.CardWidthPx
	local pad = math.floor(width * 0.06)
	local titlePx = math.floor(width * 0.12)
	local thumbPx = math.floor(width * 0.42)
	local namePx = math.floor(width * 0.075)
	local tagH = math.floor(width * 0.07)
	local notePx = math.floor(width * 0.055)
	local okH = math.floor(width * 0.14)
	local height = pad + titlePx + 8 + thumbPx + 6 + namePx + 6 + tagH + 6 + notePx + 12 + okH + pad
	local screen = Instance.new("ScreenGui")
	screen.Name = "HalloweenCueCard"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = T.CardDisplayOrder
	screen.Parent = self.gui.Parent
	local dim = Instance.new("TextButton")
	dim.Name = "CueCard"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = T.DimTransparency
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.Selectable = false
	dim.ZIndex = 10
	dim.Parent = screen
	local card = HudParts.popupCard(dim, "Card")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromOffset(width, height)
	card.ZIndex = 11
	local fit = Instance.new("UIScale")
	fit.Name = "Fit"
	fit.Scale = math.min(1, (size.X - 24) / width, size.Y * T.CardHeightShare / height)
	fit.Parent = card
	local title = HudParts.text(card, "Title", titlePx, W.NewCue, HudParts.tone("Gold"))
	title.TextWrapped = false
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.new(0.5, 0, 0, pad + titlePx / 2)
	title.Size = UDim2.fromOffset(width - 2 * pad, titlePx + 6)
	title.ZIndex = 14
	local y = pad + titlePx + 8
	local thumb = CueThumb.new(card, cueId)
	thumb.AnchorPoint = Vector2.new(0.5, 0)
	thumb.Position = UDim2.new(0.5, 0, 0, y)
	thumb.Size = UDim2.fromOffset(thumbPx, thumbPx)
	thumb.ZIndex = 12
	y += thumbPx + 6
	local name = HudParts.text(card, "Name", namePx, CueThumb.cueName(cueId))
	name.Position = UDim2.fromOffset(pad, y)
	name.Size = UDim2.fromOffset(width - 2 * pad, namePx + 4)
	name.ZIndex = 13
	y += namePx + 6
	local rarity = CueThumb.rarityOf(cueId)
	local tag = HudParts.pill(card, "Tier", CueThumb.rarityColor(rarity))
	tag.AnchorPoint = Vector2.new(0.5, 0)
	tag.Position = UDim2.new(0.5, 0, 0, y)
	tag.Size = UDim2.fromOffset(math.floor(width * 0.42), tagH)
	tag.ZIndex = 13
	local tagText = HudParts.text(tag, "Words", math.floor(tagH * 0.7), CueThumb.rarityName(rarity))
	tagText.Size = UDim2.fromScale(1, 1)
	tagText.ZIndex = 14
	y += tagH + 6
	local noteText = HudParts.note(card, "Note", notePx, note)
	noteText.Position = UDim2.fromOffset(pad, y)
	noteText.Size = UDim2.fromOffset(width - 2 * pad, notePx + 4)
	noteText.ZIndex = 13
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		cardShownAt = nil
		ContextActionService:UnbindAction(CLOSE_ACTION)
		if GuiService.SelectedObject ~= nil and GuiService.SelectedObject:IsDescendantOf(dim) then
			GuiService.SelectedObject = nil
		end
		UIAnim.popOut(card, function()
			screen:Destroy()
			self.card = nil
			self:pump()
		end)
	end
	local ok = HudParts.candy(card, W.Ok, close, "Green", nil)
	ok.Name = "Ok"
	ok.AnchorPoint = Vector2.new(0.5, 1)
	ok.Position = UDim2.new(0.5, 0, 1, -pad)
	ok.Size = UDim2.fromOffset(math.floor(width * 0.45), okH)
	ok.ZIndex = 14
	HudParts.setButtonTextSize(ok, math.floor(okH * 0.55))
	self.card = dim
	cardShownAt = os.clock()
	UIAnim.popIn(card)
	UIAnim.slam(title, HudParts.tone("Gold"), { burst = true })
	UIAnim.glowBurst(thumb, CueThumb.rarityColor(rarity), 0.6)
	if PadMode.active() then
		GuiService.SelectedObject = ok
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
	task.delay(T.AutoCloseSeconds, close)
end

return CandyToast
