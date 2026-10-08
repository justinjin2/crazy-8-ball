--!strict
-- FreePlaytime: the Free Reward menu's Playtime section (the designer's pick "free_other A",
-- 2026-10-08), under "- PLAYTIME -": a pale panel with its navy pill ("TODAY'S GIFTS") and the
-- day's five playtime gifts in a row of white tiles (Config.Daily.Playtime): "5 min", the
-- gift's pictures and money, and its status: Claimed (grey with a check), Claim! (green,
-- breathing; the tile glows gold), the time left on the next gift (white with a stopwatch) or a
-- padlock on the ones after it. The time is the server's (`playSeconds` at `sentAt`), ticked on
-- here between two states; a gift shows Claim once its time is reached (the server credits the
-- seconds since its last tick on a claim). Claim calls ctx.claim("ClaimPlaytime", index).
-- Sizes in Config.UI.FreeReward.Playtime, words in Strings.FreeReward.
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
local F = Config.UI.FreeReward
local T = F.Playtime
local GIFTS = #Config.Daily.Playtime
local W = Strings.FreeReward
local rgb, round = ShopCards.rgb, ShopCards.round

type Gift = {
	index: number,
	box: ShopCards.Box,
	glow: ImageLabel,
	time: TextLabel, -- "5 min"
	pictures: FreeParts.Pictures,
	amount: TextLabel,
	status: TextButton,
	need: number, -- seconds of play it needs
	claimed: boolean,
	ready: boolean, -- the server says it can be claimed
	mode: string,
}

local FreePlaytime = {}
FreePlaytime.__index = FreePlaytime

