--!strict
-- LuckyClient: lucky blocks on this screen (the test build, designer 2026-10-03). It holds the
-- player's blocks (BlockState), answers the controls and asks the server (BlockRequest), and
-- ties the hotbar (LuckyHotbar), the world (LuckyWorld) and the reel (LuckyOpening) together.
--
-- Controls, the same idea on every device:
-- - Hold a block: its hotbar slot (a tap or a click), keys 1-9, or LB / RB on a gamepad to step
--   through the slots. The same slot again puts it away. Both arms hold it out (the Hold
--   animation) and everyone sees it in the hands.
-- - Throw it: a tap on the world, a left click, or R2, once it is ready. A block still counting
--   down is never thrown (the designer, 2026-10-09): it shakes in its slot and the skip popup
--   opens (VIP has no timers). Each thrown block keeps its own hold prompt. The Throw animation
--   asks the server at its Release marker.
-- - Open it: the prompt over it (LuckyWorld). The server rolls its climb and its cue; once the
--   block bursts at the top of its rise, the reel plays at the climb's odds, every time
--   (economy v5.2: a Rare block's strip is Rare 82%, Epic 16.2%...; a Rare or better cue's
--   pull cutscene follows, LuckyOpening).
-- - A Mystery (economy v5.1; since v5.2 the only block with an upgrade screen) is never held
--   as it is: its slot says OPEN! and a tap, a click or its key opens its upgrade screen
--   (MysteryReveal), where its roll turns it into a tier's block, which jumps back into its
--   slot on its timer. On a gamepad LB / RB pick its slot and R2 opens it.
-- The tutorial (Tutorial.luau) reads which slot holds a kind (slotOf), what is held and what
-- lies on the floor, and the hotbar registers its slots as anchors.
-- - The bag: the ` (or ~) key, the bag button, or L3. A click on a block in it equips it with
--   the bag still open, like Roblox's backpack (a Mystery opens its upgrade screen).
-- Lobby only: Progression hides it in a match and under the screens and menus (the bag aside).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local BlockDrop = require(Progression:WaitForChild("BlockDrop"))
local BlockOdds = require(Progression:WaitForChild("BlockOdds"))
local Catalog = require(Progression:WaitForChild("Catalog"))
local LuckyBlocks = require(Progression:WaitForChild("LuckyBlocks"))
local LuckyHotbar = require(script.Parent.LuckyHotbar)
local LuckyOpening = require(script.Parent.LuckyOpening)
local MysteryReveal = require(script.Parent.MysteryReveal)
local LuckyWorld = require(script.Parent.LuckyWorld)
local GiftDrop = require(script.Parent.GiftDrop)
local GuiQA = require(script.Parent.GuiQA)
local Menus = require(script.Parent.Menus)
local PullCutscene = require(script.Parent.PullCutscene)
local TutorialAnchors = require(script.Parent.TutorialAnchors)
local UISound = require(script.Parent.UISound)

local L = Config.LuckyBlocks
local A = L.Anim
local W = Strings.LuckyBlocks
local REASONS: { [string]: string } = W.Reasons
local NUMBER_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

type Entry = LuckyHotbar.Entry

local LuckyClient = {}

local hotbar: any = nil
local opening: any = nil
local reveal: any = nil
local aimedId: number? = nil -- a Mystery the gamepad's LB / RB picked (R2 opens its screen)
local entries: { Entry } = {}
local heldId: number? = nil
local liveIds: { [number]: boolean } = {}
local reveals: { any } = {}
local revealing = false
local openingAll = false -- an "Open all" asked of the server, not answered yet
local nextReveal: () -> () -- plays the queued reels one after another (below)
local throwing = false
local visible = false
local started = false
local tracks: { hold: AnimationTrack?, throw: AnimationTrack?, animator: Animator? } = {}

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function find(id: number?): Entry?
	for _, e in entries do
		if e.id == id then
			return e
		end
	end
	return nil
end

local function refresh()
	if aimedId ~= nil and find(aimedId) == nil then
		aimedId = nil
	end
	if hotbar then
		hotbar:set(entries, heldId or aimedId, liveIds)
		hotbar:setVisible(visible)
	end
end

local function reasonText(reply: any): string
	local reason = if type(reply) == "table" then reply.reason else nil
	return REASONS[if type(reason) == "string" then reason else "Error"] or REASONS.Error
end

local function request(action: string, a: any?, b: any?): any
	local ok, reply = pcall(function()
		return (Net.get("BlockRequest") :: RemoteFunction):InvokeServer(action, a, b)
	end)
	if not ok or type(reply) ~= "table" then
		return { ok = false, reason = "Error" }
	end
	return reply
end

---------------------------------------------------------------------------------------------
-- The arms
---------------------------------------------------------------------------------------------

local function animator(): (Animator?, boolean)
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return nil, true
	end
	return humanoid:FindFirstChildOfClass("Animator"), humanoid.RigType == Enum.HumanoidRigType.R15
end

-- AnimationTracks are not parented Instances: Parent == nil does not mean unloaded.
local function clearTracks()
	for _, track in { tracks.hold, tracks.throw } do
		if track then
			track:Stop(0)
			track:Destroy()
		end
	end
	table.clear(tracks)
end

local function load(id: string): AnimationTrack?
	local found = animator()
	if found == nil or id == "" then
		return nil
	end
	if tracks.animator ~= found then
		clearTracks()
		tracks.animator = found
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return (found :: Animator):LoadAnimation(animation)
	end)
	return if ok then track else nil
end

local function rigIds(): (string, string)
	local _, r15 = animator()
	if r15 then
		return A.HoldR15, A.ThrowR15
	end
	return A.HoldR6, A.ThrowR6
end

local function playHold()
	local holdId = rigIds()
	if tracks.hold == nil or tracks.animator ~= animator() then
		tracks.hold = load(holdId)
		if tracks.hold then
			tracks.hold.Looped = true
			tracks.hold.Priority = Enum.AnimationPriority.Action
		end
	end
	if tracks.hold and not tracks.hold.IsPlaying then
		tracks.hold:Play(A.HoldFadeSeconds)
	end
end

local function stopHold()
	if tracks.hold then
		tracks.hold:Stop(A.HoldFadeSeconds)
	end
	-- Also recover any orphaned hold loops from earlier equips without touching other poses.
	local found = animator()
	if found then
		for _, track in found:GetPlayingAnimationTracks() do
			local animation = track.Animation
			if
				animation
				and (animation.AnimationId == A.HoldR15 or animation.AnimationId == A.HoldR6)
			then
				track:Stop(A.HoldFadeSeconds)
				if track ~= tracks.hold then
					track:Destroy()
				end
			end
		end
	end
end

-- Plays the throw and waits until its Release marker (or ReleaseFallbackSeconds without one).
local function playThrow()
	local _, throwId = rigIds()
	if tracks.throw == nil or tracks.animator ~= animator() then
		tracks.throw = load(throwId)
		if tracks.throw then
			tracks.throw.Looped = false
			tracks.throw.Priority = Enum.AnimationPriority.Action2
		end
	end
	local track = tracks.throw
	if track == nil then
		task.wait(A.ReleaseFallbackSeconds)
		return
	end
	local released = false
	local connection = track:GetMarkerReachedSignal(A.ReleaseMarker):Connect(function()
		released = true
	end)
	track:Play(A.ThrowFadeSeconds)
	local began = os.clock()
	local limit = math.max(A.ReleaseFallbackSeconds, track.Length)
	while not released and os.clock() - began < limit do
		task.wait()
	end
	connection:Disconnect()
end

---------------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------------

local function putAway()
	stopHold()
	if tracks.throw then
		tracks.throw:Stop(A.ThrowFadeSeconds)
	end
	if heldId == nil then
		return
	end
	heldId = nil
	stopHold()
	refresh()
	task.spawn(request, "Hold", nil)
end

-- A Mystery (economy v5.2): its tap opens its upgrade screen, it is never held as it is.
local function rollsFirst(entry: Entry?): boolean
	return LuckyHotbar.rollsFirst(entry)
end

-- The skip for a block still counting down (LuckyHotbar.offerSkip asks, with the price for the
-- time left), and its Skip: the server prompts that tier's product (1 / 4 / 9 / 15 R$), or a line
-- says why not.
local function offerSkip(id: number)
	hotbar:offerSkip(id)
end

local function requestSkip(id: number)
	UISound.play("RobuxBuy") -- a Robux press (designer, 2026-10-09)
	task.spawn(function()
		local ok, skip = pcall(function()
			return (Net.get("StoreRequest") :: RemoteFunction):InvokeServer("LuckySkip", id)
		end)
		if not ok or type(skip) ~= "table" or not skip.ok then
			hotbar:say(W.SkipUnavailable)
		end
	end)
end

-- A Mystery's upgrade screen: its icon jumps out of its slot (MysteryReveal asks the server,
-- which turns it into the block its roll reached before anything is shown).
local function revealBlock(id: number)
	if not visible or throwing or opening:isOpen() or reveal:isBusy() then
		return
	end
	local entry = find(id)
	if entry == nil or not rollsFirst(entry) or liveIds[id] then
		return
	end
	aimedId = nil
	if entry.readyAt > serverNow() then
		hotbar:shake(id, REASONS.NotReady)
		offerSkip(id)
		refresh()
		return
	end
	putAway()
	local from, px = hotbar:slotOf(id)
	reveal:play(id, from, px, nil, entry.kind)
	refresh()
end

local function holdBlock(id: number)
	if throwing or opening:isOpen() or reveal:isBusy() then
		return
	end
	if rollsFirst(find(id)) then
		revealBlock(id)
		return
	end
	aimedId = nil
	if heldId == id then
		putAway()
		return
	end
	local entry = find(id)
	if entry == nil or liveIds[entry.id] then
		return
	end
	-- A tapped block: the tutorial's RareBlock step counts the win's Rare block seen.
	TutorialAnchors.setFlag("BlockTapped", true)
	heldId = id
	playHold()
	refresh()
	task.spawn(function()
		local reply = request("Hold", id)
		if not reply.ok and heldId == id then
			heldId = nil
			stopHold()
			refresh()
			hotbar:say(reasonText(reply))
		end
	end)
end

local function move(id: number, to: number)
	task.spawn(function()
		local reply = request("Move", id, to)
		if not reply.ok then
			hotbar:say(reasonText(reply))
		end
	end)
end

local function throw()
	local id = heldId
	if aimedId ~= nil and id == nil then
		revealBlock(aimedId)
		return
	end
	if id == nil or throwing or not visible or opening:isOpen() or reveal:isBusy() then
		return
	end
	local entry = find(id)
	if entry == nil then
		return
	end
	if entry.readyAt > serverNow() then
		-- Still on its timer: no throw, the skip instead.
		hotbar:shake(id, REASONS.NotReady)
		offerSkip(id)
		return
	end
	throwing = true
	task.spawn(function()
		playThrow()
		if heldId ~= id then
			throwing = false
			return
		end
		local reply = request("Throw", id)
		throwing = false
		if reply.ok then
			if heldId == id then
				heldId = nil
			end
			stopHold()
		elseif reply.reason == "NotReady" then
			hotbar:shake(id, REASONS.NotReady)
			offerSkip(id)
		else
			hotbar:say(reasonText(reply))
		end
		refresh()
	end)
end

function nextReveal()
	if revealing or #reveals == 0 then
		return
	end
	local reward = table.remove(reveals, 1)
	revealing = true
	local function done()
		revealing = false
		task.defer(nextReveal)
	end
	-- A Config.LuckyBlocks.QuickReveal rarity skips the reel (none since 2026-10-09: the
	-- designer wants the reel every time).
	if LuckyBlocks.quickReveal(reward.rarity) then
		opening:quick(reward.cue, reward.rarity, done)
	else
		-- A climb rolled at the open (economy v5.2): the reel shows the climb's odds.
		local climb = if type(reward.start) == "string"
			then { start = reward.start, luck = reward.luck == true }
			else nil
		opening:play(
			reward.kind,
			reward.cue,
			reward.rarity,
			done,
			if type(reward.oddsId) == "string" then reward.oddsId else nil,
			climb
		)
	end
end

-- "Open all" (economy v5 plan 3.8): the server opens every ready Standard and Uncommon block
-- (not the one in the hands, not a thrown one) and the summary shows the Common and Uncommon
-- cues that came out; a climb that reached Rare or better gets its own reel after it, one by
-- one (economy v5.2).
local function openAll()
	if openingAll or not visible or revealing or opening:isOpen() or reveal:isBusy() then
		return
	end
	openingAll = true
	task.spawn(function()
		local reply = request("OpenAll")
		openingAll = false
		if not reply.ok then
			hotbar:say(reasonText(reply))
			return
		end
		if type(reply.opened) == "table" and #reply.opened > 0 then
			if hotbar:isBagOpen() then
				hotbar:toggleBag()
			end
			local quick = {}
			for _, o in reply.opened do
				if type(o) ~= "table" or type(o.rarity) ~= "string" then
					continue
				elseif table.find(L.OpenAll.Summary, o.rarity) ~= nil then
					table.insert(quick, o)
				elseif type(o.cue) == "string" and type(o.kind) == "string" then
					table.insert(reveals, o)
				end
			end
			revealing = true
			opening:summary(quick, function()
				revealing = false
				task.defer(nextReveal)
			end)
		end
	end)
end

-- A block kind that can drop a cue of `rarity`, and that cue (the kind named after the rarity
-- first): for /cutscene.
local function blockOfRarity(rarity: string): (string?, string?)
	local order = table.clone(L.Order)
	local own = table.find(order, rarity)
	if own then
		table.remove(order, own)
		table.insert(order, 1, rarity)
	end
	for _, kind in order do
		local row = LuckyBlocks.kind(kind)
		if row and row.Odds then
			for _, entry in BlockOdds.cueOdds(row.Odds) do
				if entry.rarity == rarity then
					return kind, entry.id
				end
			end
		end
	end
	return nil, nil
end

local function openBlock(id: number)
	task.spawn(function()
		local reply = request("Open", id)
		if not reply.ok then
			hotbar:say(reasonText(reply))
			if reply.reason == "NotReady" then
				offerSkip(id)
			end
			LuckyWorld.allowPrompt(id)
			return
		end
		local burstAt = if type(reply.burstAt) == "number" then reply.burstAt else serverNow()
		local wait = burstAt - serverNow()
		if wait > 0 then
			task.wait(wait)
		end
		if
			type(reply.cue) == "string"
			and type(reply.rarity) == "string"
			and type(reply.kind) == "string"
		then
			table.insert(reveals, reply)
			nextReveal()
		end
	end)
end

-- The slots' keys and the gamepad's buttons (in the lobby, with no menu up but the bag).
local function onInput(input: InputObject, processed: boolean)
	if not visible or opening:isOpen() or reveal:isBusy() then
		return
	end
	local key = input.KeyCode
	-- The bag, like Roblox's own inventory key: ` (or ~), or L3. It answers even when Roblox
	-- marked the key as used (its own backpack key), but never while typing in a text box.
	if
		key == Enum.KeyCode.Backquote
		or key == Enum.KeyCode.Tilde
		or key == Enum.KeyCode.ButtonL3
	then
		if UserInputService:GetFocusedTextBox() == nil then
			hotbar:toggleBag()
		end
		return
	end
	if processed then
		return
	end
	-- The bag open is like Roblox's backpack: the keys still work and a click throws.
	if Menus.current() ~= nil and not hotbar:isBagOpen() then
		return
	end
	local index = NUMBER_KEYS[key]
	if index then
		local entry = hotbar:slotEntry(index)
		if entry then
			holdBlock(entry.id)
		end
	elseif key == Enum.KeyCode.ButtonL1 or key == Enum.KeyCode.ButtonR1 then
		local n = hotbar:slotCount()
		if n == 0 then
			return
		end
		local at = 0
		local current = heldId or aimedId
		for i = 1, n do
			local entry = hotbar:slotEntry(i)
			if entry and entry.id == current then
				at = i
			end
		end
		local step = if key == Enum.KeyCode.ButtonR1 then 1 else -1
		local nextIndex = if at == 0 then (if step > 0 then 1 else n) else (at - 1 + step) % n + 1
		local entry = hotbar:slotEntry(nextIndex)
		if entry and rollsFirst(entry) then
			-- Picked, not held: R2 opens its climb screen.
			putAway()
			aimedId = entry.id
			refresh()
		elseif entry then
			holdBlock(entry.id)
		end
	elseif
		key == Enum.KeyCode.ButtonR2 or input.UserInputType == Enum.UserInputType.MouseButton1
	then
		throw()
	end
