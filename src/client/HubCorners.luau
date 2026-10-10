--!strict
-- HubCorners: the hub's small corner buttons (GUI lane, designer 2026-10-03, C2), shown with the
-- left column (Progression.update: never in a match or under a popup):
-- - Right edge, a little above the middle: the Daily Challenge target, its glow flashing. Daily
--   challenges are not built yet: off for the release (Config.UI.Corners.ChallengeOn, designer
--   2026-10-10), and the offer tile takes its place. The
--   gamepad's D-pad down presses it when the Free Reward tile is gone (Progression.padRoute).
-- - Under it, while open for this player: the Starter Pack and VIP's welcome offer on one tile
--   with its countdown, flipping from one to the other every few seconds when both are open
--   (tutorial v2 4.11); a press opens the Shop on the shown offer's section. Offers never pop up
--   by themselves (designer, 2026-10-03). The challenge and the offer tile are a bit bigger than
--   the left column's tiles. The offer's picture wiggles, and a small red X on its corner hides
--   the tile for the rest of the visit (the designer, 2026-10-09: "a small dismiss button ... to
--   get rid of it"; the Shop still sells it).
-- - The tutorial hides the challenge, the offer tile, Invite and Plus until its soft part
--   (Steps.Reveal: Challenge, Offer, Invite, Plus); each pops in as it comes back. The soft
--   part's click-once "!" sits on the challenge and the offer tile (setFresh).
-- - Bottom left, just right of the money HUD: Invite (Roblox's invite prompt, carrying the
--   invite's launch data, Progression/Social.launchData) and Roblox Plus (the Store's Plus
--   prompt; hidden for members and where the shop does not offer Plus).
-- - Top left, right of the rank HUD: the Settings gear (GUI lane, C10; SettingsMenu).
-- Sizes in Config.UI.Corners; words in Strings.Corners. Not gamepad stops while the player walks
-- (a selected button takes the left stick from walking): the D-pad's left (HubPad, designer
-- 2026-10-10) makes them stops and lands on the Daily Challenge (its picture on the
-- challenge's corner); the stick moves between them and the player list, A presses, B goes
-- back to walking (focusPad, blurPad).
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local CueThumb = require(script.Parent.CueThumb)
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local InvitePrompt = require(script.Parent.InvitePrompt)
local PadMode = require(script.Parent.PadMode)
local ItemState = require(script.Parent.ItemState)
local Menus = require(script.Parent.Menus)
local ShopCards = require(script.Parent.ShopCards)
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

-- The look of a controller's selection on a corner button: a gold outline round it (Roblox
-- draws it at the selected button's size).
local function padRing(): Frame
	local ring = Instance.new("Frame")
	ring.Name = "PadRing"
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.fromScale(1, 1)
	HudParts.corner(ring, C.PadRingCornerPx)
	local stroke = Instance.new("UIStroke")
	stroke.Color = HudParts.color(K.Colors.Gold)
	stroke.Thickness = C.PadRingPx
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = ring
	return ring
end

-- An icon button with the candy's hover, squish and bounce but no box (like the column's tiles),
-- its word across the icon's lower edge; a controller's selection outlines it in gold.
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
	button.SelectionImageObject = padRing()
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

