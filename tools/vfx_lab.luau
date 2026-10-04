--!nocheck
-- The cue VFX lab: judge cue skins in the real lobby lighting (the designer, 2026-10-01: the
-- auras must read on the bright floor, never judged on the dark Blender preview again). Run it
-- in a Play session through the Studio MCP's execute_luau on the Client, after editing IDS
-- below. It is a test harness, not game code: nothing here is saved or replicated.
--
-- For each cue id it puts, in a row at ORIGIN (one SPACING apart):
--   * a still copy of your avatar wearing that cue on its back (BackCue's real placement and
--     CueSkinLook with { aura = true, back = true }), facing away from +Z;
--   * a free cue on a stand beside it, lying level with its tip toward -X (aura on, as in
--     the hands);
-- and returns, per id, the camera positions to pass to screen_capture: "back" (behind and to
-- the side of the avatar, the view other players get), "stand" (side-on, close) and "front".
-- Run again to rebuild (it clears its folder first); CLEAR = true just clears it.
--
-- Roblox throttles particles far from the REAL camera (screen_capture's camera override does
-- not count), so it moves your avatar next to the lab at the end. Give new emitters a couple
-- of seconds before a capture.

local IDS = { "CelestialDragonCue", "KitsuneCue", "EclipseCue" }
local ORIGIN = Vector3.new(-40, 0, 70) -- an open stretch of the lobby floor
local SPACING = 14
local CLEAR = false

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Client = Players.LocalPlayer.PlayerScripts:WaitForChild("Client")
local CueStickBuilder = require(ReplicatedStorage.Shared.CueStickBuilder)
local CueSkinLook = require(Client.CueSkinLook)
local BackCue = require(Client.BackCue)
local CueAssets = require(Client.CueAssets)

-- BackCue watches player lifecycle events. Reuse one pool for this Play session instead of
-- leaving another set of listeners and hidden looks behind on every lab rerun.
if _G.VfxLabPool then
	for character in _G.VfxLabPool.carried do
		_G.VfxLabPool:release(character)
	end
	_G.VfxLabBackFolder.Parent = nil
end
local old = workspace:FindFirstChild("VfxLab")
if old then
	old:Destroy()
end
for _, l in _G.VfxLabLooks or {} do
	pcall(function()
		l:destroy()
	end)
end
_G.VfxLabLooks = {}
if CLEAR then
	return "cleared"
end

local lab = Instance.new("Folder")
lab.Name = "VfxLab"
lab.Parent = workspace

-- The floor under ORIGIN.
local hit = workspace:Raycast(ORIGIN + Vector3.new(0, 50, 0), Vector3.new(0, -200, 0))
local floorY = if hit then hit.Position.Y else ORIGIN.Y

local me = Players.LocalPlayer.Character
me.Archivable = true

local out = {}
local equipped = CueStickBuilder.equippedCue
-- One pool for the whole comparison; parked slots stay hidden. Warm before carry(), which
-- otherwise returns false on the first run and leaves the dummy with no cue to judge.
local pool = _G.VfxLabPool
if not pool then
	pool = BackCue.new(lab)
	_G.VfxLabPool = pool
	_G.VfxLabBackFolder = lab.BackCues
else
	_G.VfxLabBackFolder.Parent = lab
end
for i, id in IDS do
	CueAssets.preload(id)
	local deadline = os.clock() + 60
	while not CueAssets.ready(id) and os.clock() < deadline do
		task.wait(0.1)
	end
	assert(CueAssets.ready(id), "VFX lab: cue did not warm: " .. id)
	local x = ORIGIN.X + (i - 1) * SPACING
	-- The avatar copy, standing, facing -Z (its back toward the +Z camera).
	local dummy = me:Clone()
	for _, d in dummy:GetDescendants() do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") then
			d:Destroy()
		end
	end
	dummy.Name = "Dummy_" .. id
	local root = dummy:FindFirstChild("HumanoidRootPart")
	local hip = dummy:FindFirstChildOfClass("Humanoid").HipHeight
	root.Anchored = true
	dummy:PivotTo(CFrame.new(x, floorY + hip + root.Size.Y / 2, ORIGIN.Z))
	dummy.Parent = lab
	-- Its back cue, painted as `id` (BackCue paints the carrier's equipped cue).
	CueStickBuilder.equippedCue = function()
		return id
	end
	local carried = pool:carry(dummy, nil)
	CueStickBuilder.equippedCue = equipped
	assert(carried, "VFX lab: no free slot or back attachment: " .. id)
	CueStickBuilder.setVisible(pool.carried[dummy].stick, true)
	-- The stand: a free cue beside the avatar, level, tip toward -X.
	local stand = Instance.new("Folder")
	stand.Name = "Stand_" .. id
	stand.Parent = lab
	local stick = CueStickBuilder.build(stand, id)
	local tip = Vector3.new(x + 2.5, floorY + 4, ORIGIN.Z)
	CueStickBuilder.placeAt(stick, CFrame.new(tip) * CFrame.Angles(0, math.rad(90), 0))
	CueStickBuilder.setVisible(stick, true)
	table.insert(_G.VfxLabLooks, CueSkinLook.attach(stick, { aura = true }))
	local chest = Vector3.new(x, floorY + 4, ORIGIN.Z)
	local mid = tip + Vector3.new(3.5, 0, 0)
	table.insert(
		out,
		("%s back=[%g,%g,%g]>[%g,%g,%g] stand=[%g,%g,%g]>[%g,%g,%g] front=[%g,%g,%g]>[%g,%g,%g]"):format(
			id,
			chest.X - 3,
			chest.Y + 1.5,
			chest.Z + 7,
			chest.X,
			chest.Y - 0.5,
			chest.Z,
			mid.X,
			mid.Y + 0.6,
			mid.Z + 6.5,
			mid.X,
			mid.Y,
			mid.Z,
			chest.X + 2,
			chest.Y + 1,
			chest.Z - 7,
			chest.X,
			chest.Y - 0.5,
			chest.Z
		)
	)
end
me:PivotTo(CFrame.new(ORIGIN + Vector3.new(10, floorY + 3.5, 10)))
return table.concat(out, "\n")
