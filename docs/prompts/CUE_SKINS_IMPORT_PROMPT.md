# Brief: import the cue skins into the game

Written 2026-09-30 at the end of the cue-skins run, for the session that puts the new cues in the
game. The skins are built as files on branch `cue-skins` (worktree `~/Desktop/8ball-skins`):
textures, VFX sprites, 3D pieces and one data file per skin. Nothing is in Roblox yet.

**This is a milestone that touches many modules: plan it in plan mode with the designer first**
(CLAUDE.md, "How we work"). The designer is a beginner: explain every install, key and click in
simple steps.

## 1. Read first

- `CLAUDE.md`, then `docs/STATUS.md`, `docs/ARCHITECTURE.md`, `docs/UI_STYLE.md`.
- **`docs/prompts/CUE_SKINS_REPORT.md`, section 6 ("For the import session")**: the catalog
  changes, the `Config.Effects` rows, everything the cue builder needs, the upload list and the
  doc updates. It is the spec for this brief.
- `docs/prompts/CUE_SKINS_REVIEW.md`: one row per skin (what was built and why). Rows with a
  `fix:` from the designer are fixed before import.
- `docs/DECISIONS.md` from 2026-09-29 on: the run's assumptions and the designer's choices.
- One skin file end to end, for example `assets/cue/skins/kitsune.json` and
  `assets/cue/pieces/kitsune/piece.json`, next to its clip (`assets/cue/renders/skins/kitsune/`,
  rebuilt with `python3 tools/cue_skin.py kitsune --stills --sheet --clip`).

## 2. The designer's rules for how cues show (2026-09-30)

- **On the back:** the cue is in front of the body and the aura is behind it. Big
  camera-facing sprites (Eclipse's giant eclipse and galaxy) must never cover the avatar.
- **On the player's turn to shoot, the aura is off** (every aura emitter, Orbiter, Arc, aura
  Beam, Light and the piece's glow) so nothing distracts from aiming. It comes back when the
  cue returns to the back. The cue, its surface, its trail and its pocket finisher stay on.
- **The creatures are rigged holograms:** the Celestial Dragon head and pocket dragon, the
  Kitsune mask and pocket fox, the pocket firebird and the pocket skull are skinned `.glb`
  meshes whose bones follow the joints' motions (report 6.3, "Skinned pieces").
- Everything works on phone, PC and gamepad (CLAUDE.md).

## 3. Not in this import

- **The Unique cues (Founder's Cue, Beta Cue, Grand Opening)** are not built yet (their concept
  sheet, `assets/cue/concepts/Q1.png`, is missing). The designer will come back to them.
- Any skin whose review row says `fix:` and isn't fixed yet stays on its placeholder.

## 4. Suggested order (confirm in the plan)

1. **Merge.** `cue-skins` and `main` have both moved on. A test merge (2026-09-30) found
   conflicts in five files only: `docs/ARCHITECTURE.md`, `docs/DECISIONS.md`,
   `docs/STATUS.md`, `src/client/Main.client.luau` and `tools/upload_manifest.json`. Keep both
   sides in each (DECISIONS: both sets of dated lines; the manifest: every entry). Check first
   that no other session is working on `main`, and never force-push.
2. **Upload** (report 6.4). `tools/roblox_upload.py` uploads through the Open Cloud Assets API
   and records each asset id in `tools/upload_manifest.json`, so a rerun skips what is done.
   - Surface maps are not committed: rebuild them first with
     `python3 tools/cue_skin.py <id> --maps` (every skin).
   - Upload the VFX PNGs (`assets/cue/vfx/`), the piece OBJs and GLBs and their maps
     (`assets/cue/pieces/`), and each skin's surface maps.
   - A `.glb` (skinned piece) imports as a MeshPart with Bones: check one in Studio first
     (the 3D Importer, "rig" on) before uploading the rest.
3. **Data, not code.** Write a small tool that turns `assets/cue/skins/*.json`,
   `pieces/*/piece.json` and the manifest's asset ids into Luau data (one module of rows),
   so each cue is a catalog row plus assets (CLAUDE.md). Never hand-write a module per cue.
4. **The runtime** (report 6.3): one generic client module builds a cue's look from its row:
   surface and frames, emitters, Beams, Orbiters, Arcs, Lights, the piece (joints, and bones
   for skinned parts), the ball trail and pocket finisher (`Config.Effects` rows, report 6.2),
   the back-worn rate and the two rules in section 2. Particle counts are budgets already
   (report 5); check the frame rate on a phone with several Mythic cues on backs in one lobby.
5. **Catalog and strings** (report 6.1): swap the 30 placeholder case cues for the new ones,
   point the Exclusive and Rank rows at their new looks, make the Starter Cue tradable (with
   its test exception), names in the shared strings module.
6. **Tests and playtest:** `tools/lint.sh`, `tools/test.sh`, then Studio on phone, PC and
   gamepad: the shop and inventory thumbnails, a cue in hand, on the back, while shooting (aura
   off), a ball trail and a pocket finisher for one skin of every tier, and every rigged
   creature moving.
7. **Docs** (report 6.5): GDD, ECONOMY, STATUS, ROADMAP, ARCHITECTURE and a dated DECISIONS
   line. Ask the designer once to save the place to `place/8ball.rbxl` and publish.

## 5. Where things are

| What | Where |
|---|---|
| Skin data (one per cue) | `assets/cue/skins/<id>.json` (`catalog_id`, tier, `surface`, `vfx`) |
| VFX sprites | `assets/cue/vfx/_shared/`, `assets/cue/vfx/<id>/`, `assets/cue/vfx/rank/` |
| 3D pieces | `assets/cue/pieces/<id>/` (`piece.json`, OBJ or skinned GLB parts, maps) |
| Surface maps (rebuilt) | `assets/cue/textures/<id>_*.png` |
| Reference maths | `joint_matrix` and `export_matrix` in `assets/cue/CuePieces.py` |
| The Blender preview of every effect | `assets/cue/CuePreview.py` (it builds each piece the way Roblox should) |