-- The Starter Pack's picture on a tile, as the Shop's card draws it (the designer,
-- 2026-10-09): the Starter Lucky Block, the Starter Cue behind it and money in front, in the
-- icon's square (Config.UI.ShopBlocks.Pair's shares; the cue's Config.UI.Corners'). Hidden
-- until drawOffer shows it.
local function starterArt(tile: Corner): Frame
	local icon = tile.icon
	local holder = HudParts.frame(icon.Parent :: Instance, "StarterArt")
	holder.AnchorPoint = icon.AnchorPoint
	holder.Position = icon.Position
	holder.Size = icon.Size
	holder.ZIndex = icon.ZIndex
	holder.Visible = false
	local square = Instance.new("UIAspectRatioConstraint")
	square.AspectRatio = 1
	square.Parent = holder
	local pair = Config.UI.ShopBlocks.Pair
	-- A blue halo behind it all: the silver cue reads on any floor.
	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.BackgroundTransparency = 1
	glow.Image = K.Art.SoftGlow
	local tint = C.StarterGlowTint
	glow.ImageColor3 = Color3.fromRGB(tint[1], tint[2], tint[3])
	glow.ImageTransparency = C.StarterGlowTransparency
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(C.StarterGlowScale, C.StarterGlowScale)
	glow.ZIndex = icon.ZIndex - 1
	glow.Parent = holder
	local function share(object: GuiObject, at: { number }, z: number)
		object.AnchorPoint = Vector2.new(0.5, 0.5)
		object.Position = UDim2.fromScale(at[1], at[2])
		object.Size = UDim2.fromScale(at[3], at[3])
		object.ZIndex = icon.ZIndex + z
	end
	local cue = CueThumb.new(holder, Config.Shop.StarterCue)
	share(cue, C.StarterCue, 0)
	local kind = (Config.LuckyBlocks.Kinds :: any)[Config.Shop.StarterBlock]
	local block = HudParts.icon(holder, "StarterPack", "Block")
	block.Image = if kind then kind.Icon else ""
	share(block, pair.StarterBlock, 1)
	share(HudParts.icon(holder, "CashStack", "Cash"), pair.StarterCash, 2)
	HudParts.onLit(tile.button, function(lit: boolean)
		UIAnim.sunRays(holder, lit)
	end)
	return holder
end

local function showDot(dot: Frame?, on: boolean)
	if dot == nil or dot.Visible == on then
		return
	end
	if on then
		UIAnim.popIn(dot)
	else
		dot.Visible = false
	end
end

