# Morning report: Ultimates (overnight, 2026-09-28)

Everything is on the branch **`ultimates`** (made from `economy`, pushed; nothing touched
`main`, `ranks-money` or `economy`). Ults are in the game: a bar fills during a match, one press
arms your ult for your next shot, and a manga cutscene plays for both players. **Magnet** is
the first real ult. The spin screen rolls ults into three slots, and the other 12 ults exist
as placeholder rows. The spin screen is hidden from live players until more ults are built
(`Config.Ults.ScreenLive = false`); in Studio it always shows.

## 1. What to try first (about 15 minutes)

1. In a terminal in the project folder: `git switch ultimates`, then
   `rojo serve default.project.json`. In Studio, click **Connect** in the Rojo plugin.
2. Press **Play**. For a match, use Studio's **Test > Clients and Servers** with 2 players and
   walk both onto a **1v1** pad, or play a real match with a friend. On your own, the **solo**
   button on a pad gives a Practice ult instead of a bar.
3. In a match, type these in chat (only you and listed developers can use them; `/ulthelp` lists them all):
   - `/ultfull`: your bar fills. On your turn it turns gold, shakes and reads **PRESS [G] TO
     ACTIVATE** (on a phone: tap the bar; on a controller: the X / Square button).
   - Press **G**: the cutscene plays (your avatar in a tilted manga panel, "ULTIMATE",
     "Magnet"), then "MAGNET: NEXT SHOT" and two red and blue rings circle the cue ball.
   - Shoot a ball that *just* misses a pocket: Magnet bends it in (a blue glow on the ball,
     a ring at the pocket, a clunk and a zap). Balls that miss by a lot still miss.
   - `/ultbar 60`: the bar at 60%. `/opult`: fills the other side's bar (Studio only). `/ultarm`: skips straight to armed.
   - Solo (the solo pad): a **Practice ult** button instead of a bar, free, any time on your
     turn.
4. The spin screen: click **Ults** on the left column (under Trade; a red "!" means today's
   free spin is ready). Press **FREE SPIN**: the name cycles, then lands, and your avatar gets
   an aura in the ult's colour. Things to try there:
   - The lock icon on a slot card: SPIN turns into SLOT LOCKED.
   - The **$** button, then **BUY 1**: $1,750 for a spin.
   - The code box: type **ULTS** and press Redeem (+3 spins, once).
   - `/pity 99` then a spin: guaranteed Epic or better, with a PITY! tag. With only Magnet
     built that still gives Magnet; add `/ultsall on` to see the rare ones and their auras.
   - Spinning onto a slot that holds an Epic or better asks "Replace ...?" first.
   - `/fastopen on`: Skip and **AUTO SPIN** (stop at Rare+, Epic+ or Legendary+).
   - **BACK TO MENU** (or Esc) brings the game back as it was.
