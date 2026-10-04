# Lucky-block source assets

The bought pack (120 animated blocks with VFX) is `~/Downloads/LuckyBlock3.0/LuckyBlock3.0.rbxl`.
It stays outside the repo and is never edited. Its meshes and textures are already on Roblox and
load in Crazy 8 Ball. Its animations belong to the seller, so each one is re-uploaded to the
group (675425213).

- `models/YellowBlue.rbxm`: YellowLuckyBlock and BlueLuckyBlock, as in the test build.
- `anims/`: the idle animations (KeyframeSequences) and the arm animations (made by
  `tools/make_hand_anims.luau`).
- `textures/neutral_mask.png`: the emissive mask (below).

Code: `src/server/LuckyBlockService.luau` (models), `src/client/LuckyWorld.luau` (animation and
prompt). Kinds and tuning: `Config.LuckyBlocks`.

## Uploaded animations

Reuse an id when `tools/luckyblock_extract.luau` says a block has the "same motion as" a file
here. Add a row for every new upload.

| File | Motion in the pack | Id | Used by |
| --- | --- | --- | --- |
| `anims/BoxIdle.rbxm` | `Idle_Box_Take 001` (2.46 s) | `rbxassetid://120822945598411` | `Anim.BlockIdle` (Yellow, Blue) |
| `anims/LuckyHold/Throw R15/R6` | the arms | see `Config.LuckyBlocks.Anim` | every block |

The pack has 3 idle styles: 27 blocks use `Idle_Box`, 20 use `Idle_Winged` and 73 use
`Luckbox_Idle`. Blocks with the same style name can still move differently, so trust the
tool's check, not the name.

## Recipe: add a pack block ("add AdvancedLuckyBlock")

The designer decides which odds it rolls (a `Config.Cases` row) and its timer. Ask if the
request doesn't say. Run every command from the repo root.

1. **Find it.** `lune run tools/luckyblock_extract.luau --list` prints every model and its idle
   animation. Use the exact model name.
2. **Extract it.** `lune run tools/luckyblock_extract.luau <Name>` writes
   `models/<Name>.rbxm`, with the Animation Editor's `AnimSaves` link removed, and
   `anims/<Name>Idle.rbxm`. If the motion matches a file already in `anims/`, it removes the
   new copy and names the match. Then reuse that file's id from the table above and skip
   step 3.
3. **Upload the idle animation** (a new motion only). Check the key, then dry-run, then
   upload:
   ```bash
   security find-generic-password -s ROBLOX_API_KEY >/dev/null 2>&1 && echo True || echo False
   echo assets/luckyblocks/anims/<Name>Idle.rbxm > /tmp/up.txt
   python3 tools/roblox_upload.py --list /tmp/up.txt --force-type Animation --group-id 675425213 --dry-run
   python3 tools/roblox_upload.py --list /tmp/up.txt --force-type Animation --group-id 675425213
   ```
   Never print the key. The id is in `tools/upload_manifest.json`. Add a row to the table
   above.
4. **Import the model into the 8ball place** (Studio in Edit mode; stopping a play session
   is allowed). Serve the file with `python3 tools/studio_relay.py
   assets/luckyblocks/models/<Name>.rbxm` (run it in the background). Then run this through
   the Studio MCP `execute_luau` (Edit). It is a one-off Edit-mode command, not a script:
   ```lua
   local Http = game:GetService("HttpService")
   local was = Http.HttpEnabled
   Http.HttpEnabled = true
   local ok, data = pcall(Http.GetAsync, Http, "http://127.0.0.1:8765/file")
   Http.HttpEnabled = was
   assert(ok, data)
   local buf = game:GetService("EncodingService"):Base64Decode(buffer.fromstring(data))
   local model = game:GetService("SerializationService"):DeserializeInstancesAsync(buf)[1]
   local folder = game.ReplicatedStorage.LuckyBlocks
   local old = folder:FindFirstChild(model.Name)
   if old then old:Destroy() end
   -- The rooftop look (below): neutral base, white emissive mask.
   for _, d in model:GetDescendants() do
   	if d:IsA("MeshPart") then
   		d.Color = Color3.new(1, 1, 1)
   	elseif d:IsA("SurfaceAppearance") then
   		d.Color = Color3.new(1, 1, 1)
   		d.EmissiveTint = Color3.new(1, 1, 1)
   		d.EmissiveMaskContent = Content.fromUri("rbxassetid://104192408636466")
   	end
   end
   model.Parent = folder
   return model.Name .. " " .. #model:GetDescendants()
   ```
   Stop the relay afterwards (`pkill -f studio_relay.py`). Delete `models/<Name>.rbxm`
   unless the designer wants it kept: the place holds the model, and the pack can always
   produce it again.
5. **Code: data only, no new code.**
   - `Config.LuckyBlocks.Order`: add the kind's id (for example `"Advanced"`).
   - `Config.LuckyBlocks.Kinds`: `Advanced = { Case = "<case>", Timer = <seconds>, Model =
     "<Name>", Idle = "rbxassetid://<id>" }`. Leave out `Idle` if it uses `Anim.BlockIdle`'s
     motion.
   - `Strings.LuckyBlocks.Names`: `Advanced = "Advanced Lucky Block"`.
   - `/giveblock advanced` gives it to the designer for testing.
6. **Check.** Run `tools/lint.sh` and `tools/test.sh` (the tests check that every kind
   rolls a real case, has a name and a valid `Idle` id). Then playtest: hold it, throw it,
   open it, and watch the idle play. Commit and push, add a line to `docs/DECISIONS.md`, and
   ask the designer to save the place to `place/8ball.rbxl` and publish. The model is Edit-mode
   content, so it isn't live until the place is published.

## Rooftop look (2026-10-03)

The mesh base colour is neutral white. Each original SurfaceAppearance keeps its colour and
normal maps and gets a white emissive mask: `textures/neutral_mask.png` (16 x 16 white RGB), a
group-owned image asset 104192408636466 (uploaded decal 72694723354109). Only a plugin can write
EmissiveMaskContent, so it lives in the model and the place (step 4 sets it). The runtime
EmissiveStrength comes from `Config.LuckyBlocks.Look` (0.65). The working Crazy 8 Ball Studio
templates already have this; save the place and publish to ship it.

The original demo has much brighter ambient light than the rooftop. The neutral base, a gentle
texture-coloured fill and neutral viewport lights make up for it without changing the whole
lobby. Hotbar and bag previews keep the original PBR maps and use `Config.LuckyBlocks.UI`
IconAmbient, IconLight and IconLightDirection. Particles use `Look.ParticleLightInfluence`.
