--!strict
-- HubCorners: the hub's small corner buttons (GUI lane, designer 2026-10-03, C2), shown with the
-- left column (Progression.update: never in a match or under a popup):
-- - Right edge, a little above the middle: the Daily Challenge target, its glow flashing. Daily
--   challenges are not built yet, so a press only says "Soon" in a bubble beside it. The
--   gamepad's D-pad down presses it when the Free Reward tile is gone (Progression.padRoute).
-- - Under it, while open for this player: the Starter Pack and VIP's welcome offer on one tile
--   with its countdown, flipping from one to the other every few seconds when both are open
--   (tutorial v2 4.11); a press opens the Shop on the shown offer's section. Offers never pop up
--   by themselves (designer, 2026-10-03). The challenge and the offer tile are about the left
--   column's tiles' size.
-- - The tutorial hides the challenge, the offer tile, Invite and Plus until its soft part
--   (Steps.Reveal: Challenge, Offer, Invite, Plus); each pops in as it comes back. The soft
--   part's click-once "!" sits on the challenge and the offer tile (setFresh).
-- - Bottom left, just right of the money HUD: Invite (Roblox's invite prompt, carrying the
--   invite's launch data, Progression/Social.launchData) and Roblox Plus (the Store's Plus
--   prompt; hidden for members and where the shop does not offer Plus).
-- - Top left, right of the rank HUD: the Settings gear (GUI lane, C10; SettingsMenu).
-- Sizes in Config.UI.Corners; words in Strings.Corners. Never gamepad stops (a selected button
-- would take the left stick from walking); the D-pad reaches the challenge.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local InvitePrompt = require(script.Parent.InvitePrompt)
local ItemState = require(script.Parent.ItemState)
local Menus = require(script.Parent.Menus)
local ShopParts = require(script.Parent.ShopParts)
local TutorialAnchors = require(script.Parent.TutorialAnchors)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local C = Config.UI.Corners
local U = Config.UI.Settings
local K = Config.UI.Kit
local S = Config.Multiplayer.Style
local W = Strings.Corners

local HubCorners = {}
HubCorners.__index = HubCorners

type Corner = {
	button: TextButton,
	icon: ImageLabel,
	word: TextLabel,
}

local function round(n: number): number
	return math.floor(n + 0.5)
end

-- An icon button with the candy's hover, squish and bounce but no box (like the column's tiles),
-- its word across the icon's lower edge.
local function corner(
	parent: Instance,
	name: string,
	iconKey: string,
	words: string,
	press: () -> ()
): Corner
	local button = HudParts.candy(parent, "", press, "Blue", nil)
	button.Name = name
	button.Selectable = false
	local parts = HudParts.candyParts(button)
	parts.face.Visible = false
	local icon = HudParts.icon(parts.body, iconKey, "Art")
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.45)
	icon.Size = UDim2.fromScale(1.05, 1.05)
	icon.ZIndex = 3
	local word = HudParts.text(parts.body, "Word", C.WordPx, words)
	word.TextWrapped = false
	word.AnchorPoint = Vector2.new(0.5, 0.5)
	word.Position = UDim2.fromScale(0.5, 0.92)
	word.ZIndex = 4
	-- Hover (or a gamepad resting on it): sun rays behind the icon, as on the column.
	HudParts.onLit(button, function(lit: boolean)
		UIAnim.sunRays(icon, lit)
	end)
	return { button = button, icon = icon, word = word }
end

