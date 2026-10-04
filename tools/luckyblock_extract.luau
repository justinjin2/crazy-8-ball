--!strict
-- Pulls one lucky block out of the bought pack's place (default
-- ~/Downloads/LuckyBlock3.0/LuckyBlock3.0.rbxl) for import: its model, without the Animation
-- Editor's AnimSaves link, to assets/luckyblocks/models/<Name>.rbxm, and its own idle
-- animation (ServerStorage.RBX_ANIMSAVES.<Name>'s KeyframeSequence) to
-- assets/luckyblocks/anims/<Name>Idle.rbxm. When that motion matches an animation already in
-- anims/ (already uploaded), it says which and removes the copy. The recipe that uses these
-- (upload, import into Studio through tools/studio_relay.py, the Config row) is in
-- assets/luckyblocks/Readme.md.
--
--   lune run tools/luckyblock_extract.luau <ModelName> [place.rbxl]
--   lune run tools/luckyblock_extract.luau --list [place.rbxl]   every model and its animation
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

assert(fs.isDir("src/shared"), "run this from the repo root")

local DEFAULT_PLACE = (process.env.HOME or "") .. "/Downloads/LuckyBlock3.0/LuckyBlock3.0.rbxl"
local name = process.args[1]
local placePath = process.args[2] or DEFAULT_PLACE
assert(name, "usage: luckyblock_extract.luau <ModelName> [place.rbxl] (or --list)")
assert(fs.isFile(placePath), "no place file at " .. placePath)

local game = roblox.deserializePlace(fs.readFile(placePath))
local saves = game:GetService("ServerStorage"):FindFirstChild("RBX_ANIMSAVES")

-- Every block model: the pack keeps them in Workspace.LuckyBlock, or loose in Workspace.
local function models(): { any }
	local list = {}
	local holder = game.Workspace:FindFirstChild("LuckyBlock")
	for _, parent in { holder, game.Workspace } do
		if parent then
			for _, child in parent:GetChildren() do
				if child:IsA("Model") and child:FindFirstChildOfClass("AnimationController") then
					table.insert(list, child)
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

-- The block's idle animation and its length, or nil.
local function idleOf(modelName: string): (any?, number)
	local save = saves and saves:FindFirstChild(modelName)
	local sequence = save and save:FindFirstChildWhichIsA("KeyframeSequence")
	local length = 0
	if sequence then
		for _, keyframe in sequence:GetChildren() do
			if keyframe:IsA("Keyframe") then
				length = math.max(length, keyframe.Time)
			end
		end
	end
	return sequence, length
end

if name == "--list" then
	for _, model in models() do
		local sequence, length = idleOf(model.Name)
		print(
			("%-32s %s"):format(
				model.Name,
				if sequence then ("%s (%.2f s)"):format(sequence.Name, length) else "no animation"
			)
		)
	end
	return
end

local model: any = nil
for _, m in models() do
	if m.Name == name then
		model = m
	end
end
assert(model, ("no block model called %s (try --list)"):format(name))

local copy = model:Clone()
local link = copy:FindFirstChild("AnimSaves")
if link then
	link:Destroy()
end
local modelPath = "assets/luckyblocks/models/" .. name .. ".rbxm"
fs.writeFile(modelPath, roblox.serializeModel({ copy }))
print("wrote " .. modelPath)

-- A sequence's motion as text (keyframe times, pose paths, weights and CFrames, rounded), so
-- two animations can be compared whatever their names or file bytes.
local function fingerprint(kfs: any): string
	local lines = {}
	local function walk(pose: any, path: string, time: number)
		for _, child in pose:GetChildren() do
			if child:IsA("Pose") then
				local p = path .. "/" .. child.Name
				local parts = { ("%.3f %s %.2f"):format(time, p, child.Weight) }
				for _, v in { child.CFrame:GetComponents() } do
					local text = ("%.3f"):format(v)
					table.insert(parts, if text == "-0.000" then "0.000" else text)
				end
				table.insert(lines, table.concat(parts, " "))
				walk(child, p, time)
			end
		end
	end
	for _, keyframe in kfs:GetChildren() do
		if keyframe:IsA("Keyframe") then
			walk(keyframe, "", keyframe.Time)
		end
	end
	table.sort(lines)
	return table.concat(lines, "\n")
end

local sequence, length = idleOf(name)
if sequence then
	local animPath = "assets/luckyblocks/anims/" .. name .. "Idle.rbxm"
	fs.writeFile(animPath, roblox.serializeModel({ sequence }))
	print(("wrote %s (%s, %.2f s, loop %s)"):format(animPath, sequence.Name, length, tostring(sequence.Loop)))
	-- An animation already in the repo with the same motion: reuse its uploaded id (the table in
	-- assets/luckyblocks/Readme.md) and drop the copy just written. Both are read back from
	-- files: the place's copy rounds differently from a saved one.
	local mine = fingerprint(roblox.deserializeModel(fs.readFile(animPath))[1])
	local same = nil
	for _, file in fs.readDir("assets/luckyblocks/anims") do
		local path = "assets/luckyblocks/anims/" .. file
		if same == nil and path ~= animPath and string.sub(file, -5) == ".rbxm" then
			for _, other in roblox.deserializeModel(fs.readFile(path)) do
				if other:IsA("KeyframeSequence") and fingerprint(other) == mine then
					same = file
				end
			end
		end
	end
	if same then
		fs.removeFile(animPath)
		print(("same motion as anims/%s: reuse its uploaded id, no upload (copy removed)"):format(same))
	end
else
	print("no animation save for " .. name .. ": it can use another block's idle")
end
