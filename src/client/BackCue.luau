--!strict
-- BackCue: the cue on every player's back (designer, 2026-09-28). Each character near the
-- camera carries a stick painted as its player's equipped cue (the Classic mesh or bands, as in
-- their hands), diagonal across the back with the tip over the LEFT shoulder and the butt
-- toward the right hip, the seam toward the body. It hides exactly while that player's cue is
-- in their hands, in the same frame: update() is called once a frame, after Main.client has
-- drawn your own cue and WatchedShooters everyone else's (WatchedShooters.holding).
--
-- A stick is welded to BodyBackAttachment's part (R15 UpperTorso, R6 Torso): unanchored,
-- massless, no collide, query or touch, so it follows the body with no per-frame code, never
-- changes how the character moves, and the camera never zooms in on it. Sticks come from a pool
-- built up front (Config.Cue.Back.PoolSize); only characters within MaxDistanceStuds of the
-- camera get one, looked at every RefreshSeconds. A stick is let go (welds removed, parked,
-- hidden) when its character leaves the range, respawns or is removed.
--
-- Repainting a welded stick would move its parts, and so the body they are welded to, so a
-- stick is never repainted while attached: when its player equips another cue, the old stick
-- stays on until the renderer has loaded the new cue's look (CueAssets), then in one refresh it
-- is let go and a stick painted as the new cue goes on (designer, 2026-10-01: never the old cue
-- being retextured, and no empty back in between). A player walking into range gets their cue
-- once it is loaded.
--
-- Your own back cue hides in first person and fades like the hand cue when the camera comes
-- close (Camera.fadeNear). Sitting on a seat, it tilts further (SeatedExtraTiltDegrees).
--
-- Each stick wears its skin's look with the aura (CueSkinLook): the aura shows on backs only.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AvatarPose = require(Shared:WaitForChild("AvatarPose"))
local Config = require(Shared:WaitForChild("Config"))
local CueStickBuilder = require(Shared:WaitForChild("CueStickBuilder"))
local Camera = require(script.Parent:WaitForChild("Camera"))
local CueAssets = require(script.Parent:WaitForChild("CueAssets"))
local CueSkinLook = require(script.Parent:WaitForChild("CueSkinLook"))
local People = require(script.Parent:WaitForChild("People"))

local B = Config.Cue.Back
local LENGTH = Config.Cue.CueLengthStuds
-- Where a stick waits while no one carries it: below the map (above the fallen-parts line),
-- hidden.
local PARKED = CFrame.new(0, -100, 0)

type Carried = {
	stick: Model,
	player: Player?, -- nil: a body with no player (the default cue)
	character: Model,
	torso: BasePart,
	seated: boolean, -- the pose it was attached in
	cueId: string,
	welds: { WeldConstraint },
	shown: boolean?,
}

local BackCue = {}
BackCue.__index = BackCue

export type BackCue = typeof(setmetatable(
	{} :: {
		free: { Model },
		carried: { [Model]: Carried }, -- by character
		sinceRefresh: number,
		me: Player,
	},
	BackCue
))

--- The pool, built now in `parent`.
function BackCue.new(parent: Instance): BackCue
	local folder = Instance.new("Folder")
	folder.Name = "BackCues"
	folder.Parent = parent
	local free = {}
	for i = 1, B.PoolSize do
		local stick = CueStickBuilder.build(folder)
		stick.Name = ("BackCue_%02d"):format(i)
		for _, d in stick:GetDescendants() do
			if d:IsA("BasePart") then
				d.Massless = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		CueStickBuilder.setVisible(stick, false)
		stick:PivotTo(PARKED)
		-- The skin's look with its aura, worn on a back (CueSkinLook).
		CueSkinLook.attach(stick, { aura = true, back = true })
		table.insert(free, stick)
	end
	local self = setmetatable({
		free = free,
		carried = {},
		sinceRefresh = math.huge,
		me = Players.LocalPlayer,
	}, BackCue)
	-- A body going away takes its stick back at once, before its welds could let it fall.
	local function watch(player: Player)
		player.CharacterRemoving:Connect(function(character)
			self:release(character)
		end)
		-- Another cue equipped: loaded now, swapped on the back the moment it is ready.
		player:GetAttributeChangedSignal(Config.Cue.EquippedAttribute):Connect(function()
			self:fetch(CueStickBuilder.equippedCue(player))
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		if player.Character then
			self:release(player.Character)
		end
	end)
	return self