--- Build the section (closed) into `parent` (the menu's Playtime group). `ctx` as FreeDaily's.
function FreePlaytime.new(parent: Instance, ctx: any): any
	local self: any = setmetatable({}, FreePlaytime)
	self.ctx = ctx
	self.k = 1
	self.state = nil :: any
	self.open = false
	self.pulses = {} :: { [TextButton]: UIAnim.Handle }
	local root = HudParts.frame(parent, "PlaytimeSection")
	root.ZIndex = 2
	self.root = root
	local panel = ShopCards.panel(root, "PlaytimePanel")
	self.panel = panel
	self.title = ShopCards.titlePill(root, "PlaytimeTitle", W.PlaytimeTitle)
	self.gifts = {} :: { Gift }
	for index = 1, GIFTS do
		local box = ShopCards.inner(panel.frame, "PlaytimeGift" .. index, 3)
		-- A soft gold glow behind a gift that can be claimed.
		local glow =
			ShopCards.image(box.frame, "Glow", Config.UI.GrandOpeningCard.Images.BlockGlow, 3)
		glow.ImageColor3 = rgb(T.GlowTint)
		glow.Position = UDim2.fromScale(0.5, 0.45)
		glow.Size = UDim2.fromScale(1.1, 1.1)
		glow.Visible = false
		local time = ShopCards.label(box.frame, "Time", "", nil, 6)
		time.AutoLocalize = false -- "5 min" is built from a number
		local amount = ShopCards.label(box.frame, "Amount", "", rgb(Config.UI.Kit.Numbers.Money), 8)
		amount.AutoLocalize = false
		local made: Gift = {
			index = index,
			box = box,
			glow = glow,
			time = time,
			pictures = FreeParts.pictures(box.frame, "Pictures", 4),
			amount = amount,
			status = nil :: any,
			need = 0,
			claimed = false,
			ready = false,
			mode = "",
		}
		made.status = FreeParts.status(box.frame, "Status", function()
			if made.mode == "Claim" then
				ctx.claim("ClaimPlaytime", index, "Gift" .. index, made.status)
			end
		end)
		table.insert(self.gifts, made)
	end
	return self
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

--- The section's height at the scale `k`.
function FreePlaytime.heightFor(k: number): number
	return round((B.TitlePill.HeightUnits / 2 + T.Units[2]) * k)
end

-- Lay a gift's tile out in its own units.
local function layoutGift(g: Gift, k: number)
	local U = T.Tile
	local w = U.Units[1]
	ShopCards.sizeBox(g.box, k, P.InnerCornerUnits, P.InnerEdgeUnits)
	ShopCards.line(g.time, k, w / 2, U.TimeY, w - 2 * U.SideUnits, ShopCards.textPx(U.TimeUnits, k))
	local S = U.Pictures
	FreeParts.layoutPictures(g.pictures, k, w / 2, S[1], S[2], S[3])
	ShopCards.line(
		g.amount,
		k,
		w / 2,
		U.AmountY,
		w - 2 * U.SideUnits,
		ShopCards.textPx(U.AmountUnits, k)
	)
	FreeParts.layoutStatus(
		g.status,
		k,
		w / 2,
		U.StatusY,
		w - 2 * U.SideUnits,
		U.StatusUnits,
		U.StatusTextUnits
	)
end

--- Lay the section out across `width` pixels at the scale `k`, its top `y` pixels down its
--- group; returns its height.
function FreePlaytime.layout(self: any, width: number, k: number, y: number): number
	self.k = k
	local Wd, Hd = T.Units[1], T.Units[2]
	local top = B.TitlePill.HeightUnits / 2
	local cardW = round(Wd * k)
	local height = FreePlaytime.heightFor(k)
	self.root.Position = UDim2.fromOffset(math.floor((width - cardW) / 2), y)
	self.root.Size = UDim2.fromOffset(cardW, height)
	ShopCards.put(self.panel.frame, k, Wd / 2, top + Hd / 2, Wd, Hd)
	ShopCards.sizeBox(self.panel, k, P.CornerUnits, P.EdgeUnits)
	ShopCards.layoutTitlePill(self.title, k, Wd / 2, top)
	local G, U = T.Grid, T.Tile
	local tw, th = U.Units[1], U.Units[2]
	for _, g in self.gifts :: { Gift } do
		local x = G.Left + (g.index - 1) * (tw + G.GapUnits) + tw / 2
		ShopCards.put(g.box.frame, k, x, G.Top + th / 2, tw, th)
		layoutGift(g, k)
	end
	return height
end

--------------------------------------------------------------------------------------------
-- What the server says
--------------------------------------------------------------------------------------------

local function setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

-- Seconds played today by `now` (the server's clock): the state's count ticked on, never past
-- the day's end.
function FreePlaytime.played(self: any, now: number): number
	local state = self.state
	if type(state) ~= "table" then
		return 0
	end
	local base = RewardsParts.whole(state.playSeconds)
	local sentAt = if type(state.sentAt) == "number" then state.sentAt else now
	local resetsAt = if type(state.resetsAt) == "number" then state.resetsAt else math.huge
	return base + math.clamp(now - sentAt, 0, math.max(0, resetsAt - sentAt))
end

--- Draw a RewardState (nil before the first: nothing).
function FreePlaytime.refresh(self: any, state: any)
	self.state = state
	local list = if type(state) == "table" and type(state.playtime) == "table"
		then state.playtime
		else {}
	local k = self.k
	for _, g in self.gifts :: { Gift } do
		local view = list[g.index]
		g.box.frame.Visible = type(view) == "table"
		if type(view) == "table" then
			local reward = RewardsParts.reward(view.reward)
			g.need = RewardsParts.whole(view.minutes) * 60
			g.claimed = view.claimed == true
			g.ready = view.ready == true
			setText(g.time, W.Minutes:format(RewardsParts.whole(view.minutes)))
			FreeParts.setPictures(g.pictures, reward)
			local S = T.Tile.Pictures
			FreeParts.layoutPictures(g.pictures, k, T.Tile.Units[1] / 2, S[1], S[2], S[3])
			setText(g.amount, if reward.money > 0 then Format.money(reward.money) else "")
			g.amount.Visible = reward.money > 0
			FreeParts.tintPictures(g.pictures, FreeParts.claimedTint(g.claimed))
		end
	end
	self:tick(workspace:GetServerTimeNow())
end

--- Every TickSeconds while open (and on every state): the countdown and each status.
function FreePlaytime.tick(self: any, now: number)
	if type(self.state) ~= "table" then
		return
	end
	local played = self:played(now)
	local waiting = false -- the first gift not reached yet counts down; those after are locked
	for _, g in self.gifts :: { Gift } do
		if g.box.frame.Visible then
			local due = g.need > 0 and played >= g.need + F.ReadyMarginSeconds
			local mode = "Lock"
			local text: string? = nil
			if g.claimed then
				mode = "Claimed"
			elseif g.ready or due then
				mode = "Claim"
			elseif not waiting then
				waiting = true
				mode = "Wait"
				text = RewardsParts.clock(math.max(0, g.need - played))
			end
			g.mode = mode
			FreeParts.setStatus(g.status, mode, text, self.ctx.busy("Gift" .. g.index))
			g.glow.Visible = mode == "Claim"
			self:setPulse(g.status, mode == "Claim" and self.open)
		end
	end
end

-- A gift's Claim! breathes while it can be pressed and the menu is open.
function FreePlaytime.setPulse(self: any, button: TextButton, on: boolean)
	local handle = self.pulses[button]
	if on and not handle then
		self.pulses[button] = FreeParts.pulse(button)
	elseif not on and handle then
		handle.stop()
		self.pulses[button] = nil
	end
end

--- Whether a gift can be claimed now (the Playtime jump button's "!").
function FreePlaytime.claimable(self: any): boolean
	for _, g in self.gifts :: { Gift } do
		if g.box.frame.Visible and not g.claimed and (g.ready or g.mode == "Claim") then
			return true
		end
	end
	return false
end

--- The button a gamepad lands on: the first gift's Claim!.
function FreePlaytime.primary(self: any): GuiObject?
	for _, g in self.gifts :: { Gift } do
		if g.mode == "Claim" and g.status.Selectable then
			return g.status
		end
	end
	return nil
end

--------------------------------------------------------------------------------------------
-- Stage
--------------------------------------------------------------------------------------------

--- Register every piece with the menu's `stage` (ids in Config.UI.FreeReward.Open).
function FreePlaytime.register(self: any, stage: Stage.Stage, _keep: (UIAnim.Handle) -> ())
	stage:add("PlaytimePanel", self.panel.frame)
	stage:add("PlaytimeTitle", self.title.pill)
	for _, g in self.gifts :: { Gift } do
		stage:add("PlaytimeGift" .. g.index, g.box.frame)
	end
end

--- The menu opened or closed: the breathing Claim! buttons.
function FreePlaytime.setOpen(self: any, open: boolean)
	self.open = open
	if not open then
		for button, handle in self.pulses do
			handle.stop()
			self.pulses[button] = nil
		end
	else
		self:tick(workspace:GetServerTimeNow())
	end
end

return FreePlaytime
