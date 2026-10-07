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
| `anims/BoxIdle.rbxm` | `Idle_Box_Take 001` (2.46 s) | `rbxassetid://120822945598411` | `Anim.BlockIdle` (Standard, Uncommon, Rare, Epic) |
| `anims/GoldKingLuckyBlockIdle.rbxm` | Gold King (2.46 s, different bone motion) | `rbxassetid://77259119233155` | Legendary |
| `anims/LuckyHold/Throw R15/R6` | the arms | see `Config.LuckyBlocks.Anim` | every block |
| `anims/GoldMajesticLuckyBlockIdle.rbxm` | `Luckbox_Idle` (3.29 s; Gold Majestic, Diamond Ghost and Gold Titan share it) | `rbxassetid://80469786057791` | Legendary, Sky, Mythic |

## Uploaded images (2026-10-04, the shop v3 blocks)

Decal id from the upload, image id resolved in Studio (`InsertService:LoadAsset(decal).Texture`);
the image id is what `ColorMapContent` and a Decal's `Texture` take.

| File | Decal | Image | Used by |
| --- | --- | --- | --- |
| `textures/sky_colormap.png` | 88635262488640 | `rbxassetid://73401949661572` | SkyLuckyBlock (Diamond Ghost recoloured) |
| `textures/mythic_colormap.png` | 86015566073682 | `rbxassetid://95148605758635` | GoldTitanLuckyBlock (Mythic, pastel rainbow) |
| `textures/mystery_colormap.png` | 90293759365238 | `rbxassetid://113001088890929` | MysteryLuckyBlock (the Standard block, black with rainbow rims) |
| `textures/starter_colormap.png` | 133665179133564 | `rbxassetid://76868859886135` | StarterLuckyBlock (the Standard block, red with a gold tie; the Gift block too) |
| `textures/lucky8_face.png` | 105497210308341 | `rbxassetid://140162075149185` | Lucky8Block's "8" face decals |

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
           -- Preserve the authored SurfaceAppearance tint: Gold King is gold; Void Lava violet.
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
   - `Strings.LuckyBlocks.Names`: `Advanced = "<case> Lucky Block"`.
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

## Added tiers (2026-10-03 follow-up)

| Kind saved in inventory | Player-facing name | Pack model | Timer |
| --- | --- | --- | --- |
| Yellow | Standard Lucky Block | YellowLuckyBlock | none |
| Green | Uncommon Lucky Block | GreenLuckyBlock | 1 minute |
| Blue | Rare Lucky Block | BlueLuckyBlock | 2 minutes |
| VoidLava | Epic Lucky Block | VoidLavaLuckyBlock | 1 hour |
| GoldKing | Legendary Lucky Block | GoldKingLuckyBlock | 6 hours |

Keep existing save kind IDs; names describe the odds tier. Designer-only join seeding/refills
include all five. Only Standard disables physical lights; particles stay intact. Preserve
SurfaceAppearance.Color: Void Lava uses RGB 151/130/255 and Gold King uses 255/170/0.
Gold King has lower configurable emissive/preview light to retain its gold surface detail.

## The shop v3 blocks in the place (2026-10-04)

`ReplicatedStorage.LuckyBlocks` holds eleven models (Edit-mode content: save the place and
publish to ship them):

| Model | Kind | How it was made |
| --- | --- | --- |
| YellowLuckyBlock, GreenLuckyBlock, BlueLuckyBlock, VoidLavaLuckyBlock, GoldKingLuckyBlock | Standard, Uncommon, Rare, Epic, GrandOpening | the test build's imports |
| GoldMajesticLuckyBlock | Legendary | `models/GoldMajesticLuckyBlock.rbxm`, the pack's maps, white emissive mask |
| GoldTitanLuckyBlock | Mythic | `models/GoldTitanLuckyBlock.rbxm` with `textures/mythic_colormap.png` as its ColorMap |
| SkyLuckyBlock | Sky | `models/DiamondGhostLuckyBlock.rbxm` renamed, with `textures/sky_colormap.png` |
| MysteryLuckyBlock | Mystery | a clone of YellowLuckyBlock with `textures/mystery_colormap.png` |
| StarterLuckyBlock | Starter, Gift | a clone of YellowLuckyBlock with `textures/starter_colormap.png` (the Gift block uses it until it gets its own) |
| Lucky8Block | Lucky8 | part-built: a black 4.66-stud cube, twelve silver rim parts, a white disc with the "8" decal on each face; no animation (`Config.LuckyBlocks.Bob` hovers and turns it by code) |

The three winged pack blocks (Majestic, Titan, Ghost) have wide bounding boxes, so their kinds
set `IconScale` about 2 to frame the body, and `SizeMultiplier` for the world.


## Our own blocks (2026-10-07)

The pack blocks are being replaced by our own, built to the approved concept icons
(`~/Desktop/8ball-refs/lucky-blocks/`: round B corner cubes for every kind, round C flush rims for
Mystery). One master block, three pieces (Frame, Core, Glyph), each kind a set of painted maps.

1. **Paint** the maps: `python3 tools/luckyblock_textures.py <kind>` writes
   `build/<kind>/{frame,core,glyph}.png` (the colours are the `KINDS` table).
2. **Build** in headless Blender:
   `/Applications/Blender.app/Contents/MacOS/Blender -b -P tools/luckyblock_build.py -- --kind <kind> --glb assets/luckyblocks/build/<kind>/<Name>Block.glb [--preview out.png]`
   (frame style per kind in `LOOKS`). The rig is joint1 at the bottom and joint2 2.96 studs up,
   every piece on joint2.
3. **Upload** the glb (dry-run first) with `tools/roblox_upload.py --list ... --group-id 675425213`.
4. **Template**: put the model id and name in `BLOCKS` of `tools/luckyblock_template.luau` and run
   it through the Studio MCP `execute_luau` (Edit). It moves each part's texture into a
   SurfaceAppearance with a roughness map and the white emissive mask, adds the Animator, puts
   the pivot at the bottom centre and copies the pack's glow particles and light (tinted by
   `Tint`). Save the place and publish.
5. **Config**: the kind's `Model = "<Name>Block"` and `Idle = "rbxassetid://126596744037463"`.

| Model | Kind | Model asset |
| --- | --- | --- |
| StandardBlock | Standard | 81565701370753 (v4: golden-beige rims, brown faces, like the pack) |
| MysteryBlock | Mystery | 131944205075030 (v3: thinner flush rims; moving rainbow, twinkles) |

The Mystery frame's moving rainbow is six `Texture`s (`textures/rainbow_scroll.png`, image
`rbxassetid://107891048379160`) tagged `LuckyScroll`; LuckyWorld slides them
(`Config.LuckyBlocks.Look.Scroll`). A SurfaceAppearance map cannot move, a Texture can. Never
dissolve the frame's flat faces in the builder: a face's ring of bars became one face with a hole
and the glb export filled it with a triangle across the panel.

**LuckyBoxIdle** (`anims/LuckyBoxIdle.rbxm`, `rbxassetid://126596744037463`) is the pack's Box
Idle on our rig, written by `lune run tools/luckyblock_anims.luau`: the hover from 1 to 1.9 studs
with a few degrees of tilt, measured in Studio against the pack block (the pack plays its poses at
model scale 0.02). Roughness maps: `textures/rough_022.png` (glossy, `rbxassetid://98760410664616`)
and `textures/rough_045.png` (satin, `rbxassetid://120409166438752`).