end

-- The tip's frame in the torso's space: the stick crosses the attachment `grip` studs from its
-- tip, `out` studs behind it, tilted `tilt` degrees from upright toward the left shoulder, its
-- local -Y (the seam) facing the body.
local function tipInTorso(attachment: Attachment, grip: number, tilt: number): CFrame
	local a = math.rad(tilt)
	local along = Vector3.new(math.sin(a), -math.cos(a), 0) -- tip toward butt: down and right
	local y = Vector3.new(0, 0, 1) -- away from the back: the seam (-Y) faces the body
	local x = y:Cross(along)
	local cross = attachment.Position + Vector3.new(0, 0, B.OutStuds)
	return CFrame.fromMatrix(cross - along * grip, x, y, along)
end

-- How far along the cue (from the tip) it crosses the attachment on this body: GripFromTip,
-- slid toward the butt when a small body would put the butt too near the floor.
local function gripFor(
	character: Model,
	torso: BasePart,
	attachment: Attachment,
	tilt: number
): number
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local standing = AvatarPose.standHeight(character)
	if root == nil or standing == nil then
		return B.GripFromTipStuds
	end
	local rootToAttach =
		root.CFrame:PointToObjectSpace(torso.CFrame:PointToWorldSpace(attachment.Position))
	local height = standing + rootToAttach.Y -- the attachment above the floor, standing
	local lowest = LENGTH - (height - B.MinButtHeightStuds) / math.cos(math.rad(tilt))
	return math.clamp(math.max(B.GripFromTipStuds, lowest), 0, LENGTH)
end

local function isSeated(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.SeatPart ~= nil
end

-- Weld a parked stick onto `character`'s back; false when the body has no back attachment.
local function attach(c: Carried): boolean
	local attachment = c.torso:FindFirstChild("BodyBackAttachment")
	if attachment == nil or not attachment:IsA("Attachment") then
		return false
	end
	c.seated = isSeated(c.character)
	local tilt = B.TiltDegrees + (if c.seated then B.SeatedExtraTiltDegrees else 0)
	local grip = gripFor(c.character, c.torso, attachment, tilt)
	c.cueId = CueStickBuilder.equippedCue(c.player)
	CueStickBuilder.paint(c.stick, c.cueId)
	c.stick:PivotTo(c.torso.CFrame * tipInTorso(attachment, grip, tilt))
	for _, d in c.stick:GetDescendants() do
		if d:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = c.torso
			weld.Part1 = d
			weld.Parent = d
			table.insert(c.welds, weld)
			d.Anchored = false
		end
	end
	c.shown = nil
	return true
end

-- Let a stick go: welds off, anchored, parked with its parts laid out again, hidden.
local function detach(c: Carried)
	for _, d in c.stick:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.LocalTransparencyModifier = 0 -- your own stick's fade, gone before it is reused
		end
	end
	for _, weld in c.welds do
		weld:Destroy()
	end
	table.clear(c.welds)
	CueStickBuilder.setVisible(c.stick, false)
	c.stick.WorldPivot = PARKED
	CueStickBuilder.relayout(c.stick)
end

local function backPart(character: Model): BasePart?
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	return if torso and torso:IsA("BasePart") then torso else nil
end

--- Add each carried stick and its player's UserId to `into` (AuraQuiet; a body with no
--- player is left out).
function BackCue.owners(self: BackCue, into: { [Model]: number })
	for _, c in self.carried do
		if c.player then
			into[c.stick] = c.player.UserId
		end
	end
end

--- Take `character`'s stick back into the pool (the body went, or left the range).
function BackCue.release(self: BackCue, character: Model)
	local c = self.carried[character]
	if c then
		detach(c)
		self.carried[character] = nil
		table.insert(self.free, c.stick)
	end
end

