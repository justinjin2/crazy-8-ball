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
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Ranks = require(Shared:WaitForChild("Progression"):WaitForChild("Ranks"))
local HudParts = require(script.Parent.HudParts)
local RankBadge = require(script.Parent.RankBadge)

local P = Config.UI.Progress.Nameplate
local K = Config.UI.Kit
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
	-- The fade, outline and shine pass: a few times a second, not every frame.
	table.insert(
		self.connections,
		RunService.Heartbeat:Connect(function(dt)
			self.elapsed += dt
			if self.elapsed >= P.UpdateSeconds then
				self.elapsed = 0
				self:update()
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
	gui.AlwaysOnTop = false -- Studio captures do not draw AlwaysOnTop (STUDIO_NOTES)
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
	gui.Size = UDim2.new(units * P.SizeStuds, units * P.SizePx, P.SizeStuds, P.SizePx)
	-- No rays behind a Reyes badge here: they would cover the name.
	local badge = RankBadge.new(gui, { size = 1, name = "Badge", rays = false })
	badge.root.Size = UDim2.fromScale(1 / units, 1)
	local name = HudParts.text(gui, "Name", MEASURE_PX, words)
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
	gui.Parent = self.playerGui
	local plate: Plate = {
		player = player,
		gui = gui,
		badge = badge,
		name = name,
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
			plate.badge:setTransparency(fade)
		end
		local plateHeight = P.SizeStuds * perStud / distance + P.SizePx
		local outline = outlineFor(plateHeight * P.NameShare * TEXT_SHARE)
		if outline ~= plate.outline then
			plate.outline = outline
			local stroke = plate.name:FindFirstChild("Outline")
			if stroke and stroke:IsA("UIStroke") then
				stroke.Thickness = outline
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