--- Build the corners into `screen` (the HUD ScreenGui), hidden until setVisible(true). `deps`:
--- money (MoneyHud: Invite and Plus sit right of it).
function HubCorners.new(screen: ScreenGui, deps: any): any
	local self: any = setmetatable({}, HubCorners)
	self.screen = screen
	self.deps = deps
	self.wanted = false
	self.showing = false
	self.alive = true
	self.challengeHidden = false
	self.connections = {} :: { RBXScriptConnection }
	local root = HudParts.frame(screen, "HubCorners")
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = Config.UI.Menu.Column.ZIndex
	root.Visible = false
	self.root = root

	self.challenge = corner(root, "Challenge", "Challenge", W.Challenge, function()
		TutorialAnchors.notePress("Challenge") -- the soft part's click-once "!" goes
		self:pressChallenge()
	end)
	self.inviteTile = corner(root, "Invite", "Invite", W.Invite, function()
		UISound.play("Click")
		TutorialAnchors.notePress("Invite")
		self:invite()
	end)
	self.gearTile = corner(root, "Settings", "Gear", W.Settings, function()
		UISound.play("Click")
		Menus.open("Settings")
	end)
	self.plusTile = corner(root, "Plus", "RobloxPlus", W.Plus, function()
		UISound.play("Click")
		task.spawn(ItemState.request, "StoreRequest", "RobloxPlus")
	end)

	-- The open offers share one tile under the challenge: each offer's window (`key` in
	-- ShopState.offers), the Shop section a press opens, its icon and word. `openOffers` are
	-- the ones open now, in this order; `offerIndex` the one shown.
	local list = Config.Products.List
	local vipOff = math.floor((1 - list.VipOffer.Robux / list.Vip.Robux) * 100 + 0.5)
	self.offerSpecs = {
		{ key = "StarterPack", section = "Offer", icon = "StarterPack", words = W.Starter },
		{ key = "VipOffer", section = "Vip", icon = "Vip", words = W.Vip:format(vipOff) },
	}
	self.openOffers = {} :: { { spec: any, endsAt: number } }
	self.offerIndex = 1
	self.offerKey = nil :: string? -- the offer drawn on the tile now
	self.offerFlippedAt = os.clock()
	self.flipping = false
	local offerTile = corner(root, "Offer", "StarterPack", W.Starter, function()
		local shown = self.openOffers[self.offerIndex]
		if shown then
			UISound.play("Click")
			TutorialAnchors.notePress("Offer")
			Menus.open("Shop", shown.spec.section)
		end
	end)
	offerTile.button.Visible = false
	local timer = HudParts.text(HudParts.candyParts(offerTile.button).body, "Timer", C.TimerPx, "")
	timer.TextWrapped = false
	timer.TextColor3 = HudParts.tone("Gold")
	timer.AnchorPoint = Vector2.new(0.5, 0.5)
	timer.ZIndex = 4
	self.offerTile, self.offerTimer = offerTile, timer

	-- The soft part's click-once "!" (setFresh): a red dot on a tile's top-right corner.
	self.fresh = {} :: { [string]: Frame }
	for key, tile: any in { Challenge = self.challenge, Offer = offerTile } do
		local dot =
			HudParts.pill(HudParts.candyParts(tile.button).body, "New", HudParts.tone("Red"))
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.86, 0.1)
		dot.ZIndex = 6
		dot.Visible = false
		local words = HudParts.text(dot, "Words", C.WordPx + 1, Strings.Tutorial.New)
		words.TextWrapped = false
		words.Size = UDim2.fromScale(1, 1)
		words.ZIndex = 7
		self.fresh[key] = dot
	end
	-- The tutorial's anchors: the soft part's glows sit behind these.
	TutorialAnchors.set("Challenge", self.challenge.button)
	TutorialAnchors.set("Offer", offerTile.button)
	TutorialAnchors.set("Invite", self.inviteTile.button)

	-- The challenge's glow flashes behind it.
	local glow = Instance.new("ImageLabel")
	glow.Name = "Flash"
	glow.BackgroundTransparency = 1
	glow.Image = K.Art.SoftGlow
	glow.ImageColor3 = HudParts.tone("Gold")
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.45)
	glow.Size = UDim2.fromScale(2, 2)
	glow.ZIndex = 1
	glow.Parent = HudParts.candyParts(self.challenge.button).body
	self.flash = UIAnim.loop(glow, function(clock: number)
		-- A smooth pulse (a sudden reset every flash looked like blinking).
		local wave = 0.5 + 0.5 * math.cos(2 * math.pi * clock / C.ChallengeFlashSeconds)
		glow.ImageTransparency = 0.25 + 0.75 * (1 - wave)
	end)

	local function queueLayout()
		self:layout()
	end
	table.insert(
		self.connections,
		screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueLayout)
	)
	local rankHolder = deps.rankHud and deps.rankHud.holder
	if typeof(rankHolder) == "Instance" and rankHolder:IsA("GuiObject") then
		table.insert(
			self.connections,
			rankHolder:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueLayout)
		)
		table.insert(
			self.connections,
			rankHolder:GetPropertyChangedSignal("AbsolutePosition"):Connect(queueLayout)
		)
	end
	local moneyRoot = deps.money and deps.money.root
	if typeof(moneyRoot) == "Instance" and moneyRoot:IsA("GuiObject") then
		table.insert(
			self.connections,
			moneyRoot:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueLayout)
		)
		table.insert(
			self.connections,
			moneyRoot:GetPropertyChangedSignal("AbsolutePosition"):Connect(queueLayout)
		)
	end
	local player = Players.LocalPlayer
	if player then
		table.insert(
			self.connections,
			player:GetPropertyChangedSignal("MembershipType"):Connect(function()
				self:refreshPlus()
			end)
		)
	end
	table.insert(
		self.connections,
		ItemState.Changed.Shop:Connect(function()
			self:refreshPlus()
			self:refreshOffers()
		end)
	)
	table.insert(
		self.connections,
		TutorialAnchors.Changed:Connect(function()
			self:refreshShown()
			self:refreshOffers()
		end)
	)
	-- The countdowns tick once a second while the corners show; with two offers open the tile
	-- flips every OfferFlipSeconds.
	task.spawn(function()
		while self.alive do
			if self.showing then
				self:refreshOffers()
				if
					#self.openOffers > 1
					and os.clock() - self.offerFlippedAt >= C.OfferFlipSeconds
				then
					self:flipOffer()
				end
			end
			task.wait(1)
		end
	end)
	self:refreshPlus()
	self:refreshOffers()
	self:layout()
	-- Studio only: GuiQA:Invoke("cornerOffers", true) opens both offers' windows on the tile
	-- (to watch it flip); false goes back to the shop's own.
	GuiQA.add("cornerOffers", function(on: boolean)
		local ends = workspace:GetServerTimeNow() + 3600
		self.fakeOffers = if on
			then {
				StarterPack = { open = true, endsAt = ends },
				VipOffer = { open = true, endsAt = ends },
			}
			else nil
		self:refreshOffers()
		return #self.openOffers
	end)
	return self