-- The Starter Pack's worth over its price, in whole times ("x2 VALUE!"): its money at the
-- smallest money pack's rate plus its block at the Rare restock price (where paid random items
-- are restricted: more money, no block); its cue and its hour of 2x money are not counted.
local function starterTimes(price: number, restricted: boolean): number
	local list: any = Config.Products.List
	local pack = list.Pack1
	local money = if restricted
		then Config.Shop.StarterRestrictedMoney
		else Config.Shop.StarterMoney
	local worth = money / pack.Money * pack.Robux
		+ (if restricted then 0 else list.RestockRare.Robux)
	return if price > 0 then math.max(1, math.floor(worth / price)) else 1
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
	self.challengeDue = true -- its "!" until pressed (refreshChallengeDot)
	self.freshOn = {} :: { [string]: boolean }
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
	HudParts.padKey(
		HudParts.candyParts(self.challenge.button).body,
		PadMode.key(Config.Input.Gamepad.Hub.Side) :: Enum.KeyCode,
		K.PadKey.Corner
	)
	self.padFocused = false
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
	self.offerSpecs = {
		{ key = "StarterPack", section = "Offer", icon = "StarterPack", words = W.Starter },
		{ key = "VipOffer", section = "Vip", icon = "Vip", words = W.VipName },
	}
	self.openOffers = {} :: { { spec: any, endsAt: number } }
	self.offerIndex = 1
	self.offerKey = nil :: string? -- the offer drawn on the tile now
	self.offerFlippedAt = os.clock()
	self.flipping = false
	local offerTile = corner(root, "Offer", "StarterPack", W.Starter, function()
		self:pressOffer()
	end)
	offerTile.button.Visible = false
	self.starterArt = starterArt(offerTile)
	-- Its picture wiggles now and then (the designer, 2026-10-09).
	UIAnim.shake(offerTile.icon, "Wiggle")
	UIAnim.shake(self.starterArt, "Wiggle")
	-- The X: away for the rest of the visit (it comes back on the next join while still open).
	self.offerDismissed = false
	local dismiss = HudParts.candy(root, "", function()
		UISound.play("Click")
		self.offerDismissed = true
		self:refreshOffers()
	end, "Red", "X")
	dismiss.Name = "OfferDismiss"
	dismiss.Selectable = false
	dismiss.AnchorPoint = Vector2.new(0.5, 0.5)
	dismiss.Visible = false
	HudParts.setMinHit(dismiss, C.DismissHitPx)
	self.offerDismiss = dismiss
	local offerBody = HudParts.candyParts(offerTile.button).body
	-- The deal under the name, as a shop sign (the designer, 2026-10-09): the deal in rainbow
	-- ("x2 VALUE!", "50% OFF!"), then "ONLY" and the price in Robux green.
	local deal = HudParts.text(offerBody, "Deal", C.DealPx, "")
	deal.TextWrapped = false
	deal.AnchorPoint = Vector2.new(0.5, 0.5)
	deal.TextColor3 = Color3.new(1, 1, 1)
	deal.ZIndex = 4
	UIAnim.rainbow(deal)
	local price = HudParts.text(offerBody, "Price", C.PricePx, "")
	price.RichText = true
	price.TextWrapped = false
	price.AnchorPoint = Vector2.new(0.5, 0.5)
	price.ZIndex = 4
	self.offerDeal, self.offerPrice = deal, price
	-- The countdown on a gold pill over the tile's top-left corner (as the Shop tile's).
	local timerPill = HudParts.pill(offerBody, "Timer", HudParts.tone("Gold"))
	timerPill.AnchorPoint = Vector2.new(0.5, 0.5)
	timerPill.ZIndex = 5
	local timer = HudParts.text(timerPill, "Time", C.TimerPx, "")
	timer.AutoLocalize = false -- a time
	timer.TextWrapped = false
	timer.Size = UDim2.fromScale(1, 1)
	timer.ZIndex = 6
	self.offerTile, self.offerTimer, self.offerTimerPill = offerTile, timer, timerPill
	-- Rainbow sun rays turning behind it (as Free Reward's gold ones), under every tile.
	local rays = Instance.new("ImageLabel")
	rays.Name = "OfferRays"
	rays.BackgroundTransparency = 1
	rays.Image = K.Art.Rays
	rays.ImageTransparency = C.OfferRaysTransparency
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.ZIndex = 0
	rays.Visible = false
	rays.Parent = root
	UIAnim.rainbow(rays)
	UIAnim.loop(rays, function(clock: number)
		rays.Rotation = (clock * K.Motion.RaysDegreesPerSecond) % 360
	end)
	self.offerRays = rays

	-- The soft part's click-once "!" (setFresh): a red dot on a tile's top-right corner.
	self.fresh = {} :: { [string]: Frame }
	for key, tile: any in { Challenge = self.challenge, Offer = offerTile } do
		local dot =
			HudParts.pill(HudParts.candyParts(tile.button).body, "New", HudParts.tone("Red"))
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		-- The offer's sits left of its X (the corner is the X's).
		local at = if key == "Offer" then C.OfferNewAt else { 0.86, 0.1 }
		dot.Position = UDim2.fromScale(at[1], at[2])
		dot.ZIndex = 6
		dot.Visible = false
		local words = HudParts.text(dot, "Words", C.WordPx + 1, Strings.Tutorial.New)
		words.TextWrapped = false
		words.Size = UDim2.fromScale(1, 1)
		words.ZIndex = 7
		self.fresh[key] = dot
	end
	self:refreshChallengeDot()
	-- The tutorial's anchors: the soft part's glows sit behind these.
	TutorialAnchors.set("Challenge", self.challenge.button)
	TutorialAnchors.set("Offer", offerTile.button)
	TutorialAnchors.set("OfferDismiss", self.offerDismiss) -- its X (Studio QA presses it)
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
		C.ChallengeOn and not self.challengeHidden and not TutorialAnchors.hidden("Challenge")
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
	self.freshOn[key] = on
	if key == "Challenge" then
		self:refreshChallengeDot()
		return
	end
	showDot(self.fresh[key], on)
end

--- The challenge's "!": while today's challenge waits (the designer, 2026-10-09: a nudge to do
--- it), or the soft part's click-once. Daily challenges are not built yet, so "waits" means
--- not pressed this session; their service will say when today's is done.
function HubCorners.refreshChallengeDot(self: any)
	showDot(self.fresh.Challenge, self.challengeDue or self.freshOn.Challenge == true)
end