end

---------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------

function LuckyClient.start(screen: ScreenGui)
	if started then
		return
	end
	started = true
	-- Our own hotbar replaces Roblox's backpack (no Tools are used).
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	hotbar = LuckyHotbar.new(screen, {
		select = holdBlock,
		reveal = revealBlock,
		move = move,
		skip = requestSkip,
		openAll = openAll,
	})
	opening = LuckyOpening.new(screen)
	reveal = MysteryReveal.new(screen.Parent :: Instance, {
		request = function(id: number): any
			return request("Reveal", id)
		end,
		slotOf = function(id: number): (Vector2?, number?)
			return hotbar:slotOf(id)
		end,
		mask = function(id: number, on: boolean)
			hotbar:mask(id, on)
		end,
		landed = function(id: number, kind: string)
			local tier = Config.LuckyBlocks.Reveal.Tiers[kind]
			local tint = if tier
				then Color3.fromRGB(tier.Glow[1], tier.Glow[2], tier.Glow[3])
				else nil
			hotbar:landed(id, tint)
		end,
		-- A climb that reached the Secret (no block): straight to the Secret's pull, then the
		-- card (the cue is already the player's).
		secret = function(reply: any)
			if type(reply.cue) == "string" then
				opening:pull(
					reply.cue,
					if type(reply.rarity) == "string" then reply.rarity else "Secret"
				)
			end
		end,
		refused = function(reply: any)
			hotbar:say(reasonText(reply))
			if type(reply) == "table" and reply.reason == "NotReady" and reveal.id then
				offerSkip(reveal.id)
			end
		end,
	})
	LuckyWorld.start({ onOpen = openBlock })
	-- Studio tests of the climb screen with a made-up path ("Standard,Uncommon,Uncommon,Rare")
	-- for a `kind` block (default Mystery), nothing asked of the server or changed in the save.
	-- A path ending on the Secret plays the Secret's pull with a Secret cue (nothing given).
	GuiQA.add("mystery", function(path: string?, kind: string?)
		-- One tier per press (Config.BlockOdds.Drop.Upgrade.Clicks): the start, then climbs.
		local tiers = string.split(path or "Standard,Uncommon,Uncommon,Rare", ",")
		local final = tiers[#tiers]
		local from, px = hotbar:slotOf(-1)
		local fake: any = { ok = true, path = tiers, from = kind or "Mystery" }
		if BlockDrop.isBlockTier(final) then
			fake.kind = final
		else
			local pool = BlockDrop.pool(final)
			fake.secret, fake.rarity = true, final
			fake.cue = if pool[1] then pool[1].Id else nil
		end
		reveal:play(-1, from, px, fake, kind)
		return true
	end)
	-- Studio tests of the reel with a made-up prize (default a Standard block's Cobalt Cue),
	-- nothing asked of the server or changed in the save.
	GuiQA.add("luckyReel", function(kind: string?, cueId: string?)
		local id = cueId or "CobaltCue"
		local row = Catalog.get(id)
		opening:play(kind or "Standard", id, if row then row.Rarity else "Common")
		return opening:isOpen()
	end)
	-- Studio tests of the quick reveal (default a Common cue of the Standard row) and of "Open
	-- all"'s summary (`ids`: "CobaltCue,CobaltCue,..."; default a few of the Standard and
	-- Uncommon rows' cues, one twice), nothing asked of the server or changed in the save.
	GuiQA.add("quickReveal", function(cueId: string?)
		local id = cueId or BlockOdds.cueOdds("Standard")[1].id
		local row = Catalog.get(id)
		opening:quick(id, if row then row.Rarity else "Common")
		return opening:isOpen()
	end)
	-- Press "Open all" as a tap would (the server really opens the blocks); whether it shows.
	GuiQA.add("openAll", function()
		local shown = hotbar.openAllButton.Visible
		openAll()
		return shown
	end)
	GuiQA.add("openAllSummary", function(ids: string?)
		local list = {}
		if ids then
			for _, id in string.split(ids, ",") do
				table.insert(list, { cue = id })
			end
		else
			local seen = {}
			for _, row in { "Standard", "Uncommon" } do
				for _, entry in BlockOdds.cueOdds(row) do
					if table.find(L.OpenAll.Summary, entry.rarity) and not seen[entry.id] then
						seen[entry.id] = true
						table.insert(list, { cue = entry.id, new = #list == 0 })
					end
				end
			end
			if list[1] then
				table.insert(list, { cue = list[1].cue })
			end
		end
		opening:summary(list)
		return opening:isOpen()
	end)
	-- The open reel's showcase card (economy v4 plan 4): stop the spin with it under the marker
	-- and say where it is and what it reads; `close` closes the opening instead.
	GuiQA.add("luckyReelPeek", function(close: boolean?)
		if close then
			opening:close()
			return nil
		end
		local reel = opening.reel
		if reel == nil or reel.showcaseAt == nil then
			return nil
		end
		local slot = reel.slots[reel.showcaseAt]
		reel:hold(reel.showcaseAt)
		return reel.showcaseAt, slot.id, slot.rarity, slot.showcase
	end)
	-- Studio checks of the skip (economy v4 plan 18.1 item 8): a made-up Epic block with
	-- `seconds` left (default 25 minutes: the 4 R$ tier) joins the bar until its next refresh
	-- and the skip is asked; nothing is asked of the server unless Skip is pressed. `step`:
	-- "odds" then presses its dice (the block's Odds & Details), "back" closes that list again
	-- (the question comes back).
	GuiQA.add("skipOffer", function(seconds: number?, step: string?)
		if step == "back" then
			hotbar.odds:close()
			task.wait(0.1)
			return hotbar.skipDialog ~= nil
		end
		local list = table.clone(entries)
		-- A block on its timer has climbed (economy v5): its odds are its one rarity's.
		table.insert(
			list,
			1,
			{ id = -2, kind = "Epic", readyAt = serverNow() + (seconds or 1500), climbed = true }
		)
		hotbar:set(list, heldId or aimedId, liveIds)
		hotbar:setVisible(true)
		hotbar:offerSkip(-2)
		if step == "odds" then
			hotbar:skipOdds(-2, "Epic")
			return hotbar.odds:isOpen()
		end
		return hotbar.skipDialog ~= nil
	end)
	-- Press the bar's `index`-th block (in bar order) as a tap would: a Mystery opens its
	-- upgrade screen, any other is held. Returns the pressed block's id and kind.
	GuiQA.add("blockPress", function(index: number?)
		local entry = entries[index or 1]
		if entry == nil then
			return nil
		end
		hotbar:pressed(entry.id)
		return entry.id, entry.kind
	end)
	GuiQA.add("blockBag", function(open: boolean?)
		hotbar:setBag(open ~= false)
		return hotbar:isBagOpen()
	end)
	GuiQA.add("mysteryTap", function()
		reveal:tap()
		return reveal.phase
	end)
	GuiQA.add("mysterySpeed", function(k: number?)
		reveal.timeScale = k or 1
		return reveal.timeScale
	end)
	GuiQA.add("mysteryState", function()
		return reveal.phase, reveal.presses
	end)
	GiftDrop.start() -- the Gift's fall from the sky, the first time back after leaving
	Net.get("BlockState").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" or type(payload.blocks) ~= "table" then
			return
		end
		local list: { Entry } = {}
		for _, b in payload.blocks do
			if type(b) == "table" and type(b.id) == "number" and type(b.kind) == "string" then
				table.insert(list, {
					id = b.id,
					kind = b.kind,
					readyAt = tonumber(b.readyAt) or 0,
					climbed = if b.climbed == true then true else nil,
				})
			end
		end
		entries = list
		if heldId ~= nil and find(heldId) == nil then
			heldId = nil
			stopHold()
		end
		refresh()
	end)
	-- /cutscene <rarity> (the designer's dev command, checked on the server): a whole opening
	-- that lands on a cue of that rarity, the reel, the cutscene and the card; nothing is given.
	Net.get("DevNotice").OnClientEvent:Connect(function(payload: any)
		if
			type(payload) ~= "table"
			or payload.kind ~= "Cutscene"
			or type(payload.rarity) ~= "string"
		then
			return
		end
		local kind, cueId = blockOfRarity(payload.rarity)
		if kind and cueId then
			table.insert(reveals, { kind = kind, cue = cueId, rarity = payload.rarity })
			nextReveal()
		end
	end)
	UserInputService.InputBegan:Connect(onInput)
	UserInputService.TouchTapInWorld:Connect(function(_position: Vector2, processed: boolean)
		if not processed then
			throw()
		end
	end)
	local player = Players.LocalPlayer
	if player then
		player.CharacterRemoving:Connect(function()
			stopHold()
			clearTracks()
		end)
		player.CharacterAdded:Connect(function()
			-- The server dropped the held copy with the old body.
			heldId = nil
			throwing = false
			clearTracks()
			refresh()
		end)
	end
	RunService.Heartbeat:Connect(function()
		local current = LuckyWorld.myLiveIds()
		local changed = false
		for id in current do
			if not liveIds[id] then
				changed = true
				break
			end
		end
		if not changed then
			for id in liveIds do
				if not current[id] then
					changed = true
					break
				end
			end
		end
		if changed then
			liveIds = current
			refresh()
		end
	end)
end

--- Progression: the hotbar shows in the lobby with no screen or menu over it (the bag aside).
--- Hiding it puts the held block away.
function LuckyClient.setVisible(show: boolean)
	if not started then
		return
	end
	if visible == show then
		return
	end
	visible = show
	if not show then
		putAway()
		aimedId = nil
	end
	hotbar:setVisible(show)
end

--- Whether the reel, its pull cutscene or its card is up (Progression treats it as a popup).
function LuckyClient.isOpen(): boolean
	return started and (opening:isOpen() or PullCutscene.isPlaying() or reveal:isOpen())
end

--- Close the reel (and its cutscene) at once: a match is starting, or the result screen
--- takes the screen.
function LuckyClient.close()
	if started then
		opening:close()
		PullCutscene.stop()
		reveal:close()
	end
end

--- The hotbar's middle in absolute pixels while the bar shows (where a block earned
--- elsewhere flies to; RewardChips, RewardsFlyer), else nil.
function LuckyClient.hotbarCenter(): Vector2?
	if not started or not visible then
		return nil
	end
	return hotbar:center()
end

--- A block landed in the hotbar: the bar bounces.
function LuckyClient.bumpHotbar()
	if started and visible then
		hotbar:bump()
	end
end

--- The tutorial: the hotbar slot (1-9) showing a block of `kind`, the one not ready first
--- when `waiting` (the Rare block on its timer), or nil.
function LuckyClient.slotOf(kind: string, waiting: boolean?): number?
	if not started then
		return nil
	end
	local fallback: number? = nil
	for i = 1, hotbar:slotCount() do
		local entry = hotbar:slotEntry(i)
		if entry and entry.kind == kind then
			if not waiting or entry.readyAt > serverNow() then
				return i
			end
			fallback = fallback or i
		end
	end
	return fallback
end

--- The tutorial: the held block's kind, or nil.
function LuckyClient.heldKind(): string?
	local entry = find(heldId)
	return if entry then entry.kind else nil
end

--- The tutorial: a block of `kind` of mine lying on the floor (its part), or nil.
function LuckyClient.livePart(kind: string): BasePart?
	if not started then
		return nil
	end
	for _, entry in entries do
		if entry.kind == kind and liveIds[entry.id] then
			return LuckyWorld.myLivePart(entry.id)
		end
	end
	return nil
end

return LuckyClient
