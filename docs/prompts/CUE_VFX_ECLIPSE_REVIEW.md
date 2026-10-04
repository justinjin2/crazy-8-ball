# Eclipse visual review — 2026-10-04

**Eclipse only. Ready for designer review; not approved for release. Stop here.**
No Beta, Mythic or other cue work may resume without explicit Eclipse approval.

## View the recordings

Open [the local review player](../../assets/cue/renders/vfx-upgrade/eclipse_review.html).
The local recordings are intentionally ignored by git, as required for checkpoint renders.

- [Moving camera, full → Lower effects](../../assets/cue/renders/vfx-upgrade/eclipse_comparison_orbit.mp4), 24 seconds.
- [Walking](../../assets/cue/renders/vfx-upgrade/eclipse_comparison_walking.mp4), 12 seconds.
- [Aiming, trail and pocketing](../../assets/cue/renders/vfx-upgrade/eclipse_comparison_pocket.mp4), 12 seconds.
- [Phone emulation, Lower effects, actual pull-bar shot](../../assets/cue/renders/vfx-upgrade/eclipse_review_phone_lower.mp4), 12 seconds.
- [Eight carriers, full → Lower effects](../../assets/cue/renders/vfx-upgrade/eclipse_review_eight.mp4), 16 seconds.

Left is the original pre-pass Eclipse from `5650020`, after the approved shared widening but
before any Eclipse VFX upgrade. Right is the current candidate. Both use the same width,
bright-lobby lighting, camera setup and shot inputs. The actual walking routes are affected
by collisions and are not frame-aligned. The orbit comparison trims 0.6 seconds from the
original recording to align the shared camera path after native capture startup. The pocket
comparison uses the same Studio fixture
and real match simulation; the separate phone shot uses the actual pull-bar input. No
Blender render is presented as gameplay. Native video capture hides HUD and runs at the
Studio session's approximately 15 fps; it is not evidence of physical phone performance.

## What changed

The rejected whole-aura sheets and ruled ribbon attempt are replaced by a genuinely dimensional
solar sculpture. An OpenAI-painted forked flame master was reconstructed in Meshy, reduced and
refitted in Blender, then formed into ten overlapping solar prominences with 31 bones.
Each prominence has independent root growth, curling and tip stretch; varied inclination and
depth reveal changing overlap as the camera moves. Painted ivory/gold cores and warm/violet
contours surround the black sphere. Two closed violet currents deform around the shaft;
separate orbital paths, travelling surges, sparse stars and small flame breakaways add motion.
Short-range, independently modulated gold and violet PointLights illuminate nearby surfaces.

The obsidian/gold cue retains its six moving emissive frames. Its short crescent wake now has
16 internally animated texture frames, a violet channel and separate celestial chips. The
pocket eclipse uses the same deforming flame sculptures, with staged rise/turn/fade, orbital
sweeps and actual local flash light. A legal winning eight retains its additional staged
sweep. Scratch and illegal-eight celebrations remain suppressed.

Main: **16 parts / 28,736 triangles**, versus the original 37 / 37,640. Pocket: **5 parts /
24,592 triangles**, shown briefly and subject to the existing multi-pot cooldown. No whole
aura is a camera-facing image. Small individual eruption particles remain textured sprites.

## Verification and practical limits

- Full and reduced motion captured in the real lobby, including oblique and edge-on views.
- Actual walking carrier and held cue inspected; aiming remains restrained and balls readable.
- Ordinary pocket shot captured under matching conditions; actual phone pull-bar input accepted
  with `shotSeq = 1` and the resulting pocket visible in the recording.
- Actual Settings Lower effects toggle was ON for the phone recording and restored OFF afterward.
- Studio assertions pass: skinned meshes follow their roots; bones change pose; Lower effects
  preserves major forms; AuraOff hides classified geometry; the short wake cycles frames and
  cleans up; scratch/illegal-eight suppression, legal-eight variant and multi-pot limits hold.
- Eight carriers retain their main forms in Lower effects. Physical iPhone frame rate and
  thermal behavior still require the designer's device; the capped Studio session cannot
  certify them. No controls changed; physical controller acceptance remains pending.
- Lint passes with the four existing shadow warnings. The full shared working-tree suite passed
  985 tests; the isolated Eclipse commit verifies all **984** of its tests. Its first run
  lacked the copied cue/map/table asset fixtures; after those were added, all 27 tests in
  the affected suites passed. Final regenerated motion fixtures pass. Paused Beta changes
  are excluded from this commit.

The new forms have actual depth and internal deformation. Their gold detail is deliberately
sharper and less hazy than the original. Whether that composition earns Secret quality is this
review's decision, not something inferred from asset generation or passing tests. Earlier
sheet/ribbon and rounded procedural variants remain failed checkpoints, not accepted results.

## Studio handoff

The active Edit-mode cue and piece libraries contain this Eclipse candidate. The original's
0.36-width cue template and its 37-piece ornament are also preserved separately under
`ServerStorage.CueVfxReview.Original`, labelled with their source revision. Original data and
recordings are retained locally under `renders/vfx-upgrade/original-baseline/`.

The Play session is left with the designer temporarily wearing Eclipse. This is an appearance
override, not an ownership or economy change, and lasts until Play stops. Walk around, enter
solo play and compare full/Lower effects. Stop Play to inspect imported Edit content.

After visual approval and milestone completion, the designer saves `place/8ball.rbxl` and
publishes. The candidate is not being published as an approved final effect. All other cues
remain paused for this review.
