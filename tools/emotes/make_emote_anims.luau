--!nocheck
-- Writes the custom emotes' animations (Popcorn's Intro and Loop, Bullseye's Shot) as
-- KeyframeSequences in assets/emotes/<emote>/anims/, ready to upload as group Animations:
--
--   lune run tools/emotes/make_emote_anims.luau
--   python3 tools/roblox_upload.py --list <files> --force-type Animation --group-id 675425213
--
-- The poses live in tools/emotes/<emote>_anim.luau on the R15 rest frames in rig.luau; look at
-- them in Studio first with tools/emotes/preview.sh (no upload). Also prints where each prop
-- sits on its hand, for Config.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

assert(fs.isDir("src/shared"), "run this from the repo root")
local env = {
	CFrame = roblox.CFrame,
	Vector3 = roblox.Vector3,
	Instance = roblox.Instance,
	Enum = roblox.Enum,
}
local Rig = require("./rig")(env)

local function write(dir: string, kfs: any)
	if not fs.isDir(dir) then
		fs.writeDir(dir)
	end
	local path = dir .. kfs.Name .. ".rbxm"
	fs.writeFile(path, roblox.serializeModel({ kfs }))
	local keys = kfs:GetChildren()
	local last = 0
	for _, k in keys do
		last = math.max(last, k.Time)
	end
	print(("wrote %s (%d keys, %.2f s)"):format(path, #keys, last))
end

local Popcorn = require("./popcorn_anim")(Rig, env)
write("assets/emotes/popcorn/anims/", Popcorn.intro())
write("assets/emotes/popcorn/anims/", Popcorn.loop())
local hand = Popcorn.bucketOnHand()
local rx, ry, rz = hand:ToEulerAnglesYXZ()
print(
	("Popcorn bucket on LeftHand: offset %s, YXZ degrees %.1f %.1f %.1f"):format(
		tostring(hand.Position),
		math.deg(rx),
		math.deg(ry),
		math.deg(rz)
	)
)

local Bullseye = require("./bullseye_anim")(Rig, env)
write("assets/emotes/bullseye/anims/", Bullseye.shot())
local from, to = Bullseye.aim()
print(("Bullseye aim (root space): from %s to %s"):format(tostring(from), tostring(to)))
local bow = Bullseye.bowOnHand()
local bx, by, bz = bow:ToEulerAnglesYXZ()
print(
	("Bullseye bow on LeftHand: offset %s, YXZ degrees %.1f %.1f %.1f"):format(
		tostring(bow.Position),
		math.deg(bx),
		math.deg(by),
		math.deg(bz)
	)
)
