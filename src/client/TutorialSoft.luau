--!strict
-- TutorialSoft: tutorial v2's soft part on the client (docs/prompts/TUTORIAL_V2_PROMPT.md 4.5
-- steps 10-14 and 4.6): encouraged, never forced. After the guided chain every icon pops in
-- (Tutorial's stagger), and then:
--
-- - Each new icon wears a click-once "!" until it is clicked once: the Shop and Free Reward
--   tiles, the offer tile, the money "+", and the Daily Challenge once challenges are built
--   (Config.Tutorial.Soft.ChallengeBuilt). Free Reward stands out most: it also glows and
--   bounces. After game 2 the Shop glows too, until it is opened.
-- - "Win a Match 0/1", top centre (under the top banner while one shows), until a win: then
--   "1/1", "Done!", and the daily win track takes its place (WinTrack waits meanwhile). Only in
--   a quiet lobby (Progression.quiet).
-- - The Daily Rewards popup, once, as the lobby goes quiet after the icons (day 1 to claim,
--   day 7's prize on show; DailyRewardsMenu); then the invite popup, once: a small card,
--   Invite and a big X.
-- - Free Reward's first open lands on Group (FreeRewardMenu); its join and favorite get a gold
--   ring and a light sweeping over them until they are pressed (or claimed), its like line a
--   ring until the menu closes after it was on the page.
-- - Play Global wears the gold ring, its spawn pill staying up (Main, MatchBar), until it is
--   pressed.
-- - After game 2, the first-win Rare block's hotbar slot wears the gold ring once its timer is
--   done (its READY! shows), until it is taken in hand.
--
-- Who gets it: a player in the soft part, or past it (its icons came out: the Icons moment). A
-- skipper (TutorialWhy "Skip") gets only the "!" dots: the first click on each new icon is a
-- first-time hint for everyone (4.8); the rest is the soft tutorial they skipped.
-- What was clicked is saved as one-time moments (Tutorial/Steps.Seen, the TutorialSeen mask):
-- the client reports each (TutorialEvent "Seen"), the server checks the name. Sizes and
-- timings in Config.Tutorial.Soft, words in Strings.Tutorial.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Strings = require(Shared.Strings)
local FreeParts = require(script.Parent.FreeParts)
local HudParts = require(script.Parent.HudParts)
local InvitePrompt = require(script.Parent.InvitePrompt)
local ItemState = require(script.Parent.ItemState)
local LuckyClient = require(script.Parent.LuckyClient)
local Menus = require(script.Parent.Menus)
local Progression = require(script.Parent.Progression)
local RewardsParts = require(script.Parent.RewardsParts)
local TutorialAnchors = require(script.Parent.TutorialAnchors)
local TutorialOverlay = require(script.Parent.TutorialOverlay)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local S = Config.Tutorial.Soft
local O = Config.Tutorial.Overlay
local Copy = Strings.Tutorial
local player = Players.LocalPlayer

local TutorialSoft = {}

-- The tiles with a click-once "!" (Progression.setFresh's names).
local FRESH = { "Shop", "FreeReward", "Offer", "Money", "Challenge" }
-- Free Reward's frames with the once-only ring (TutorialAnchors' names).
local RINGED = { "Group", "Favorite", "Like" }
-- A press (TutorialAnchors.notePress) and the moment it is.
local PRESSES: { [string]: string } = {
	Challenge = "Challenge",
	Offer = "Offer",
	Money = "Money",
	GlobalQueue = "PlayGlobal",
	Group = "Group",
	Favorite = "Favorite",
}

local gui: ScreenGui
local quest: TextLabel
local popup: Frame
local popupInvite: TextButton
local popupClose: TextButton
-- Built (start), and the fail-safe tripped (nothing more shows this session).
local started = false
local stopped = false

-- What was clicked this session, before the server's mask says so (its "!" goes at once), and
-- when it was last reported (reported again until the mask has it).
local clicked: { [string]: boolean } = {}
local reportedAt: { [string]: number } = {}

local freshOn: { [string]: boolean } = {}
type Glow = {
	object: GuiObject,
	label: ImageLabel,
	rays: ImageLabel,
	pulse: UIAnim.Handle,
	spin: UIAnim.Handle,
}
local glows: { [string]: Glow } = {}
type Ring = { clip: Frame, ring: Frame, stroke: UIStroke }
local rings: { [string]: Ring } = {}
local freePulse: UIAnim.Handle? = nil -- Free Reward breathing (its tile's)
local shinedAt = 0
local likeShown = false

-- The quest: "on" (Win a Match 0/1), "count" (1/1), "done" (Done!), or "off".
local questPhase = "off"
local questAt = 0
local questSeen = false -- it showed this session (so its Done! is shown)

-- The invite popup: when the lobby went quiet for it (os.clock), and whether it is up.
local quietSince: number? = nil
local popupUp = false

local function step(): string
	local s = player:GetAttribute("TutorialStep")
	return if type(s) == "string" then s else ""
end

-- A soft-part player: in the soft part now, or past it (its icons came out).
local function soft(): boolean
	return not stopped and (step() == "Soft" or TutorialAnchors.seen("Icons"))
end

-- A skipper: the "!" dots only.
local function skipper(): boolean
	return not stopped and player:GetAttribute("TutorialWhy") == "Skip"
end

local function seen(name: string): boolean
	return clicked[name] == true or TutorialAnchors.seen(name)
end

local function report(kind: string, data: any?)
	Net.get("TutorialEvent"):FireServer(kind, data)
end

-- One-time moment `name` happened (a click, a popup shown): its "!" or glow goes at once and
-- the server is told.
local function click(name: string)
	if not (soft() or skipper()) or TutorialAnchors.seen(name) or clicked[name] then
		return
	end
	clicked[name] = true
	reportedAt[name] = os.clock()
	report("Seen", name)
end

local function phone(): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and math.min(camera.ViewportSize.X, camera.ViewportSize.Y) < O.PhoneBelowPx
end

---------------------------------------------------------------------------------------------
-- Glows and rings
---------------------------------------------------------------------------------------------

-- The house glow behind a candy button (anchor `name`): gold rays turning slowly round a
-- breathing soft glow, under the button's own face, or on `under` (a layer under the whole
-- column, so the rays never cover the next tile) where the button is; `want` false takes it
-- away.
local function setGlow(name: string, want: boolean, under: GuiObject?)
	local object = if want then TutorialAnchors.get(name) else nil
	local g: Glow? = glows[name]
	if g and g.object ~= object then
		g.pulse.stop()
		g.spin.stop()
		g.rays:Destroy()
		g.label:Destroy()
		glows[name] = nil
		g = nil
	end
	if object == nil then
		return
	end
	if g == nil then
		local function image(art: string, z: number): ImageLabel
			local made = Instance.new("ImageLabel")
			made.Name = "TutorialGlow"
			made.BackgroundTransparency = 1
			made.Image = art
			made.ImageColor3 = HudParts.tone("Gold")
			made.AnchorPoint = Vector2.new(0.5, 0.5)
			made.Position = UDim2.fromScale(0.5, 0.5)
			made.ZIndex = if under then 1 else z -- under the button's own face and words
			made.Parent = under or object
			return made
		end
		local rays = image(Config.UI.Kit.Art.Rays, -3)
		rays.ImageTransparency = S.GlowRaysTransparency
		local label = image(Config.UI.Kit.Art.SoftGlow, -2)
		local made: Glow = {
			object = object,
			label = label,
			rays = rays,
			pulse = UIAnim.glowPulse(label, S.GlowLow, S.GlowHigh, S.GlowSeconds),
			spin = UIAnim.spin(rays),
		}
		glows[name] = made
		g = made
	end
	-- Square, from the button's short side (a wide pill too).
	local glow = g :: Glow
	if under then
		local centre = object.AbsolutePosition + object.AbsoluteSize / 2 - under.AbsolutePosition
		local at = UDim2.fromOffset(centre.X, centre.Y)
		local shows = TutorialAnchors.showing(name)
		glow.label.Position, glow.rays.Position = at, at
		glow.label.Visible, glow.rays.Visible = shows, shows
	end
	local side = math.min(object.AbsoluteSize.X, object.AbsoluteSize.Y)
	local glowFit = UDim2.fromOffset(side * S.GlowScale, side * S.GlowScale)
	if glow.label.Size ~= glowFit then
		glow.label.Size = glowFit
		glow.rays.Size = UDim2.fromOffset(side * S.GlowRaysScale, side * S.GlowRaysScale)
	end
end

-- A gold ring round anchor `name`, on this module's screen and clipped to the page it scrolls
-- in. `shape`: "Card" (just inside its edge, so a page's edge never cuts it), "Pill" (round
-- it, round ends: a wide pill a round glow would hardly show round) or "Box" (round it). A line
-- of words gets it round its words. Answers whether it shows on its page.
local function setRing(name: string, want: boolean, clock: number, shape: string): boolean
	local object = if want and TutorialAnchors.showing(name) then TutorialAnchors.get(name) else nil
	local r = rings[name]
	if object == nil then
		if r then
			r.clip.Visible = false
		end
		return false
	end
	if r == nil then
		local clip = Instance.new("Frame")
		clip.Name = name .. "Ring"
		clip.BackgroundTransparency = 1
		clip.ClipsDescendants = true
		clip.Parent = gui
		local ring = Instance.new("Frame")
		ring.Name = "Ring"
		ring.BackgroundTransparency = 1
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Parent = clip
		local corner = HudParts.corner(ring, O.RingCornerPx)
		if shape == "Pill" then
			corner.CornerRadius = UDim.new(0.5, 0)
		end
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = S.RingThicknessPx
		stroke.Color = HudParts.color(O.RingColor)
		stroke.Parent = ring
		r = { clip = clip, ring = ring, stroke = stroke }
		rings[name] = r
	end
	local made = r :: Ring
	-- Places in this layer: AbsolutePositions less the layer's own (right with a phone's notch).
	local page = object:FindFirstAncestorWhichIsA("ScrollingFrame")
	local base = if page then page.AbsolutePosition else gui.AbsolutePosition
	local clipAt = base - gui.AbsolutePosition
	local clipSize = if page then page.AbsoluteSize else gui.AbsoluteSize
	made.clip.Position = UDim2.fromOffset(clipAt.X, clipAt.Y)
	made.clip.Size = UDim2.fromOffset(clipSize.X, clipSize.Y)
	local size = object.AbsoluteSize
	local words = object:IsA("TextLabel")
	if words then
		size = Vector2.new(
			math.min(size.X, (object :: TextLabel).TextBounds.X),
			math.min(size.Y, (object :: TextLabel).TextBounds.Y)
		)
	end
	local pad = if shape == "Card" and not words then -S.RingThicknessPx else S.RingThicknessPx * 2
	local centre = object.AbsolutePosition + object.AbsoluteSize / 2 - base
	made.ring.Position = UDim2.fromOffset(centre.X, centre.Y)
	made.ring.Size = UDim2.fromOffset(size.X + pad * 2, size.Y + pad * 2)
	local wave = 0.5 + 0.5 * math.sin(2 * math.pi * clock / S.GlowSeconds)
	made.stroke.Transparency = S.RingLow + (S.RingHigh - S.RingLow) * wave
	made.clip.Visible = true
	-- Seen only while its middle is on the page (not scrolled away).
	return centre.X >= 0 and centre.Y >= 0 and centre.X <= clipSize.X and centre.Y <= clipSize.Y
end

---------------------------------------------------------------------------------------------
-- The quest
---------------------------------------------------------------------------------------------

local BANNER = TutorialOverlay.guiTarget("Banner", 0)

local function placeQuest()
	local px = if phone() then S.QuestPhoneTextPx else S.QuestTextPx
	HudParts.setTextSize(quest, px)
	-- Centred on the play area (in from a phone's notch), under Roblox's top bar or a banner.
	local play = TutorialOverlay.areas().play
	local top = play.y + S.QuestTopGapPx
	local centre, size = BANNER()
	if centre and size then
		top = math.max(top, centre.Y + size.Y / 2 + S.QuestTopGapPx)
	end
	quest.Position = UDim2.fromOffset(play.x + play.w / 2, top)
	quest.Size = UDim2.fromOffset(play.w - 2 * S.QuestTopGapPx, px + 8)
end

local function showQuest(text: string, slam: boolean)
	quest.Text = text
	placeQuest()
	if slam then
		quest.Visible = true
		UIAnim.slam(quest, nil, { shake = "Nudge" })
	elseif not quest.Visible then
		UIAnim.popIn(quest)
	end
end

-- Every frame: the quest's words and phase.
local function updateQuest(quiet: boolean, now: number)
	local on = soft() and TutorialAnchors.seen("Quest") and not TutorialAnchors.seen("QuestDone")
	if questPhase == "off" or questPhase == "on" then
		if on then
			questPhase = "on"
		elseif questPhase == "on" and TutorialAnchors.seen("QuestDone") then
			-- Won: the count fills, then Done!, once the lobby is quiet.
			questPhase = "count"
			questAt = -1
		else
			questPhase = "off"
		end
	end
	if not quiet then
		quest.Visible = false
		if questAt >= 0 and questPhase ~= "on" and questPhase ~= "off" then
			questAt = -1 -- the count and Done! start again once it is quiet
			questPhase = "count"
		end
		return
	end
	if questPhase == "on" then
		questSeen = true
		local text = Copy.Quest:format(0, S.QuestWins)
		if not quest.Visible or quest.Text ~= text then
			showQuest(text, false)
		else
			placeQuest()
		end
	elseif questPhase == "count" then
		if not questSeen then
			questPhase = "off" -- won without it ever showing here: nothing to finish
		elseif questAt < 0 then
			questAt = now
			showQuest(Copy.Quest:format(S.QuestWins, S.QuestWins), false)
			UIAnim.thump(quest)
		elseif now - questAt >= S.QuestCountSeconds then
			questPhase = "done"
			questAt = now
			showQuest(Copy.QuestDone, true)
		else
			placeQuest()
		end
	elseif questPhase == "done" then
		if now - questAt >= S.QuestDoneSeconds then
			questPhase = "off"
			UIAnim.popOut(quest)
		else
			placeQuest()
		end
	else
		quest.Visible = false
	end
end

---------------------------------------------------------------------------------------------
-- The invite popup
---------------------------------------------------------------------------------------------

local function closePopup()
	if not popupUp then
		return
	end
	popupUp = false
	ContextActionService:UnbindAction("TutorialInviteClose")
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(popup) then
		GuiService.SelectedObject = nil
	end
	UIAnim.popOut(popup)
end

-- Lay the card out at its width (a phone's narrower), each line as tall as its words.
local function layoutPopup()
	local w = if phone() then S.InvitePhoneWidthPx else S.InviteWidthPx
	local pad = S.InvitePadPx
	local inner = w - 2 * pad
	local y = pad
	local function line(name: string, px: number)
		local label = popup:FindFirstChild(name) :: TextLabel
		HudParts.setTextSize(label, px)
		local fit = TextService:GetTextSize(
			label.Text,
			px,
			HudParts.measureFont(label),
			Vector2.new(inner, 10000)
		)
		label.Position = UDim2.fromOffset(pad, y)
		label.Size = UDim2.fromOffset(inner, fit.Y + 4)
		y += fit.Y + 4 + S.InviteGapPx
	end
	line("Title", if phone() then S.InvitePhoneTitlePx else S.InviteTitlePx)
	local block = popup:FindFirstChild("Block") :: ImageLabel
	block.Position = UDim2.fromOffset(w / 2, y + S.InviteBlockPx / 2)
	block.Size = UDim2.fromOffset(S.InviteBlockPx, S.InviteBlockPx)
	y += S.InviteBlockPx + S.InviteGapPx
	line("Body", S.InviteBodyPx)
	line("When", S.InviteSmallPx)
	local buttonH = math.max(S.InviteButtonPx * 2, Config.UI.Menu.Frame.TouchMinPx)
	popupInvite.Position = UDim2.fromOffset(w / 2, y + buttonH / 2)
	popupInvite.Size = UDim2.fromOffset(math.floor(w * S.InviteButtonShare), buttonH)
	HudParts.setButtonTextSize(popupInvite, S.InviteButtonPx)
	y += buttonH + pad
	popupClose.Position = UDim2.fromOffset(w - S.InviteCloseInsetPx, S.InviteCloseInsetPx)
	popupClose.Size = UDim2.fromOffset(S.InviteClosePx, S.InviteClosePx)
	popup.Size = UDim2.fromOffset(w, y)
end

local function openPopup()
	popupUp = true
	click("Invite") -- shown once ever (the server logs InviteShown)
	layoutPopup()
	popup.Visible = true
	UIAnim.slam(popup, nil, { shake = "Nudge" })
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = popupInvite
	end
	-- A gamepad's B closes it.
	ContextActionService:BindActionAtPriority(
		"TutorialInviteClose",
		function(_, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin and popupUp then
				report("InvitePopup", "Closed")
				closePopup()
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.ButtonB
	)
end

-- The Daily Rewards popup: once, after the icons are out and the lobby has been quiet a
-- moment (before the invite popup, which waits for it to close).
local dailySince: number? = nil
local function updateDaily(quiet: boolean, now: number)
	local due = step() == "Soft" and soft() and TutorialAnchors.seen("Icons") and not seen("Daily")
	if not due or not quiet then
		dailySince = nil
		return
	end
	dailySince = dailySince or now
	if now - (dailySince :: number) >= S.DailyAfterSeconds then
		click("Daily")
		Menus.open("DailyRewards")
	end
end

-- Every frame: once, after the icons are out and the lobby has been quiet a moment.
local function updatePopup(quiet: boolean, now: number)
	if popupUp then
		if not quiet then
			closePopup()
		end
		return
	end
	local due = step() == "Soft"
		and soft()
		and TutorialAnchors.seen("Icons")
		and seen("Daily")
		and not seen("Invite")
	if not due or not quiet then
		quietSince = nil
		return
	end
	quietSince = quietSince or now
	if now - (quietSince :: number) >= S.InviteAfterSeconds then
		openPopup()
	end
end

---------------------------------------------------------------------------------------------
-- Every frame
---------------------------------------------------------------------------------------------

--- Whether Play Global should stay up and glow (the soft part, until it is pressed): Main
--- keeps the spawn pill up for it.
function TutorialSoft.wantsGlobal(): boolean
	-- After the invite popup was answered: it comes first.
	return step() == "Soft" and soft() and not seen("PlayGlobal") and seen("Invite") and not popupUp
end

--- Whether the Win a Match quest is up (or finishing): the daily win track waits for it.
function TutorialSoft.questOn(): boolean
	return soft()
		and (
			(TutorialAnchors.seen("Quest") and not TutorialAnchors.seen("QuestDone"))
			or questPhase == "count"
			or questPhase == "done"
		)
end

--- Tutorial's update, every frame (under its fail-safe).
function TutorialSoft.update(_dt: number)
	if stopped or not started then
		return
	end
	local now = os.clock()
	local on = soft()
	local dots = on or skipper()
	local over = step() == "" -- game 2 is over (or the tutorial ended another way)

	-- Reports the server has not answered yet go again.
	for name, at in reportedAt do
		if TutorialAnchors.seen(name) then
			reportedAt[name] = nil
		elseif now - at >= Config.Tutorial.Timing.ReportAgainSeconds * 3 then
			reportedAt[name] = now
			report("Seen", name)
		end
	end

	-- Opening a menu is clicking its tile.
	local menu = Menus.current()
	if menu == "Shop" or menu == "FreeReward" then
		click(menu)
	end
	-- Free Reward's frames: a claimed join or favorite needs no ring; the like line's ring
	-- goes once the menu closes after it showed.
	local rewards = ItemState.rewards()
	if type(rewards) == "table" then
		for _, key in { "Group", "Favorite" } do
			local view = rewards[string.lower(key)]
			if type(view) == "table" and view.claimed == true then
				click(key)
			end
		end
	end
	if likeShown and menu ~= "FreeReward" then
		click("Like")
	end

	-- The click-once "!".
	for _, item in FRESH do
		local want = dots and not seen(item) and (item ~= "Challenge" or S.ChallengeBuilt)
		if want ~= (freshOn[item] == true) then
			freshOn[item] = want
			Progression.setFresh(item, want)
		end
	end

	-- The glows: Free Reward (and its bounce), the Shop after game 2, Play Global, the Rare
	-- block's slot once it is ready.
	local column = TutorialAnchors.get("ColumnRays")
	local free = on and not seen("FreeReward")
	setGlow("FreeReward", free, column)
	local breathe = free and TutorialAnchors.showing("FreeReward")
	if breathe and freePulse == nil then
		local tile = TutorialAnchors.get("FreeReward")
		if tile then
			freePulse = UIAnim.pulse(tile, S.BounceScale, S.BounceSeconds)
		end
	elseif not breathe and freePulse then
		freePulse.stop()
		freePulse = nil
	end
	setGlow("Shop", on and over and not seen("Shop"), column)
	setRing("GlobalQueue", TutorialSoft.wantsGlobal(), now, "Pill")
	local readyWanted = on and over and not seen("Ready")
	local slot = if readyWanted then LuckyClient.readySlot("Rare") else nil
	for i = 1, 9 do
		setRing("HotbarSlot" .. i, slot == i, now, "Box")
	end
	if slot and LuckyClient.heldKind() == "Rare" then
		click("Ready")
	end

	-- Free Reward's rings, and a light sweeping over the join and the favorite now and then.
	local shine = now - shinedAt >= S.ShineSeconds
	for _, key in RINGED do
		if setRing(key, on and not seen(key), now, "Card") then
			if key == "Like" then
				likeShown = true
			elseif shine then
				shinedAt = now
				local card = TutorialAnchors.get(key)
				if card then
					UIAnim.shine(card)
				end
			end
		end
	end

	local quiet = Progression.quiet()
	updateQuest(quiet, now)
	updateDaily(quiet, now)
	updatePopup(quiet, now)
end

--- Studio QA (TutorialClientQA "popup"): presses the invite popup's Invite (`which` "Invite")
--- or its X (anything else) as a click would; false when the popup is not up.
function TutorialSoft.qaPress(which: string): boolean
	return popupUp and HudParts.pressCandy(if which == "Invite" then popupInvite else popupClose)
end

--- Studio QA (TutorialClientQA "soft"): what the soft part shows now.
function TutorialSoft.qaState(): any
	local shownGlows, shownRings = {}, {}
	for name in glows do
		table.insert(shownGlows, name)
	end
	for name, r in rings do
		if r.clip.Visible then
			table.insert(shownRings, name)
		end
	end
	local fresh = {}
	for item, on in freshOn do
		if on then
			table.insert(fresh, item)
		end
	end
	return {
		quest = questPhase,
		questText = if quest.Visible then quest.Text else nil,
		popup = popupUp,
		glows = shownGlows,
		rings = shownRings,
		fresh = fresh,
		stopped = stopped,
	}
end

--- The fail-safe: everything the soft part shows goes, for this session.
function TutorialSoft.stop()
	stopped = true
	for item in freshOn do
		pcall(Progression.setFresh, item, false)
	end
	for name in glows do
		setGlow(name, false)
	end
	if started then
		gui.Enabled = false
	end
	pcall(ContextActionService.UnbindAction, ContextActionService, "TutorialInviteClose")
end

--- Builds the soft part's screen (the quest, the popup, the rings). Tutorial.start calls it.
function TutorialSoft.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "TutorialSoftGui"
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ResetOnSpawn = false
	gui.DisplayOrder = O.DisplayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	quest = HudParts.text(gui, "Quest", S.QuestTextPx, "")
	quest.AnchorPoint = Vector2.new(0.5, 0)
	quest.TextWrapped = false
	quest.ZIndex = 3
	quest.Visible = false

	popup = HudParts.card(gui, "InvitePopup")
	popup.AnchorPoint = Vector2.new(0.5, 0.5)
	popup.Position = UDim2.fromScale(0.5, 0.5)
	popup.ZIndex = 5
	popup.Visible = false
	local title = HudParts.text(popup, "Title", S.InviteTitlePx, Copy.InviteTitle)
	title.ZIndex = 6
	local kind = Config.Social.InviteBlock
	local block = Instance.new("ImageLabel")
	block.Name = "Block"
	block.BackgroundTransparency = 1
	block.Image = FreeParts.blockImage(kind)
	block.ScaleType = Enum.ScaleType.Fit
	block.AnchorPoint = Vector2.new(0.5, 0.5)
	block.ZIndex = 6
	block.Parent = popup
	UIAnim.bob(block)
	local body = HudParts.note(
		popup,
		"Body",
		S.InviteBodyPx,
		Copy.InviteBody:format(RewardsParts.blockName(kind))
	)
	body.TextWrapped = true
	body.ZIndex = 6
	local when = HudParts.note(popup, "When", S.InviteSmallPx, Copy.InviteWhen)
	when.TextWrapped = true
	when.ZIndex = 6
	popupInvite = HudParts.candy(popup, Copy.InviteButton, function()
		UISound.play("Click")
		TutorialAnchors.notePress("Invite")
		report("InvitePopup", "Invited")
		InvitePrompt.show(function() end)
		closePopup()
	end, "Green", "Invite")
	popupInvite.Name = "Invite"
	popupInvite.AnchorPoint = Vector2.new(0.5, 0.5)
	popupInvite.ZIndex = 7
	popupClose = HudParts.candy(popup, "", function()
		UISound.play("Click")
		report("InvitePopup", "Closed")
		closePopup()
	end, "Red", "X")
	popupClose.Name = "Close"
	popupClose.AnchorPoint = Vector2.new(0.5, 0.5)
	popupClose.ZIndex = 8

	started = true
	-- A press the soft part waits for; any Invite press is the Social funnel's Invited.
	TutorialAnchors.pressed:Connect(function(name: string)
		local moment = PRESSES[name]
		if moment then
			click(moment)
		elseif name == "Invite" and soft() then
			report("Invited")
		end
	end)
end

return TutorialSoft
