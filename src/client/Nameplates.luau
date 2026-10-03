--!strict
-- Nameplates: over every character's head, the player's rank badge then their username
-- (reference 02-rank-hud-nameplate), in the kit's white text with an ink outline. Roblox's own
-- name over the head is hidden (Humanoid.DisplayDistanceType None, on this client only).
--
-- One BillboardGui per player, in this client's PlayerGui (so nothing replicates), adorned to
-- the current character's head and kept across respawns. Its height is part studs, part pixels
-- (Config.UI.Progress.Nameplate): near plates grow with the world as in the reference, far ones
-- keep a readable floor, and past FadeEndStuds they are not drawn at all (MaxDistance). A
-- throttled pass, a few times a second rather than every frame, fades plates out between
-- FadeStartStuds and FadeEndStuds, keeps the name's outline thin while it is small, and lets
-- only the badges within ShineDistance shine.
--
-- A player's rank change (their RankTier and RankDivision attributes) pops their badge, so
-- everyone nearby sees a rank-up. The players in your match are hidden while you play
-- (setHidden, from Progression).
--
-- A win streak (designer, 2026-09-28): "🔥 3" on its own line over the badge and name, from
-- the first win in a row (the WinStreak attribute, Stats.WinStreak in the save); it bounces
-- when it goes up and is gone after a loss. The plate keeps its place over the head: the
-- BillboardGui is StreakShare taller and lifted by SizeOffset so the new line sits above it.
--
-- A VIP (the Vip attribute, set by the server) has their name in a gold shimmer (a UIGradient
-- on the white name; rainbow until 2026-10-03), with the badge kept in front of it. The
-- colours drift slowly along the name, one loop every VipRainbowCycleSeconds: calm, never a
-- flash. Only here: in chat a VIP gets the [VIP] tag instead (ChatTags).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Ranks = require(Shared:WaitForChild("Progression"):WaitForChild("Ranks"))
local HudParts = require(script.Parent.HudParts)
local RankBadge = require(script.Parent.RankBadge)
local UIAnim = require(script.Parent.UIAnim)
local People = require(script.Parent.People)

local P = Config.UI.Progress.Nameplate
local K = Config.UI.Kit
-- VIP's gold shimmer (Config.UI.Kit.Vip; designer, 2026-10-03: the rainbow is for deals now).
local RAINBOW: { { number } } = K.Vip.Colors :: any
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
-- Names are measured at this size to find how wide they are for their height.
local MEASURE_PX = 100
-- A TextScaled line's letters come out about this share of its box's height (Fredoka One).
local TEXT_SHARE = 0.85

type Plate = {
	player: Player,
	gui: BillboardGui,
	badge: RankBadge.Badge,
	name: TextLabel,
	streak: TextLabel, -- "🔥 3" over the name
	streakShown: number, -- the streak on it (0: none)
	rainbow: UIGradient, -- the VIP's rainbow over the name (enabled for a VIP)
	key: string?, -- the badge shown ("gold_3")
	known: boolean, -- that badge came from the player's save (not the Unranked stand-in)
	pending: boolean,
	fade: number,
	outline: number,
	connections: { RBXScriptConnection },
	bodyConnections: { RBXScriptConnection }, -- the current character's
}

local Nameplates = {}
Nameplates.__index = Nameplates

local function disconnectAll(list: { RBXScriptConnection })
	for _, connection in list do
		connection:Disconnect()
	end
	table.clear(list)
end

-- The ink outline for text about `px` tall on screen, by the kit's rule (HudParts): thin on
-- small text so the letters' holes stay open.
local function outlineFor(px: number): number
	if px < K.TextOutlineThinBelowPx then
		return K.TextOutlineThinPx
	end
	return math.max(K.TextOutlineMinPx, math.floor(px * K.TextOutlineRatio + 0.5))
end

-- The house rainbow as a loop (purple runs back into red), its colours evenly spaced round it.
local LOOP: { Color3 } = {}
for _, c in RAINBOW do
	table.insert(LOOP, HudParts.color(c))
end

-- The loop's colour at `u` (0..1 round the loop), blended between its neighbours.
local function loopColor(u: number): Color3
	local n = #LOOP
	local at = (u % 1) * n
	local i = math.floor(at)
	return LOOP[i % n + 1]:Lerp(LOOP[(i + 1) % n + 1], at - i)
end

