#!/usr/bin/env bash
# Prints a Luau snippet for an Edit-mode run in Studio (execute_luau) that builds an emote's
# KeyframeSequences from tools/emotes/rig.luau and its *_anim.luau, registers them with
# KeyframeSequenceProvider (no upload) and leaves their temporary ids in
# workspace.EmotePreviewIds (a Configuration of StringValues), ready to play on a rig there.
#
#   tools/emotes/preview.sh popcorn > /tmp/snippet.luau
set -euo pipefail
cd "$(dirname "$0")"
name="$1"
cat <<LUAU
local env = { CFrame = CFrame, Vector3 = Vector3, Instance = Instance, Enum = Enum }
local Rig = (function()
$(sed 's/^return function(env)/return (function(env)/; $ s/^end$/end)(env)/' rig.luau)
end)()
local Anim = (function()
$(cat "${name}_anim.luau" | sed '1,/^return function(Rig, env)/ s/^return function(Rig, env)/return (function(Rig, env)/' | sed '$ s/^end$/end)(Rig, env)/')
end)()
local KSP = game:GetService("KeyframeSequenceProvider")
local ids = workspace:FindFirstChild("EmotePreviewIds") or Instance.new("Configuration")
ids.Name = "EmotePreviewIds"
ids.Parent = workspace
local out = {}
for key, build in Anim do
	if type(build) == "function" and (key == "intro" or key == "loop" or key == "shot") then
		local kfs = build()
		local value = ids:FindFirstChild(kfs.Name) or Instance.new("StringValue")
		value.Name = kfs.Name
		value.Value = KSP:RegisterKeyframeSequence(kfs)
		value.Parent = ids
		table.insert(out, kfs.Name .. " " .. #kfs:GetChildren() .. " keys")
	end
end
-- Where props sit on their hands (CFrameValues named after the function, e.g. BucketOnHand).
for key, fn in Anim do
	if type(fn) == "function" and key:match("OnHand$") then
		local name = key:sub(1, 1):upper() .. key:sub(2)
		local value = ids:FindFirstChild(name) or Instance.new("CFrameValue")
		value.Name = name
		value.Value = fn()
		value.Parent = ids
	end
end
return table.concat(out, ", ")
LUAU