5. Money and spins: `/spins 25`, `/lucky 3`, `/pity 99` (the next spin is Epic or better),
   `/freespin` (today's free spin again), `/ult black flash` (puts any ult in your slot),
   `/ultsall on` (placeholders roll and play too, for testing).
6. The global queue: the Join card has **Ults: On / Off**. Off only meets other Off players;
   after 30 s alone it offers "Search with ults on?".

## 2. What was built, in plain words

- **The bar** (bottom centre, only on your turn). It fills when you pot your own balls
  (+10, +8, +6, +5, then +3 in one turn), on a NICE SHOT (+20), when your opponent pots
  (+8 plus 7 for every ball you are behind), and a little at each turn's end. Classic tables
  fill 1.3 times faster. After your first ult it fills at a quarter of the speed; at most 2
  ults a match. Gains made on the opponent's turn wait and count up when your turn starts.
- **Activating.** Only on your turn, before the shot, never on the break. A 1.6 s cutscene for
  everyone at the table, then about a second before it arms; the shot clock pauses meanwhile.
- **Magnet.** For one shot, your own balls that are about to miss a pocket by a little are
  pulled in. Never the cue ball, never the opponent's balls, the 8 only on your legal 8 shot
  toward the called pocket.
- **The PC opponent's rule** (for when bots exist): it uses its ult when its bar is full and
  it is behind, or when it sees no easy shot.
- **Where ults show:** the opponent's ult icon on the top bar lights up when their ult is
  ready; "Opponent's ult: MAGNET" when theirs is armed; the controller guide lists "Ult"; a
  "NO ULTS" pill on the match bar and result screen for No-ults queue games.
- **Getting spins:** 3 to start, a free spin every day, rank-ups (1 to 3 per tier), streak
  day 7 (+2), the day's last playtime gift (+1), the code **ULTS** (3 spins), $1,750 a spin,
  or Robux. The NEW RANK! popup, the roadmap, the Rewards menu and the codes box all show
  spins with the spin icon.
- **NEW RANK! now dims the screen** a little (your request): black at half strength, big
  enough that no edge shows on any screen.
- **The spin screen:**
  - Three slot cards (slot 1 free; slots 2 and 3 are game passes).
  - The CURRENT ULT name and line over your avatar, in a dark stage room with an aura in the
    ult's rarity colour.
  - The true odds on the right (normal and Lucky), the pity counter, and the code box.
  - Robux and money buy buttons, SPIN, Lucky Spins, and Auto Spin for Fast Open owners.
  - On a phone the odds and the buy buttons move into popups.
  - It is hidden from live players (`Config.Ults.ScreenLive`) until more ults are built;
    Studio and `/ultsall on` always show it.
- **Dev commands:** `/ulthelp` lists `/ultbar`, `/ultfull`, `/ultarm`, `/opult`, `/spins`,
  `/lucky`, `/pity`, `/freespin`, `/ult`, `/ultsall`.

## 3. What was verified, and how

- **Tests:** lint clean; 729 Lune tests pass (fill, roll odds and pity, slots and locks,
  match rules, Magnet's harness, the spin service, the queue pools, the save migration).
- **The model** (`tools/ult_model.py`, reading Config's real numbers, 10,000 matches a row):
  - How often **both players use an ult** (a player who runs out the whole rack in one turn
    left out):

    | Table | Players (pot rate) | Both use an ult | Second ults |
    |---|---|---|---|
    | Classic | weak 0.45 vs 0.45 | 95.0% | 1.8% |
    | Classic | average 0.62 vs 0.62 | 90.9% | 0.3% |
    | Classic | strong 0.80 vs 0.80 | 84.9% | 0.1% |
    | Classic | strong vs weak | 86.7% | 0.1% |
    | Difficult | weak 0.30 vs 0.30 | 95.0% | 0.4% |
    | Difficult | average 0.45 vs 0.45 | 92.8% | 0.1% |
    | Difficult | strong 0.60 vs 0.60 | 86.4% | 0.0% |

    The worst row is 84.9%, over your 80% goal; second ults stay under 2%.
  - **Missing on purpose doesn't pay:** a player who misses to farm the bar wins only 25-28%
    against an honest equal player.
  - **The power ladder:** a top ult (2-3 sure balls) against Magnet between equal players wins
    61-64%. A 50% shooter with a top ult against a 60% shooter with Magnet wins 48.7% (the
    same pair with Magnet each: 34.4%), so a top ult nearly closes a 10-point skill gap
    without flipping it.
- **Magnet's measured value** (a Lune harness shooting thousands of real near misses through
  the physics): it drops 87.8% of misses within a quarter to one ball width, 28.4% of misses
  1-2 widths out, none past 2.5 widths, and every jaw rattle; direct pots are unchanged. That
  is about **+0.41 of a ball per use**, against the ladder's Common target of about 1/3
  (+0.30). I kept it (your call, see section 7).
- **In Studio** (PC window, the QA opponent):
  - The opponent potted four of its balls with real shots: my bar went 20, 49, 87, 100.
  - My turn: "+100" counted up, READY, **G** played the cutscene, the armed pill showed.
  - A 2 degree miss with Magnet dropped. The replay carried the effect and the client drew
    the pull (beams, pocket ring, sounds, spark burst).
  - The PC rule held its ult while level with an easy shot and used it once 3 behind.
  - Solo Practice armed Magnet with no bar.
  - The bar built into 750 x 361 and 844 x 390 phone frames: readable, nothing clipped.
  - Every `/ult...` command answered correctly, bad input answered its usage.
  - Two No-ults searches paired with each other and never with an On search; the match
    record says No ults.
  - NEW RANK!'s dim measured at 3458 x 1800 on a 1529 x 758 screen.
  - An old save moved to the new version (Magnet in slot 1, 3 spins).
  - **The spin screen**, clicked through by hand in Studio:
    - The free spin.
    - The pity spin landing an Epic (Portals) with PITY!.
    - The Replace question (Keep keeps it).
    - A lock turning SPIN into SLOT LOCKED.
    - $1,750 buying one spin.
    - The ULTS code giving 3.
    - A Lucky Spin landing an Uncommon.
    - `/buy spin10`, `/buy lucky3` and `/buy ultslot2` granting (slot 2 became selectable).
    - Auto Spin stopping on a Rare.
    - Closing, which brought the camera and HUD back.
    - Laid out at 750 x 361, 844 x 390 and tablet size.
  - The console stayed clean.
- **Audit:** a fresh reviewer read every path that grants spins, money, rolls or ults as
  an attacker would. No critical or high issues. I fixed 3 medium and 5 low ones:
  - The shop could prompt spin packs before Roblox's PolicyService answered.
  - Solo practice shots paid money.
  - A Lucky Spin could land a Common. It now never does; with only Commons built, Lucky
    Spins wait.
  - `/ultsall` didn't reach matches.
  - Lobby hosts could still switch ults off.
  - A free spin could repeat around midnight between two servers.
  - `/opult` worked in live games.
  - Money could buy spins past the 100,000 cap.

## 4. Every overnight assumption (overrule any of them)

Each is also a dated line in `docs/DECISIONS.md`.

- Fill numbers re-tuned from the brief's first guess (own balls +10/+8/+6/+5 then +3, x0.25
  after your first ult) so "both players use an ult" holds at 85%+.
- Magnet kept at its measured strength (+0.41 ball) pending your call.
- The PC opponent's ult rule is a policy only; bots don't exist yet.
- No-ults search: Yes moves only this search (your saved toggle stays Off); No hides the
  offer for that search; the toggle is hidden while searching; "Play another" stays in the
  arena's pool.
- Restricted players (PolicyService) can't buy spins but can use free and owned ones.
- Rank-up spins paid on reaching a tier's division I; the last playtime gift adds a spin;
  an ult icon also shows beside a teammate; an unknown difficulty fills at x1.
- Spin screen: gamepad X opens it in the hub; Robux is the default buy mode; the free-spin
  line only in the leave reminder; closing stops Auto Spin; the stage room sits far off the
  map only while open; Mythic's name shimmers pastel while its aura is red-black.
- A Lucky Spin never lands a Common; while only Commons are built, Lucky Spins and their
  products are refused ("Lucky Spins open once rarer ults are in the game").
- Solo practice shots pay nothing and count nothing.
- Lobby tables always have ults on; only the global queue's No-ults arenas turn them off.
- NEW RANK! dims the screen (your request), as an exception to "popups never dim".

## 5. Known issues and anything BLOCKED

- **Nothing is BLOCKED.**
- **Not checkable in Studio:** gamepad buttons (Studio refuses to fake them), a real phone's
  touch, and a second real player seeing your cutscene.
- **Audit L4 (left):** every player's exact bar percentage is in the table data everyone
  receives, so a hacked client could show the opponent's exact bar. The HUD only shows
  "ready". Fixing it means sending each player their own copy; parked for later.
- **Placeholders:** the other 12 ults are names only. Their cutscene plays, then "Coming
  soon". Live players can never roll them.
- **Lucky Spins today:** with only Magnet (Common) built, Lucky Spins are refused and their
  products say so. They open automatically once an Uncommon or better ult is built.
- **The pretend opponent's cutscene** shows an ink silhouette (no avatar); real players and
  bots will show their avatar.
- **Magnet's look is quick:** the pull lasts only while the ball crosses the pocket's mouth
  (I let the glow linger 0.5 s). Judge it by hand.

## 6. Turning on the Robux items (click by click)

Everything is built; only the ids are missing. While an id is 0 a Robux button shows "Soon".
You make each item once in the Creator Hub, paste its number into `src/shared/Config.luau`
(`Config.Products.List`), and it works. The spin screen also needs
`Config.Ults.ScreenLive = true` before live players see it.

**A. The developer products** (bought again and again):
1. Open https://create.roblox.com, **Creations**, the game **Crazy 8 Ball**.
2. Left menu: **Monetization > Developer Products > Create a Developer Product**.
3. Name, description, icon (from `assets/ui/icons/`) and price as below; **Create**.
4. Copy its **Product ID**, then in `Config.Products.List` replace that row's `Id = 0` with
   the number. Save (Rojo sends it to Studio).

| Config key | Name | Price (R$) | Icon file | Description |
|---|---|---|---|---|
| Spin1 | 1 Ult Spin | 15 | ult_spin.png | One spin on the Ults screen. The odds are on the screen. |
| Spin5 | 5 Ult Spins | 50 | ult_spin.png | Five spins (was 75). |
| Spin10 | 10 Ult Spins | 100 | ult_spin.png | Ten spins (was 150). |
| Spin50 | 50 Ult Spins | 449 | ult_spin.png | Fifty spins (was 750). |
| Lucky1 | 1 Lucky Spin | 49 | lucky.png | A spin that never lands Common. The odds are on the screen. |
| Lucky3 | 3 Lucky Spins | 129 | lucky.png | Three Lucky Spins (was 147). |

**B. The game passes** (bought once):
1. **Monetization > Passes > Create a Pass**; name, description, icon; **Create Pass**.
2. Open it, **Sales**, switch **Item for Sale** on, set the price, **Save**.
3. Copy its ID into `Config.Products.List` the same way.

| Config key | Name | Price (R$) | Icon file | Description |
|---|---|---|---|---|
| UltSlot2 | Ult Slot 2 | 59 | ults.png | A second ult slot: keep one ult and spin another. |
| UltSlot3 | Ult Slot 3 | 99 | ults.png | A third ult slot. |

**C. Test in Studio without Robux:** `/buy spin10`, `/buy lucky1`, `/buy ultslot2` run the
same grant as a real purchase. With real ids, Studio's test purchase box works too.

**D. Paid random items:** spins are paid random items, so Roblox requires the odds on screen
(they are, always) and PolicyService: where paid random items are not allowed, the spin
buttons for money and Robux are refused, while free and already-owned spins still work.

## 7. What needs you

- **Magnet's strength:** it rescues about 0.41 of a ball per use; the ladder's Common target
  is about 0.30. Weaker: lower `Config.Ults.Magnet.CaptureBallWidths` (3) or `Power` (1).
- **A real phone and a real controller:** tap the bar to activate, the X / Square button,
  and the spin screen by touch and gamepad.
- **Two real players:** the cutscene on the other player's screen, and the opponent's icon
  and pill.
- **The product and pass ids** (section 6), then a **publish** and one real purchase.
- **`Config.Ults.ScreenLive = true`** when enough ults are built to open the spin screen.
- **Save the place** to `place/8ball.rbxl` and publish once you're happy (this milestone
  added art ids only; nothing expensive lives only in the place).

