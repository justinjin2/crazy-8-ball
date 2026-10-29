# Halloween simplified: menu v4, buying, HUD pills, Shop banner (brief, 2026-10-29)

For a fresh session on branch `halloween` in `~/Desktop/8ball`. Read CLAUDE.md, `docs/STATUS.md`
(Halloween section) and the designer's 2026-10-29 ~05:30 line in `docs/DECISIONS.md` first.
**The release waits for this work: do not tell the designer to publish until it is done.**
Keep the cost low: no multi-agent workflows unless a check really needs one.

## Done (pushed)

- Night all event, the moon out, no Sunset (`Config.HalloweenMap.Night.Permanent`, 4d8a1bce).
- The four event cues show as Unique tier, pink (Rarity Unique, Group still Exclusive, d20abb8d).
- The Spider playtime reward is off (`Config.Halloween.Spider.Enabled = false`, 34af660b).
- The money boost card: a Friends row at +0% too, and no grey friend rule (35509c21,
  Studio-checked).
- The Candy boost line's own card: CANDY BOOST with the Rush x2, Friends and Group rows and the
  Total; the Rush countdown, or the next Rush, at its foot. The separate Rush pill is gone
  (`Config.UI.BoostPill.Chip.Shown = false`, 4f06e8ad, Studio-checked). Follow-up: the Rush
  row's candy icon doesn't draw.

## To build, in this order (one commit each)

1. **The Halloween menu redo, lively** (`.claude/skills/lively-gui/SKILL.md`, a big screen).
   The target (gate A) is approved: mock **A**,
   `~/Desktop/8ball-refs/halloween/mocks/v4/A.png` (B, not chosen, beside it). It has:
   - The lively frame: the title, a Candy pill in place of the money pill, ENDS IN, and the X.
   - A top row of four pink UNIQUE cue cards:
     - Pitchfork, Witch's Broom and Halloween Sword, each with a big green Robux button (with
       a gift square, shining) over a smaller orange Candy button.
     - The Jack-o'-Lantern, with a PUMPKIN KING DROP 5% ribbon and no buy buttons.
   - TODAY'S QUESTS: only the current board, no day tabs, a "new quests in" timer.
   - GET CANDY: the two packs.
   - No track, no playtime cue, no Candy Rush bar.

   **The card art is rendered from the real in-game cue models**, not the mock's drawings
   (designer). Next gate: B, the art sheet. Keep the menu at most 66% of the screen wide, and
   the first screen must fit a phone.
2. **Buying.**
   - Candy prices: Pitchfork 500, Witch's Broom 1,500, Halloween Sword 5,000.
   - Direct Robux prices: 149 / 399 / 999. These need three new developer products. Create
     them through Open Cloud if the key allows; otherwise the designer creates them.
   - Purchase handling must be server-validated and replay-safe. Reuse the parked Limited
     card's flow on `origin/hw-core-limited`.
   - Owned cues show OWNED.
   - **The designer knows the prices are off** (2,000 Candy for 149 R$ undercuts the direct
     buttons) and will fix them later. Build with these numbers, all in Config.
3. **Remove the Candy track**: Config Track, the Ledger steps and the funnel steps. Candy is
   saved and spent. Leftover Candy still turns into money after the end.
4. **Remove the Spider fully** (17 files: `grep -rln "SpiderCue\|Halloween.Spider\|HwSpider"
   src tests`). It never went live, so no real save holds it; the save-schema test may still
   name the field.
5. **HUD:** done. The Candy pill sits right above the money pill (`Config.UI.BoostPill.CandyPill`,
   Studio-checked on PC). Check it by hand on a phone, and check that tapping it opens the menu.
6. **The Shop banner**: a small Halloween banner at the top of the Shop that opens the event
   menu. There are no Halloween lucky blocks.
7. **The Pitchfork model**: the fork must be the cue's TIP, the end that hits the ball
   (designer). Flip it in `src/shared/CueSkins/Skins/PitchforkCue.luau` and its pieces, then
   rebuild its template in Team Create (`tools/build_cue_templates.luau`, ONLY = PitchforkCue).
8. The Jack-o'-Lantern stays the Pumpkin King's 5% drop only. The King stays for now; the
   designer may change him later, so ask first.

Then do the fresh-player run in Studio, update STATUS and RELEASE, and give the publish handoff.