-- Draw `spec`'s icon, word and press on the offer tile.
local function drawOffer(self: any, spec: any)
	self.offerKey = spec.key
	local starter = spec.key == "StarterPack"
	HudParts.setIcon(self.offerTile.icon, if starter then nil else spec.icon)
	self.starterArt.Visible = starter
	self.offerTile.word.Text = spec.words
	-- The live prices (Roblox's, else Config's), as the Shop shows them.
	local shop = ItemState.shop()
	local state: any = if type(shop) == "table" then shop else {}
	local products = if type(state.products) == "table" then state.products else {}
	local robux = ShopParts.robuxOf(products[spec.key], spec.key)
	if starter then
		self.offerDeal.Text = W.Value:format(starterTimes(robux, state.restricted == true))
	else
		local full = ShopParts.robuxOf(products.Vip, "Vip")
		local off = if full > 0 then math.floor((1 - robux / full) * 100 + 0.5) else 0
		self.offerDeal.Text = W.Off:format(off)
	end
	self.offerPrice.Text = W.Only:format(
		Color3.fromRGB(C.PriceColor[1], C.PriceColor[2], C.PriceColor[3]):ToHex(),
		ShopCards.robuxText(robux)
	)
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
			self:sizeTimerPill()
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
	local allowed = not self.challengeHidden
		and not TutorialAnchors.hidden("Offer")
		and not self.offerDismissed
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
	local drawn = false
	if shown and shown.spec.key ~= self.offerKey and not self.flipping then
		drawOffer(self, shown.spec)
		drawn = true
	end
	if setShown(self, self.offerTile.button, shown ~= nil) or drawn then
		self:layout()
	end
	if shown then
		self.offerTimer.Text = ShopParts.timeLeft(shown.endsAt - now) -- "6d 4h", "2:59:12"
		self:sizeTimerPill()
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
	-- The challenge's and the offer's words: bigger than the left column's (the designer,
	-- 2026-10-09).
	local bigWordPx = if short then C.ShortBigWordPx else C.BigWordPx
	-- Far enough in from the right edge for the widest word under the two tiles.
	local font = (Enum.Font :: any)[K.Font]
	local function wide(text: string, px: number): number
		local plain = string.gsub(text, "<[^>]*>", "")
		return TextService:GetTextSize(plain, px, font, Vector2.new(2000, 200)).X
	end
	local widest = wide(W.Challenge, bigWordPx)
	for _, spec in self.offerSpecs do
		widest = math.max(widest, wide(spec.words, bigWordPx))
	end
	widest = math.max(
		widest,
		wide(self.offerDeal.Text, if short then C.ShortDealPx else C.DealPx),
		wide(self.offerPrice.Text, if short then C.ShortPricePx else C.PricePx)
	)
	local right = math.max(C.ChallengeRightPx, math.ceil((widest - big) / 2) + C.WordEdgePx)
	local ch = self.challenge
	ch.button.AnchorPoint = Vector2.new(1, 0.5)
	ch.button.Size = UDim2.fromOffset(big, big)
	ch.button.Position = UDim2.new(1, -right, C.ChallengeYShare, 0)
	-- The word is wider than the icon: it overhangs both sides.
	ch.word.Size = UDim2.fromOffset(big * 2, bigWordPx + 4)
	HudParts.setTextSize(ch.word, bigWordPx)

	-- The offer tile under the challenge, centred on it; its deal and price under its word.
	local offerPx = if short then C.ShortOfferPx else C.OfferPx
	local timerPx = if short then C.ShortTimerPx else C.TimerPx
	local dealPx = if short then C.ShortDealPx else C.DealPx
	local pricePx = if short then C.ShortPricePx else C.PricePx
	local centreX = -right - big / 2
	-- With the challenge off (C.ChallengeOn) the offer takes its place.
	local offerY = if C.ChallengeOn
		then size.Y * C.ChallengeYShare + big / 2 + bigWordPx + C.OfferGapPx + offerPx / 2
		else size.Y * C.ChallengeYShare
	local offer = self.offerTile
	offer.button.AnchorPoint = Vector2.new(0.5, 0.5)
	offer.button.Size = UDim2.fromOffset(offerPx, offerPx)
	offer.button.Position = UDim2.new(1, round(centreX), 0, round(offerY))
	offer.word.Size = UDim2.fromOffset(round(offerPx * 2.4), bigWordPx + 4)
	HudParts.setTextSize(offer.word, bigWordPx)
	local wordBottom = 0.92 * offerPx + bigWordPx / 2 + 2
	self.offerDeal.Position = UDim2.fromOffset(round(offerPx / 2), round(wordBottom + dealPx / 2))
	self.offerDeal.Size = UDim2.fromOffset(round(offerPx * 2.4), dealPx + 4)
	HudParts.setTextSize(self.offerDeal, dealPx)
	self.offerPrice.Position =
		UDim2.fromOffset(round(offerPx / 2), round(wordBottom + dealPx + 2 + pricePx / 2))
	self.offerPrice.Size = UDim2.fromOffset(round(offerPx * 2.4), pricePx + 4)
	HudParts.setTextSize(self.offerPrice, pricePx)
	self.timerPx, self.timerPillPx = timerPx, if short then C.ShortTimerPillPx else C.TimerPillPx
	self.offerTimerPill.Position = UDim2.fromScale(C.TimerPillAt[1], C.TimerPillAt[2])
	HudParts.setTextSize(self.offerTimer, timerPx, timerPx)
	self:sizeTimerPill()
	local raysPx = round(offerPx * C.OfferRaysShare)
	self.offerRays.Size = UDim2.fromOffset(raysPx, raysPx)
	self.offerRays.Position = offer.button.Position
	self.offerRays.Visible = offer.button.Visible
	-- The X on the tile's top-right corner.
	local dismissPx = if short then C.ShortDismissPx else C.DismissPx
	self.offerDismiss.Size = UDim2.fromOffset(dismissPx, dismissPx)
	self.offerDismiss.Position = UDim2.new(
		1,
		round(centreX + offerPx / 2 - dismissPx * C.DismissInShare),
		0,
		round(offerY - offerPx / 2 + dismissPx * C.DismissInShare)
	)
	self.offerDismiss.Visible = offer.button.Visible
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
		self:blurPad()
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