## 8. Next session

**Eagle's Eye** (Common): its own brief, built to the ladder's Common row, with a harness
like Magnet's. After it: Super Bounce, then the Uncommons. Every new ult is one
`src/shared/Ults/Effects/<Id>.luau`, its catalog row's `Built = true` and `Effect`, its look
module on the client, and its test.

## 9. Uploaded images (group 675425213)

The uploader returns a Decal id; the game uses the image id inside it (STUDIO_NOTES).

| File | Decal id | Image id (in Config) |
|---|---|---|
| ults.png | 134987873534606 | 116359776498638 |
| ult_badge.png | 129539443325735 | 132970855167502 |
| ult_badge_gold.png | 99530249381002 | 74974990816876 |
| lucky.png | 71752745751886 | 97997677415172 |
| ult_spin.png | 83339327565913 | 76372169720993 |
| ult_backdrop.png | 98881182064534 | 121308269711722 |
| aura_flame.png | 82997454954024 | 90187359321182 |
| field_lines.png | 126008179443843 | 132811450841753 |
| ring_glow.png | 100993435112539 | 121133273572178 |
| spark.png | 121833848983877 | 131919576694289 |
| soft_glow.png | 109949034902778 | 121163827465552 |

While moderation was slow, aura_flame.png was uploaded three times and field_lines.png twice.
The extra copies are unused, and you can archive them in the Creator Hub. No audio was
uploaded: the ults use your two sounds and Roblox library sounds.