end

-- Show `button` or not; one coming back while the corners show pops in (a small HUD piece's
-- entrance). True when it changed.
local function setShown(self: any, button: GuiObject, show: boolean): boolean
	if button.Visible == show then
		return false
	end
	if show and self.showing then
		UIAnim.popIn(button)
	else
		button.Visible = show
	end
	return true
end

--- The challenge, Invite and Plus: each shows unless the tutorial hides it (Steps.Reveal),
--- the challenge also unless the queue card stands there, Plus only where it is offered.
function HubCorners.refreshShown(self: any)
	local changed = setShown(
		self,
		self.challenge.button,
		not self.challengeHidden and not TutorialAnchors.hidden("Challenge")
	)
	changed = setShown(self, self.inviteTile.button, not TutorialAnchors.hidden("Invite"))
		or changed
	changed = setShown(
		self,
		self.plusTile.button,
		self.plusOffered == true and not TutorialAnchors.hidden("Plus")
	) or changed
	if changed then
		self:layout()
	end
end

--- The soft part's click-once "!" on the challenge or the offer tile (`key`: "Challenge" or
--- "Offer").
function HubCorners.setFresh(self: any, key: string, on: boolean)
	local dot = self.fresh[key]
	if dot == nil or dot.Visible == on then
		return
	end
	if on then
		UIAnim.popIn(dot)
	else
		dot.Visible = false
	end