--- The countdown's pill as wide as its words.
function HubCorners.sizeTimerPill(self: any)
	local timerPx, pillH = self.timerPx or C.TimerPx, self.timerPillPx or C.TimerPillPx
	local width = TextService:GetTextSize(
		self.offerTimer.Text,
		timerPx,
		(Enum.Font :: any)[K.Font],
		Vector2.new(400, 100)
	).X
	self.offerTimerPill.Size = UDim2.fromOffset(math.max(pillH * 2, math.ceil(width) + 14), pillH)
end

function HubCorners.isShown(self: any): boolean
	return self.showing
end

-- The corner buttons a controller may land on while the right side is focused, shown ones only.
function HubCorners.padStops(self: any): { GuiObject }
	local stops: { GuiObject } = {}
	for _, button in
		{
			self.challenge.button,
			self.offerTile.button,
			self.offerDismiss,
			self.gearTile.button,
			self.inviteTile.button,
			self.plusTile.button,
		}
	do
		if button.Visible then
			table.insert(stops, button)
		end
	end
	return stops
end

--- The controller onto the corner buttons (HubPad, the D-pad's left): they become stops and the
--- selection lands on the Daily Challenge (or the first one shown). False when none shows.
function HubCorners.focusPad(self: any): boolean
	if not self.showing then
		return false
	end
	local stops = self:padStops()
	if #stops == 0 then
		return false
	end
	for _, button in stops do
		button.Selectable = true
	end
	self.padFocused = true
	GuiService.SelectedObject = stops[1]
	return true
end

--- Back to walking: the corner buttons stop being stops, a selection on one is dropped.
function HubCorners.blurPad(self: any)
	if not self.padFocused then
		return
	end
	self.padFocused = false
	local selected = GuiService.SelectedObject
	for _, button in
		{
			self.challenge.button,
			self.offerTile.button,
			self.offerDismiss,
			self.gearTile.button,
			self.inviteTile.button,
			self.plusTile.button,
		}
	do
		button.Selectable = false
		if selected == button then
			GuiService.SelectedObject = nil
		end
	end
end

--- Whether the controller is on the corner buttons now (focusPad).
function HubCorners.padFocusedOn(self: any, object: Instance?): boolean
	return self.padFocused and object ~= nil and object:IsDescendantOf(self.root)
end

--- The Daily Challenge: a "Soon" bubble beside it (a press, or the D-pad's down).
--- The offer tile's press: the Shop on the shown offer's section.
function HubCorners.pressOffer(self: any)
	local shown = self.openOffers[self.offerIndex]
	if shown then
		UISound.play("Click")
		TutorialAnchors.notePress("Offer")
		Menus.open("Shop", shown.spec.section)
	end
end

function HubCorners.pressChallenge(self: any)
	if not C.ChallengeOn then
		-- Off for the release: the D-pad's down opens the offer instead, when it shows.
		if self.offerTile.button.Visible then
			self:pressOffer()
		end
		return
	end
	if not self.showing then
		return
	end
	UISound.play("Click")
	self.challengeDue = false
	self:refreshChallengeDot()
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
