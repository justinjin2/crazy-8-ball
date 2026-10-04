--!nocheck
-- Transient Client assertions for independent dimensional cue motion and animated wakes.
local C = game.Players.LocalPlayer.PlayerScripts.Client
local RS = game.ReplicatedStorage
local CueAssets, CuePiece = require(C.CueAssets), require(C.CuePiece)
local Effects, Quality = require(C.Effects), require(C.Quality)
local wasLow = Quality.isLow()
local folder = Instance.new("Folder")
folder.Name = "DimensionalCueChecks"
folder.Parent = workspace
local root = Instance.new("Part")
root.Anchored, root.Transparency = true, 1
root.CFrame = CFrame.new(0, -100, 0)
root.Parent = folder
local checks = {}
local ok, err = pcall(function()
	for _, id in { "eclipse", "eclipse_pocket" } do
		local piece = assert(CuePiece.new(id, root, folder))
		task.wait(.1)
		assert(#piece.skinned > 0)
		for _, sk in piece.skinned do
			assert(sk.model:FindFirstChild("RootPart"), "single-mesh rig has no root")
			for _, part in sk.parts do
				assert(part:IsDescendantOf(workspace), "detached skinned mesh")
				assert((part.Position-root.Position).Magnitude < 20, "rig is not following its root")
			end
		end
		piece:step(0)
		local a = piece.skinned[1].bones[#piece.skinned[1].bones].bone.Transform
		piece:step(.7)
		local b = piece.skinned[1].bones[#piece.skinned[1].bones].bone.Transform
		assert(a ~= b, "flame bone is frozen")
		Quality.set(true)
		piece:setModifier(0)
		for _, sk in piece.skinned do
			for _, part in sk.parts do assert(part.LocalTransparencyModifier < .1, "Lower effects removed main shape") end
		end
		piece:setAura(false)
		piece:setModifier(0)
		if id == "eclipse" then
			for _, sk in piece.skinned do
				for _, part in sk.parts do assert(part.LocalTransparencyModifier == 1, "AuraOff leaked flames") end
			end
		end
		piece:destroy()
	end
	table.insert(checks, "cue/pocket skins follow their root, bones deform, Lower effects keeps forms, AuraOff hides flames")
	for _, id in { "EclipseCue" } do
		CueAssets.holdShots({ id })
		local deadline = os.clock()+30
		while not CueAssets.shotReady(id) and os.clock()<deadline do task.wait(.1) end
		assert(CueAssets.shotReady(id))
		local fx = Effects.new(folder, "skin:"..id)
		fx:attachTrail(root)
		assert(fx.trailFrames and #fx.trailFrames.Maps == 16)
		local ball={x=0,y=0,vx=10,vy=0,pocketed=false}
		local seen={}
		for i=1,10 do
			fx:updateTrail(ball,true)
			seen[fx.trail.Texture]=true
			task.wait(.07)
		end
		local count=0 for _ in seen do count+=1 end
		assert(count>5,"wake texture froze in Lower effects")
		fx:updateTrail(ball,false)
		assert(not fx.trail.Enabled)
		fx:detachTrail()
		assert(fx.trailFrames==nil and fx.trail==nil,"detached wake retained state")
		fx:destroy()
	end
	table.insert(checks, "Eclipse short wake animate in Lower effects and stop/clean up with replay")
end)
folder:Destroy()
Quality.set(wasLow)
assert(ok,err)
return checks