end

-- Draw `spec`'s icon, word and press on the offer tile.
local function drawOffer(self: any, spec: any)
	self.offerKey = spec.key
	HudParts.setIcon(self.offerTile.icon, spec.icon)
	self.offerTile.word.Text = spec.words
end

--- The next open offer on the tile: it narrows to nothing, turns to the other offer and opens
--- again (each half OfferFlipHalfSeconds).
function HubCorners.flipOffer(self: any)
	if self.flipping or #self.openOffers < 2 then
		return
	end
	self.flipping = true
	self.offerFlippedAt = os.clock()
	local body = HudParts.candyParts(self.offerTile.button).body
	-- Narrow toward its middle, like a card turning.
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	local full = body.Size
	local half = C.OfferFlipHalfSeconds
	local narrow = TweenService:Create(
		body,
		TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = UDim2.new(0, 0, full.Y.Scale, full.Y.Offset) }
	)
	narrow.Completed:Connect(function()
		self.offerIndex = self.offerIndex % #self.openOffers + 1
		local shown = self.openOffers[self.offerIndex]
		if shown then
			drawOffer(self, shown.spec)
			self.offerTimer.Text = ShopParts.timeLeft(shown.endsAt - workspace:GetServerTimeNow())
		end
		local open = TweenService:Create(
			body,
			TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = full }
		)
		open.Completed:Connect(function()
			body.Size = full
			self.flipping = false
		end)
		open:Play()
	end)
	narrow:Play()
end

--- The offer tile: the offers whose window is open and that are not owned, the shown one's
--- countdown; hidden while none is (or the tutorial hides it, or the queue card stands there).
function HubCorners.refreshOffers(self: any)
	local shop = ItemState.shop()
	local state: any = if type(shop) == "table" then shop else {}
	local windows = if type(state.offers) == "table" then state.offers else {}
	if self.fakeOffers then
		windows = self.fakeOffers -- Studio QA (GuiQA "cornerOffers")
	end
	local now = workspace:GetServerTimeNow()
	local allowed = not self.challengeHidden and not TutorialAnchors.hidden("Offer")
	local open = {}
	for _, spec in self.offerSpecs do
		local window = windows[spec.key]
		local owned = if self.fakeOffers
			then false
			elseif spec.key == "StarterPack" then state.starterBought == true
			else state.vip == true
		if
			allowed
			and not owned
			and type(window) == "table"
			and window.open == true
			and type(window.endsAt) == "number"
			and window.endsAt > now
		then
			table.insert(open, { spec = spec, endsAt = window.endsAt })
		end
	end
	self.openOffers = open
	if self.offerIndex > #open then
		self.offerIndex = 1
	end
	local shown = open[self.offerIndex]
	if shown and shown.spec.key ~= self.offerKey and not self.flipping then
		drawOffer(self, shown.spec)
	end
	if setShown(self, self.offerTile.button, shown ~= nil) then
		self:layout()
	end
	if shown then
		self.offerTimer.Text = ShopParts.timeLeft(shown.endsAt - now) -- "6d 4h", "2:59:12"
	end
end

function HubCorners.refreshPlus(self: any)
	local player = Players.LocalPlayer
	local member = player ~= nil and player.MembershipType == Enum.MembershipType.Premium
	local shop = ItemState.shop()
	local offered = type(shop) == "table" and shop.robloxPlus == true
	self.plusOffered = offered and not member
	self:refreshShown()
end

