--!strict
-- LuckyClient: lucky blocks on this screen (the test build, designer 2026-10-03). It holds the
-- player's blocks (BlockState), answers the controls and asks the server (BlockRequest), and
-- ties the hotbar (LuckyHotbar), the world (LuckyWorld) and the reel (LuckyOpening) together.
--
-- Controls, the same idea on every device:
-- - Hold a block: its hotbar slot (a tap or a click), keys 1-9, or LB / RB on a gamepad to step
--   through the slots. The same slot again puts it away. Both arms hold it out (the Hold
--   animation) and everyone sees it in the hands.
-- - Throw it: a tap on the world, a left click, or R2, including blocks still counting down.
--   Each keeps its own hold prompt and timer. The Throw animation asks the server at
--   its Release marker.
-- - Open it: the prompt over it (LuckyWorld). The server rolls; once the block bursts at the
--   top of its rise, the reel plays (and a Rare or better cue's pull cutscene, LuckyOpening).
-- The tutorial (Tutorial.luau) reads which slot holds a kind (slotOf), what is held and what
-- lies on the floor, and the hotbar registers its slots as anchors.
-- - The bag: the ` key, the bag button, or L3.
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
local BlockOdds = require(Progression:WaitForChild("BlockOdds"))
local LuckyBlocks = require(Progression:WaitForChild("LuckyBlocks"))
local LuckyHotbar = require(script.Parent.LuckyHotbar)
local LuckyOpening = require(script.Parent.LuckyOpening)
local LuckyWorld = require(script.Parent.LuckyWorld)
local Menus = require(script.Parent.Menus)
local PullCutscene = require(script.Parent.PullCutscene)
local TutorialAnchors = require(script.Parent.TutorialAnchors)

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
local entries: { Entry } = {}
local heldId: number? = nil
local liveIds: { [number]: boolean } = {}
local reveals: { any } = {}
local revealing = false
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
	if hotbar then
		hotbar:set(entries, heldId, liveIds)
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

local function holdBlock(id: number)
	if throwing or opening:isOpen() then
		return
	end
	if heldId == id then
		putAway()
		return
	end
	local entry = find(id)
	if entry == nil or liveIds[entry.id] then
		return
	end
	if entry.readyAt > serverNow() then
		-- A block still on its timer was tapped: the tutorial's RareBlock step counts it seen.
		TutorialAnchors.setFlag("BlockTapped", true)
	end
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
	if id == nil or throwing or not visible or opening:isOpen() then
		return
	end
	local entry = find(id)
	if entry == nil then
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
		else
			hotbar:say(reasonText(reply))
		end
		refresh()
	end)
end

local function nextReveal()
	if revealing or #reveals == 0 then
		return
	end
	local reward = table.remove(reveals, 1)
	revealing = true
	opening:play(reward.kind, reward.cue, reward.rarity, function()
		revealing = false
		task.defer(nextReveal)
	end, if type(reward.oddsId) == "string" then reward.oddsId else nil)
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
				local ok, skip = pcall(function()
					return (Net.get("StoreRequest") :: RemoteFunction):InvokeServer("LuckySkip", id)
				end)
				if not ok or type(skip) ~= "table" or not skip.ok then
					hotbar:say(W.SkipUnavailable)
				end
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
	if processed or not visible or opening:isOpen() then
		return
	end
	local key = input.KeyCode
	local current = Menus.current()
	if key == Enum.KeyCode.Backquote or key == Enum.KeyCode.ButtonL3 then
		hotbar:toggleBag()
		return
	end
	if current ~= nil then
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
		for i = 1, n do
			local entry = hotbar:slotEntry(i)
			if entry and entry.id == heldId then
				at = i
			end
		end
		local step = if key == Enum.KeyCode.ButtonR1 then 1 else -1
		local nextIndex = if at == 0 then (if step > 0 then 1 else n) else (at - 1 + step) % n + 1
		local entry = hotbar:slotEntry(nextIndex)
		if entry then
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
	hotbar = LuckyHotbar.new(screen, { select = holdBlock, move = move })
	opening = LuckyOpening.new(screen)
	LuckyWorld.start({ onOpen = openBlock })
	Net.get("BlockState").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" or type(payload.blocks) ~= "table" then
			return
		end
		local list: { Entry } = {}
		for _, b in payload.blocks do
			if type(b) == "table" and type(b.id) == "number" and type(b.kind) == "string" then
				table.insert(list, { id = b.id, kind = b.kind, readyAt = tonumber(b.readyAt) or 0 })
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
	end
	hotbar:setVisible(show)
end

--- Whether the reel, its pull cutscene or its card is up (Progression treats it as a popup).
function LuckyClient.isOpen(): boolean
	return started and (opening:isOpen() or PullCutscene.isPlaying())
end

--- Close the reel (and its cutscene) at once: a match is starting, or the result screen
--- takes the screen.
function LuckyClient.close()
	if started then
		opening:close()
		PullCutscene.stop()
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
