--!nocheck
-- Transient Studio Client assertions for the shared VFX lifecycle. No saved Script instances.
-- Run after templates are built; the current Play session's MCP module copies own this test.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Client = Players.LocalPlayer.PlayerScripts.Client
local CueVfx = require(Client.CueVfx)
local Quality = require(Client.Quality)
local CuePiece = require(Client.CuePiece)
local CueAssets = require(Client.CueAssets)
local CueSkinLook = require(Client.CueSkinLook)
local CueStickBuilder = require(RS.Shared.CueStickBuilder)
local Effects = require(Client.Effects)
local Config = require(RS.Shared.Config)
local wasLow = Quality.isLow()
local folder = Instance.new("Folder")
folder.Name = "CueVfxChecks"
folder.Parent = workspace
local passed = {}
local function near(a, b)
	assert(math.abs(a - b) < 1e-5, ("%s ~= %s"):format(a, b))
end
local ok, err = pcall(function()
	Quality.set(false)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.Transparency = 1
	anchor.Position = Vector3.new(0, -100, 0)
	anchor.Parent = folder
	local accent = CueVfx.emitter({ Rate = 20, Layer = "Accent" }, { frame = "world" })
	accent.Parent = anchor
	local form = CueVfx.emitter({ Rate = 1.2, Layer = "Essential", Transparency = 0.1 }, { frame = "world" })
	form.Parent = anchor
	for _ = 1, 3 do
		CueVfx.setShare(accent, 0.25)
		CueVfx.setShare(form, 0.25)
		for _, low in { true, false } do
			Quality.set(low)
			task.wait()
			near(accent.Rate, 5 * (if low then Config.CueSkins.LowerLayers.Accent else 1))
			near(form.Rate, 1.2)
			near(form.Transparency.Keypoints[1].Value, 0.775)
		end
	end
	CueVfx.setShare(accent, 1)
	near(accent.Rate, 20)
	table.insert(passed, "quality toggles retain quiet share without compounding; essential silhouette stays continuous")
	local piece = assert(CuePiece.new("eclipse", anchor, folder))
	Quality.set(true)
	piece.auraShare = 0.25
	piece:setModifier(0)
	local major, tiny = 0, 0
	for _, r in piece.rigid do
		if piece.layers[r.joint] == "Accent" then
			near(r.part.LocalTransparencyModifier, 1)
			tiny += 1
		elseif piece.auraJoints[r.joint] then
			near(r.part.LocalTransparencyModifier, 0.75)
			major += 1
		end
	end
	assert(major > 0 and tiny > 0)
	piece:setAura(false)
	piece:setModifier(0)
	for _, r in piece.rigid do
		if piece.auraJoints[r.joint] then near(r.part.LocalTransparencyModifier, 1) end
	end
	piece:destroy()
	table.insert(passed, "Lower effects hides tiny satellites; essential geometry respects quiet and aura-off")
	Quality.set(false)
	CueAssets.preload("EclipseCue")
	local warmUntil = os.clock() + 30
	while not CueAssets.ready("EclipseCue") and os.clock() < warmUntil do task.wait(0.1) end
	assert(CueAssets.ready("EclipseCue"))
	local stick = CueStickBuilder.build(folder, "EclipseCue")
	CueStickBuilder.placeAt(stick, workspace.CurrentCamera.CFrame * CFrame.new(0, 0, -8))
	CueStickBuilder.setVisible(stick, true)
	local look = CueSkinLook.attach(stick, { aura = true })
	stick:SetAttribute("AuraOff", true)
	for _ = 1, 4 do game:GetService("RunService").RenderStepped:Wait() end
	assert(look.piece, "skin look did not build its piece")
	local hidden = 0
	for _, r in look.piece.rigid do
		if look.piece.auraJoints[r.joint] then
			near(r.part.LocalTransparencyModifier, 1)
			hidden += 1
		end
	end
	assert(hidden > 0, "no classified aura geometry checked")
	look:destroy()
	stick:Destroy()
	table.insert(passed, "actual skin-look AuraOff hides classified geometry after frame updates")
	CueAssets.holdShots({ "EclipseCue" })
	local deadline = os.clock() + 30
	while not CueAssets.shotReady("EclipseCue") and os.clock() < deadline do task.wait(0.1) end
	assert(CueAssets.shotReady("EclipseCue"), "shot assets did not warm")
	local effects = Effects.new(folder, "skin:EclipseCue")
	effects:pocketBurst(anchor.Position, 0, false)
	effects:pocketBurst(anchor.Position, 8, false)
	assert(#effects.folder:GetChildren() == 0, "scratch or illegal 8 celebrated")
	effects:pocketBurst(anchor.Position, 1, false)
	effects:pocketBurst(anchor.Position, 2, false)
	local function pieces()
		local count = 0
		for _, item in effects.folder:GetChildren() do
			if item.Name == "Piece_eclipse_pocket" then count += 1 end
		end
		return count
	end
	assert(pieces() == 1, "rapid multi-pot stacked major finishers")
	effects:pocketBurst(anchor.Position, 8, true)
	assert(pieces() == 2, "legal winning 8 did not bypass ordinary cooldown")
	assert(effects.folder:FindFirstChild("VictorySecondSweep"), "winning variant missing")
	effects:destroy()
	task.wait(1.2)
	assert(effects.folder.Parent == nil, "destroyed effects returned")
	table.insert(passed, "scratch/illegal 8 suppressed; multi-pot bounded; legal winning 8 receives staged variant; cleanup holds")
end)
folder:Destroy()
Quality.set(wasLow)
assert(ok, err)
return passed