function HubCorners.layout(self: any)
	local size = self.screen.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local short = size.Y < S.ShortHeight
	local big = if short then C.ShortChallengePx else C.ChallengePx
	local small = if short then C.ShortSmallPx else C.SmallPx
	local wordPx = if short then C.ShortWordPx else C.WordPx
	local ch = self.challenge
	ch.button.AnchorPoint = Vector2.new(1, 0.5)
	ch.button.Size = UDim2.fromOffset(big, big)
	ch.button.Position = UDim2.new(1, -C.ChallengeRightPx, C.ChallengeYShare, 0)
	-- The word is wider than the icon: it overhangs both sides.
	ch.word.Size = UDim2.fromOffset(big * 2, wordPx + 4)
	HudParts.setTextSize(ch.word, wordPx)

	-- The offer tile under the challenge, centred on it.
	local offerPx = if short then C.ShortOfferPx else C.OfferPx
	local timerPx = if short then C.ShortTimerPx else C.TimerPx
	local centreX = -C.ChallengeRightPx - big / 2
	local offerY = size.Y * C.ChallengeYShare + big / 2 + C.OfferGapPx + offerPx / 2
	local offer = self.offerTile
	offer.button.AnchorPoint = Vector2.new(0.5, 0.5)
	offer.button.Size = UDim2.fromOffset(offerPx, offerPx)
	offer.button.Position = UDim2.new(1, round(centreX), 0, round(offerY))
	offer.word.Size = UDim2.fromOffset(round(offerPx * 2.4), wordPx + 4)
	HudParts.setTextSize(offer.word, wordPx)
	self.offerTimer.Position = UDim2.new(0.5, 0, 0.92, wordPx + 2)
	self.offerTimer.Size = UDim2.fromOffset(offerPx * 2, timerPx + 4)
	HudParts.setTextSize(self.offerTimer, timerPx, timerPx)
	for _, dot in self.fresh do
		dot.Size = UDim2.fromOffset(wordPx + 12, wordPx + 8)
	end

	-- The gear right of the rank HUD's card at its biggest (it grows on hover and press), centred
	-- on it.
	local gearPx = if short then U.ShortGearPx else U.GearPx
	local gear = self.gearTile
	gear.button.AnchorPoint = Vector2.new(0, 0.5)
	gear.button.Size = UDim2.fromOffset(gearPx, gearPx)
	local rankFound = self.deps.rankHud and self.deps.rankHud.holder
	local rankHolder: GuiObject? = if typeof(rankFound) == "Instance"
			and rankFound:IsA("GuiObject")
		then rankFound
		else nil
	if rankHolder and rankHolder.AbsoluteSize.X > 0 then
		local o = self.screen.AbsolutePosition
		local rankHud = self.deps.rankHud
		local right = if rankHud and rankHud.grownRight
			then rankHud:grownRight()
			else rankHolder.AbsolutePosition.X + rankHolder.AbsoluteSize.X
		gear.button.Position = UDim2.fromOffset(
			round(right - o.X + U.GearGapPx),
			round(rankHolder.AbsolutePosition.Y - o.Y + rankHolder.AbsoluteSize.Y / 2)
		)
	else
		gear.button.Position = UDim2.fromOffset(300, 40)
	end
	gear.word.Size = UDim2.fromOffset(gearPx * 2, wordPx + 4)
	HudParts.setTextSize(gear.word, wordPx)

	-- Invite and Plus right of the money HUD, centred on it.
	local origin = self.screen.AbsolutePosition
	local found = self.deps.money and self.deps.money.root
	local moneyRoot: GuiObject? = if typeof(found) == "Instance" and found:IsA("GuiObject")
		then found
		else nil
	local x, y = 200, size.Y - small
	if moneyRoot and moneyRoot.AbsoluteSize.X > 0 then
		x = moneyRoot.AbsolutePosition.X - origin.X + moneyRoot.AbsoluteSize.X + C.SmallGapPx
		y = moneyRoot.AbsolutePosition.Y - origin.Y + moneyRoot.AbsoluteSize.Y / 2
	end
	for index, c in { self.inviteTile, self.plusTile } do
		c.button.AnchorPoint = Vector2.new(0, 0.5)
		c.button.Size = UDim2.fromOffset(small, small)
		c.button.Position =
			UDim2.fromOffset(round(x + (index - 1) * (small + C.SmallGapPx)), round(y))
		c.word.Size = UDim2.fromOffset(small * 2, wordPx + 4)
		HudParts.setTextSize(c.word, wordPx)
	end