-- A VIP's name colours, the loop shifted by `phase` (0..1): one whole loop across the name,
-- the same colour at both ends, so sliding the phase moves the colours with no seam.
local function rainbowAt(phase: number): ColorSequence
	local n = #LOOP
	if n < 2 then
		return ColorSequence.new(if n == 1 then LOOP[1] else Color3.new(1, 1, 1))
	end
	local times: { number } = {}
	for i = 1, n do
		local x = ((i - 1) / n - phase) % 1
		if x > 1e-3 and x < 1 - 1e-3 then
			table.insert(times, x)
		end
	end
	table.sort(times)
	local keys = { ColorSequenceKeypoint.new(0, loopColor(phase)) }
	for _, x in times do
		table.insert(keys, ColorSequenceKeypoint.new(x, loopColor(x + phase)))
	end
	table.insert(keys, ColorSequenceKeypoint.new(1, loopColor(phase)))
	return ColorSequence.new(keys)
end

-- Show whether the player is a VIP (their Vip attribute, which only the server sets).
local function showVip(plate: Plate)
	plate.rainbow.Enabled = plate.player:GetAttribute("Vip") == true
end

-- Show the player's rank from their attributes; `pop` bounces it if it changed.
local function showRank(plate: Plate, pop: boolean)
	local tier = plate.player:GetAttribute("RankTier")
	local division = plate.player:GetAttribute("RankDivision")
	local known = type(tier) == "string"
	local t: string = if type(tier) == "string" then tier else "Unranked"
	local d: number = if type(division) == "number" then division else 0
	local key = Ranks.badgeKey(t, d)
	if key == plate.key then
		plate.known = plate.known or known
		return
	end
	-- A rank seen changing live pops; the first real rank after the stand-in does not.
	plate.badge:set(t, d, pop and plate.known)
	plate.key = key
	plate.known = known
end

-- Show the player's win streak from their WinStreak attribute; `pop` bounces it when it
-- went up.
local function showStreak(plate: Plate, pop: boolean)
	local value = plate.player:GetAttribute("WinStreak")
	local streak = if type(value) == "number" and value >= P.StreakFrom
		then math.floor(value)
		else 0
	if streak == plate.streakShown then
		return
	end
	local rose = streak > plate.streakShown
	plate.streakShown = streak
	plate.streak.Visible = streak > 0
	if streak > 0 then
		plate.streak.Text = Strings.Progress.WinStreak:format(streak)
		if pop and rose then
			UIAnim.bounce(plate.streak)
		end
	end
end

-- Adorn the plate to the character's head and hide Roblox's own name over it.
local function attach(plate: Plate, character: Model?)
	disconnectAll(plate.bodyConnections)
	plate.gui.Adornee = nil :: any
	if not character then
		return
	end
	local function find()
		local head = character:FindFirstChild("Head")
		local part: any = if head and head:IsA("BasePart") then head else nil
		plate.gui.Adornee = part
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	find()
	-- The head and humanoid may arrive after the model (streaming, a slow load).
	table.insert(
		plate.bodyConnections,
		character.ChildAdded:Connect(function(child)
			if child.Name == "Head" or child:IsA("Humanoid") then
				find()
			end
		end)
	)
	table.insert(
		plate.bodyConnections,
		character.ChildRemoved:Connect(function(child)
			if child == plate.gui.Adornee then
				find()
			end
		end)
	)
end

