--!strict
-- Copies one KeyframeSequence (an Animation Editor save) out of a place file into a binary
-- .rbxm, ready for tools/roblox_upload.py --force-type Animation --group-id 675425213.
--
-- Used for the lucky block pack (~/Downloads/LuckyBlock3.0/LuckyBlock3.0.rbxl), whose
-- animation ids belong to the seller and do not play in the group's game:
--   lune run tools/export_keyframes.luau <place.rbxl> <save name> <out.rbxm>
-- <save name> is the ObjectValue under ServerStorage.RBX_ANIMSAVES (the model's name, for
-- example YellowLuckyBlock); its first KeyframeSequence is written.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local placePath, saveName, outPath = process.args[1], process.args[2], process.args[3]
assert(
	placePath and saveName and outPath,
	"usage: export_keyframes.luau <place.rbxl> <save name> <out.rbxm>"
)

local game = roblox.deserializePlace(fs.readFile(placePath))
local saves = game:GetService("ServerStorage"):FindFirstChild("RBX_ANIMSAVES")
assert(saves, "no ServerStorage.RBX_ANIMSAVES in " .. placePath)
local save = saves:FindFirstChild(saveName)
assert(save, "no animation save named " .. saveName)
local sequence = save:FindFirstChildWhichIsA("KeyframeSequence")
assert(sequence, saveName .. " holds no KeyframeSequence")

local length = 0
for _, keyframe in sequence:GetChildren() do
	if keyframe:IsA("Keyframe") then
		length = math.max(length, keyframe.Time)
	end
end

fs.writeFile(outPath, roblox.serializeModel({ sequence }))
print(
	string.format(
		"wrote %s: %s, %d keyframes, %.2f s, loop %s",
		outPath,
		sequence.Name,
		#sequence:GetChildren(),
		length,
		tostring(sequence.Loop)
	)
)