end

--- Show or hide the corners (Progression, with the column). Cheap to call every frame.
function HubCorners.setVisible(self: any, visible: boolean)
	local player = Players.LocalPlayer
	local loaded = player == nil or player:GetAttribute("DataLoaded") == true
	local show = visible and loaded
	if show == self.showing then
		return
	end
	self.showing = show
	if show then
		self.root.Visible = true
		self:layout()
		if self.challenge.button.Visible then
			UIAnim.popIn(self.challenge.button)
		end
	else
		self.root.Visible = false
	end
end

--- Hide only the Daily Challenge (the queue card stands over the right edge while you wait).
function HubCorners.setChallengeHidden(self: any, hidden: boolean)
	if self.challengeHidden == hidden then
		return
	end
	self.challengeHidden = hidden
	self:refreshShown()
	self:refreshOffers()
end

function HubCorners.isShown(self: any): boolean
	return self.showing
end

--- The Daily Challenge: a "Soon" bubble beside it (a press, or the D-pad's down).
function HubCorners.pressChallenge(self: any)
	if not self.showing then
		return
	end
	UISound.play("Click")
	local button = self.challenge.button
	UIAnim.bounce(button)
	UIAnim.glowBurst(self.challenge.icon, HudParts.tone("Gold"), 0.5)
	self:say(W.ChallengeSoon, button, -1)
end

--- A white bubble with `text` beside `button`: to its left (`side` -1) or right (1).
function HubCorners.say(self: any, text: string, button: GuiObject, side: number)
	if self.bubble then
		self.bubble:Destroy()
	end
	local bubble = HudParts.pill(self.root, "Bubble", HudParts.tone("White"))
	bubble.AnchorPoint = Vector2.new(if side < 0 then 1 else 0, 0.5)
	local words = HudParts.note(bubble, "Words", C.BubblePx, text)
	words.Size = UDim2.new(1, -16, 1, 0)
	words.Position = UDim2.fromOffset(8, 0)
	words.TextWrapped = false
	local wide = TextService:GetTextSize(
		text,
		C.BubblePx,
		(Enum.Font :: any)[K.Font],
		Vector2.new(2000, 200)
	).X
	local width = math.min(self.screen.AbsoluteSize.X - 40, wide + 28)
	bubble.Size = UDim2.fromOffset(round(width), C.BubblePx + 18)
	local pos = button.AbsolutePosition - self.root.AbsolutePosition
	local x = if side < 0 then pos.X - 8 else pos.X + button.AbsoluteSize.X + 8
	bubble.Position = UDim2.fromOffset(round(x), round(pos.Y + button.AbsoluteSize.Y / 2))
	bubble.ZIndex = 8
	words.ZIndex = 9
	self.bubble = bubble
	UIAnim.popIn(bubble)
	task.delay(C.BubbleSeconds, function()
		if self.bubble == bubble then
			self.bubble = nil
			UIAnim.popOut(bubble, function()
				bubble:Destroy()
			end)
		end
	end)
end

--- Roblox's invite prompt, carrying our launch data (the invite rewards).
function HubCorners.invite(self: any)
	InvitePrompt.show(function()
		self:say(W.InviteFailed, self.inviteTile.button, 1)
	end)
end

function HubCorners.destroy(self: any)
	self.alive = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	self.flash.stop()
	self.root:Destroy()
end

return HubCorners