--- Nameplates for everyone in the server, now and as they join.
function Nameplates.new(): any
	local self: any = setmetatable({}, Nameplates)
	self.plates = {} :: { [Player]: Plate }
	self.hidden = {} :: { [number]: boolean }
	self.connections = {}
	self.elapsed = 0
	self.rainbowElapsed = 0
	self.alive = true
	local localPlayer = Players.LocalPlayer
	self.playerGui = if localPlayer then localPlayer:WaitForChild("PlayerGui") else nil
	table.insert(
		self.connections,
		Players.PlayerAdded:Connect(function(player)
			self:add(player)
		end)
	)
	table.insert(
		self.connections,
		Players.PlayerRemoving:Connect(function(player)
			self:remove(player)
		end)
	)
	for _, player in Players:GetPlayers() do
		self:add(player)
	end
	-- Bots get the same plate (the Bots lane: People's stand-in carries the same attributes).
	table.insert(
		self.connections,
		People.botAdded:Connect(function(bot)
			self:add(bot)
		end)
	)
	table.insert(
		self.connections,
		People.botRemoved:Connect(function(bot)
			self:remove(bot)
		end)
	)
	for _, bot in People.bots() do
		self:add(bot)
	end
	-- The fade and outline pass: a few times a second, not every frame.
	table.insert(
		self.connections,
		RunService.Heartbeat:Connect(function(dt)
			self.elapsed += dt
			if self.elapsed >= P.UpdateSeconds then
				self.elapsed = 0
				self:update()
			end
			self.rainbowElapsed += dt
			if self.rainbowElapsed >= P.VipRainbowStepSeconds then
				self.rainbowElapsed = 0
				self:driftRainbows()
			end
		end)
	)
	return self
end

function Nameplates.add(self: any, player: Player)
	if self.plates[player] or not self.playerGui then
		return
	end
	local words = if P.UseDisplayName then player.DisplayName else player.Name
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nameplate_" .. player.UserId
	-- Drawn over the world like Roblox's own names, so a hat or a wall never cuts it; Studio's
	-- screen captures do not draw AlwaysOnTop (STUDIO_NOTES), so turn it off to check there.
	gui.AlwaysOnTop = P.AlwaysOnTop
	gui.LightInfluence = 0 -- the same at night
	gui.ResetOnSpawn = false
	gui.ClipsDescendants = false -- the badge's pop and sparkles reach past its box
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.MaxDistance = P.FadeEndStuds
	gui.StudsOffsetWorldSpace = Vector3.new(0, P.OffsetStuds, 0)
	gui.Enabled = not self.hidden[player.UserId]
	-- Sized to the badge and this name, in units of the badge's height, so the pair is
	-- centred over the head whatever the name's length.
	local measured = TextService:GetTextSize(words, MEASURE_PX, FONT, Vector2.new(100000, 1000))
	local aspect = measured.X / math.max(1, measured.Y) * (1 + P.NameSlack)
	local nameWidth = aspect * P.NameShare
	local units = 1 + P.GapShare + nameWidth
	-- The streak's line sits over the plate: the gui is that much taller, and lifted by half
	-- of it (SizeOffset is a share of the size), so the badge and name keep their place.
	local tall = 1 + P.StreakShare
	gui.Size = UDim2.new(units * P.SizeStuds, units * P.SizePx, tall * P.SizeStuds, tall * P.SizePx)
	gui.SizeOffset = Vector2.new(0, P.StreakShare / (2 * tall))
	local row = HudParts.frame(gui, "Plate")
	row.AnchorPoint = Vector2.new(0, 1)
	row.Position = UDim2.fromScale(0, 1)
	row.Size = UDim2.fromScale(1, 1 / tall)
	local streak = HudParts.text(gui, "Streak", MEASURE_PX, "", HudParts.tone("Gold"))
	HudParts.setTextSize(streak, MEASURE_PX, 1) -- scaled to its box at any distance
	streak.AutoLocalize = false -- a number and the fire
	streak.AnchorPoint = Vector2.new(0.5, 0)
	streak.Position = UDim2.fromScale(0.5, 0)
	streak.Size = UDim2.fromScale(1, P.StreakShare / tall)
	streak.Visible = false
	-- No rays behind a Reyes badge here: they would cover the name.
	local badge = RankBadge.new(row, { size = 1, name = "Badge", rays = false })
	badge.root.Size = UDim2.fromScale(1 / units, 1)
	local name = HudParts.text(row, "Name", MEASURE_PX, words)
	HudParts.setTextSize(name, MEASURE_PX, 1) -- scaled to its box at any distance
	local stroke = name:FindFirstChild("Outline")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Thickness = K.TextOutlineThinPx -- until the first pass sizes it (update)
	end
	name.AutoLocalize = false -- a player's name is never translated
	-- No `TextWrapped = false`: in Roblox that also turns TextScaled off (STUDIO_NOTES), and
	-- the name must scale with its box. One word never wraps anyway.
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.AnchorPoint = Vector2.new(0, 0.5)
	name.Position = UDim2.fromScale((1 + P.GapShare) / units, 0.5)
	name.Size = UDim2.fromScale(nameWidth / units, P.NameShare)
	local rainbow = Instance.new("UIGradient")
	rainbow.Name = "VipRainbow"
	rainbow.Color = rainbowAt(0)
	rainbow.Enabled = false
	rainbow.Parent = name
	gui.Parent = self.playerGui
	local plate: Plate = {
		player = player,
		gui = gui,
		badge = badge,
		name = name,
		streak = streak,
		streakShown = 0,
		rainbow = rainbow,
		key = nil,
		known = false,
		pending = false,
		fade = 0,
		outline = -1,
		connections = {},
		bodyConnections = {},
	}
	self.plates[player] = plate
	showRank(plate, false)
	showStreak(plate, false)
	showVip(plate)
	table.insert(
		plate.connections,
		player:GetAttributeChangedSignal("WinStreak"):Connect(function()
			showStreak(plate, true)
		end)
	)
	table.insert(
		plate.connections,
		player:GetAttributeChangedSignal("Vip"):Connect(function()
			showVip(plate)
		end)
	)
	-- RankTier and RankDivision change together: one refresh for both.
	local function changed()
		if plate.pending then
			return
		end
		plate.pending = true
		task.defer(function()
			plate.pending = false
			if self.plates[player] == plate then
				showRank(plate, true)
			end
		end)
	end
	for _, attribute in { "RankTier", "RankDivision" } do
		table.insert(
			plate.connections,
			player:GetAttributeChangedSignal(attribute):Connect(changed)
		)
	end
	table.insert(
		plate.connections,
		player.CharacterAdded:Connect(function(character)
			attach(plate, character)
		end)
	)
	table.insert(
		plate.connections,
		player.CharacterRemoving:Connect(function(character)
			if plate.gui.Adornee and plate.gui.Adornee:IsDescendantOf(character) then
				attach(plate, nil)
			end
		end)
	)
	attach(plate, player.Character)
end

function Nameplates.remove(self: any, player: Player)
	local plate: Plate? = self.plates[player]
	if not plate then
		return
	end
	self.plates[player] = nil
	disconnectAll(plate.connections)
	disconnectAll(plate.bodyConnections)
	plate.badge:destroy()
	plate.gui:Destroy()
end

-- The throttled pass: for each plate, how far it is from the camera sets its fade, its name's
-- outline and whether its badge shines.
-- Slide the VIPs' name colours on one shared clock (only the plates being drawn; a handful).
function Nameplates.driftRainbows(self: any)
	local colors: ColorSequence? = nil
	for _, plate in self.plates do
		if plate.rainbow.Enabled and plate.gui.Enabled and plate.gui.Adornee and plate.fade < 1 then
			if not colors then
				-- Negative: the colours travel from the name's start toward its end.
				colors = rainbowAt(-os.clock() / math.max(1, P.VipRainbowCycleSeconds))
			end
			plate.rainbow.Color = colors :: ColorSequence
		end
	end
end

function Nameplates.update(self: any)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	-- Pixels per stud at one stud away; divided by the distance below.
	local perStud = camera.ViewportSize.Y / (2 * math.tan(math.rad(camera.FieldOfView) / 2))
	local fadeSpan = math.max(0.001, P.FadeEndStuds - P.FadeStartStuds)
	for _, plate in self.plates do
		local head = plate.gui.Adornee
		if not plate.gui.Enabled or not head or not head:IsA("BasePart") then
			plate.badge:setShining(false)
			continue
		end
		local distance = math.max(0.5, (head.Position - eye).Magnitude)
		plate.badge:setShining(distance <= P.ShineDistance)
		local fade = math.clamp((distance - P.FadeStartStuds) / fadeSpan, 0, 1)
		fade = math.floor(fade / P.FadeStep + 0.5) * P.FadeStep
		if fade ~= plate.fade then
			plate.fade = fade
			HudParts.setTextTransparency(plate.name, fade)
			HudParts.setTextTransparency(plate.streak, fade)
			plate.badge:setTransparency(fade)
		end
		local plateHeight = P.SizeStuds * perStud / distance + P.SizePx
		local outline = outlineFor(plateHeight * P.NameShare * TEXT_SHARE)
		if outline ~= plate.outline then
			plate.outline = outline
			for _, label in { plate.name, plate.streak } do
				local stroke = label:FindFirstChild("Outline")
				if stroke and stroke:IsA("UIStroke") then
					stroke.Thickness = outline
				end
			end
		end
	end
end

--- Hide the plates of these players (the ones in your match, while you play). Cheap to call
--- every frame: nothing changes unless the set does.
function Nameplates.setHidden(self: any, userIds: { [number]: boolean })
	local old: { [number]: boolean } = self.hidden
	if userIds == old then
		return
	end
	local same = true
	for id in userIds do
		if not old[id] then
			same = false
			break
		end
	end
	if same then
		for id in old do
			if not userIds[id] then
				same = false
				break
			end
		end
	end
	if same then
		return
	end
	self.hidden = table.clone(userIds)
	for _, plate in self.plates do
		plate.gui.Enabled = not self.hidden[plate.player.UserId]
	end
end

function Nameplates.destroy(self: any)
	if not self.alive then
		return
	end
	self.alive = false
	disconnectAll(self.connections)
	local players = {}
	for player in self.plates do
		table.insert(players, player)
	end
	for _, player in players do
		self:remove(player)
	end
end

return Nameplates