--- Put a stick on `character`'s back, painted as `player`'s equipped cue (nil: the default
--- cue). Players' characters are carried by refresh(); this is also how a body with no player
--- (a dummy, a future NPC) gets one, kept until release(). False when no stick is free or the
--- body has no BodyBackAttachment.
function BackCue.carry(self: BackCue, character: Model, player: Player?): boolean
	if self.carried[character] then
		return true
	end
	local torso = backPart(character)
	if torso == nil or #self.free == 0 then
		return false
	end
	-- Only a cue whose look is loaded goes on (a welded stick is never repainted).
	local cueId = CueStickBuilder.equippedCue(player)
	if not CueAssets.ready(cueId) then
		self:fetch(cueId)
		return false
	end
	local stick = table.remove(self.free) :: Model
	local c: Carried = {
		stick = stick,
		player = player,
		character = character,
		torso = torso,
		seated = false,
		cueId = "",
		welds = {},
		shown = nil,
	}
	if attach(c) then
		self.carried[character] = c
		return true
	end
	table.insert(self.free, stick)
	return false
end

-- Load cue `id`'s look, then refresh at once (not at the next refresh): the swap.
function BackCue.fetch(self: BackCue, id: string)
	CueAssets.whenReady(id, function()
		self.sinceRefresh = math.huge
	end)
end

-- Hand out and take back sticks: the nearest players' characters within range carry one.
function BackCue.refresh(self: BackCue)
	local eye = Workspace.CurrentCamera.CFrame.Position
	local want: { { player: Player, character: Model, d: number } } = {}
	-- Players and bots alike (the Bots lane: People's stand-in for a bot).
	for _, player in People.everyone() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if
			character
			and character.Parent
			and root
			and root:IsA("BasePart")
			and backPart(character)
			and humanoid
			and humanoid.Health > 0
		then
			local d = (root.Position - eye).Magnitude
			if d <= B.MaxDistanceStuds then
				table.insert(want, { player = player, character = character, d = d })
			end
		end
	end
	table.sort(want, function(a, b)
		return a.d < b.d
	end)
	local keep: { [Model]: boolean } = {}
	for i = 1, math.min(#want, B.PoolSize) do
		keep[want[i].character] = true
	end
	-- Let go of whoever left the range or the game, or whose body or cue changed (the ones still
	-- wanted are carried again below, with their new look or pose, in this same frame). A new
	-- cue counts only once it is loaded: until then the old one stays on.
	for character, c in self.carried do
		local player = c.player
		local cueId = CueStickBuilder.equippedCue(player)
		local stale = c.torso.Parent ~= character
			or character.Parent == nil
			or isSeated(character) ~= c.seated
			or (cueId ~= c.cueId and CueAssets.ready(cueId))
			or (player ~= nil and (not keep[character] or player.Character ~= character))
		if stale then
			self:release(character)
			if player == nil and character.Parent ~= nil then
				self:carry(character, nil) -- a dummy keeps its stick, re-posed
			end
		end
	end
	for i = 1, math.min(#want, B.PoolSize) do
		local w = want[i]
		self:carry(w.character, w.player)
	end
end

--- Once a frame, after the hand cues are drawn: `mineHeld` is whether your own cue is in your
--- hands this frame, `held` who else's is (WatchedShooters.holding).
function BackCue.update(self: BackCue, dt: number, mineHeld: boolean, held: { [number]: boolean })
	self.sinceRefresh += dt
	if self.sinceRefresh >= B.RefreshSeconds then
		self.sinceRefresh = 0
		self:refresh()
	end
	local camera = Workspace.CurrentCamera
	for character, c in self.carried do
		local mine = c.player ~= nil and c.player == self.me
		local show
		if mine then
			local head = character:FindFirstChild("Head")
			local firstPerson = head ~= nil
				and head:IsA("BasePart")
				and (camera.CFrame.Position - head.Position).Magnitude < B.FirstPersonStuds
			show = not mineHeld and not firstPerson
		else
			show = not (c.player and held[c.player.UserId])
		end
		if show ~= c.shown then
			c.shown = show
			CueStickBuilder.setVisible(c.stick, show)
		end
		if mine and show then
			Camera.fadeNear(c.stick, Config.Cue.CameraFadeStuds)
		end
	end
end

return BackCue
