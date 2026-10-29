# Halloween 2026: release checklist

For Justin. Tonight's build (Oct 29 evening, v3): branch `halloween`, the commit the coordinator
names in STATUS. The code reads the clock: the event has been Live since 19:00 EDT Oct 28, so a
server with this update boots straight into Live. It ends by itself Nov 3 19:00 EST. Config line
numbers re-read 14:00 Oct 29.

## 1. Check by hand (Studio Play or the test place first, then the live game after the publish)

On a phone, a PC and a controller where you can:

1. Join on a **new account** and an **old account**. The tutorial shows nothing of Halloween
   until it is done or skipped.
2. Play one match against a person (or the bot a search finds). **Every ball you pot pays +3
   Candy** (+4 now and then with a boost): a little candy pops out under the cash and flies into
   the Candy pill, which counts up as each lands. After the result, one "+N" chip with the
   match's total flies to the HALLOWEEN button. PC practice and solo pay no Candy.
3. **Walk around** while it is the other player's turn, and pick up **ground candy** (+1 each).
   One spawns near you about every 4.5 seconds, in a match too; at most 150 an hour.
4. The **HALLOWEEN** button opens the menu: the Candy balance, today's 4 quests, the four cues in
   order (Pitchfork 300 Candy or 49 R$, Witch's Broom 2,500 or 249 R$, **Jack-o'-Lantern 4,500 or
   399 R$**, Halloween Sword 7,500 or 599 R$) and the two Candy packs (300 for 49 R$, 1,200 for
   149 R$). The cards' 8-balls drift, each card plays its cue's effects live (more up the
   ladder), and each has a small "2026" pumpkin badge. The pink edges are whole. Studio shows the
   Robux prices about 20% lower (40/200/320/480): that is Roblox's own regional price for your
   account; the products on Roblox are 49/249/399/599 (checked 13:50).
5. **Buy the Pitchfork with Candy** (play for it, or `/hw candy 300` on your account). The balance
   drops by 300 and the cue is yours (My Cues, with the 2026 badge). A Robux button opens the
   Roblox prompt (cancel it unless you want to test a real buy).
6. **No Pumpkin King**: no throne, timer, banners, sign or cutscene anywhere.
7. The cues:
   - **Pitchfork**: its outer prongs stay while you aim and shoot; the two tip flames are small
     and steady. Look once at a short bridge: does your bridge hand touch the curving prongs?
   - **Jack-o'-Lantern**: the laugh on a pot is much quieter and only heard near the table; the
     rising pumpkin head is the focus.
   - **Witch's Broom**: a pot shows a witch's hat drawn in stars and the witch sweeping across it
     (no rings, no moon). On your back the straws no longer touch the floor.
   - **Halloween Sword**: painted purple flames on the blade, a dark purple flaming trail, and a
     big laughing purple fire face out of the pocket.
8. Settings > **Lower effects** on and off with a Halloween cue.
9. The **abilities** screen says "USE CODES 5KLIKES & 10KLIKES FOR FREE SPINS". 10KLIKES gives
   10 spins and $10,000, 5KLIKES 5 spins and $5,000, 2KLIKES 10 spins and $10,000; 1KLIKES is
   expired.

## 2. Publishing

1. Use the **Team Create** Studio window ("[EMOTES] CRAZY 8 Ball"). Rojo must say connected.
   The folder must be clean (nothing uncommitted): Rojo ships whatever is in it.
2. **File > Publish to Roblox.**
3. Creator Hub > the game > **Configure > Server management > Restart Servers**, choose
   **"Restart only servers with outdated versions"**. Old servers have to go: their code has no
   Halloween at all.
4. Save the place to `place/8ball.rbxl` once (File > Save to File As), so git has the rebuilt
   Witch's Broom templates.
5. Tell the coordinator it is out. The coordinator then updates the game's description (the
   5KLIKES and 10KLIKES codes, next code at 25K likes) and sets the LIVE icon
   (`python3 tools/halloween/store_page.py icon-set LIVE --go`).

## 3. Every switch (Config, `src/shared/Config.luau`)

Off = the old behaviour; one line, then publish with the outdated-only restart.

| Switch | Line | Off does |
|---|---|---|
| `Config.Halloween.Enabled` | 3771 | no Candy, no event UI; saved Candy still converts after the end |
| `Config.Halloween.Rush.Enabled` | 3780 | no 2x Candy minutes (UTC :00-:09) |
| `Config.Halloween.Match.Enabled` | 3798 | no match Candy at all |
| `Config.Halloween.Match.PerPocketEnabled` | 3799 | the old settle-time Candy (3 a ball, +10 finished, +25 a win, no flying chips) |
| `Config.Halloween.Pickup` | 3836 | ground candy: 1 a pickup, 150 pickups an hour at most |
| `Config.Halloween.Quests.Enabled` | 3848 | no quest boards |
| `Config.Halloween.Cues.Enabled` | 3952 | the four cues cannot be bought (Candy or Robux) |
| `Config.Halloween.Packs.Enabled` | 3962 | Candy packs not sold |
| `Config.Halloween.Convert.Enabled` | 3965 | Candy does not turn into money ($10 each) after the end |
| `Config.HalloweenMap.Enabled` | 9319 | the master map switch: no night, tables, decor, props, drops |
| `Config.HalloweenMap.Boss.Enabled` | 9529 | false for this release: no Pumpkin King |
| `Config.HalloweenMap.Candy.Enabled` | 9783 | no ground candy (`SpawnEverySeconds` 9787 sets how often) |
| `Config.Multiplayer.Roam.Enabled` | 8379 | in-match players stay at their table, as before |
| `Config.UI.Halloween.CardFx.Enabled` | 17772 | the menu cards' live effects off (still pictures) |
| `Config.UI.EventEmblem.Enabled` | 18081 | no "2026" badge on the event cues' cards |
| `Config.Badges.Enabled` | 18648 | no badge is awarded |
| `Config.Economy.FriendBoostEnabled` | 2037 | no +10% per friend |

## 4. If something breaks

Tell the coordinator what you see. The coordinator flips the switch, commits and pushes; you
publish with the outdated-only restart. Cut order for a bad night: the menu cards' effects
(`CardFx`), the flying pocket Candy (`Match.PerPocketEnabled`: back to settle-time Candy), the
ground candy (`HalloweenMap.Candy`), roaming, the badge queue, then the whole event
(`Halloween.Enabled`).

## 5. Nov 3, 19:00 EST

The event ends and converts Candy into money by itself. Rename the game back. The icon: set the
original back (asset 123614794049673):
`python3 tools/halloween/store_page.py icon-set 123614794049673 --go`.

## 6. What to read after launch (custom events and funnels)

- The `Halloween` funnel: 1_Button, 2_Opened, 3_FirstCandy, 4_Pitchfork, 5_Broom, 6_Jack,
  7_Sword (each cue owned however it was got). Retune if 4_Pitchfork is under ~30% of
  3_FirstCandy.
- `HwCandy` "Match" (one a match, its pots' total) against `CandyPickups` (the ground) and
  `HwQuest`: the three thirds the designer asked for (no source past ~45%). `HwMatch` (a: Paid /
  Disguised / PC / Tutorial) for the share of matches that pay.
- `HwBuy` (cue, Candy / Robux / Gift): which cues sell and how. `HwPack`, `HwMenu`, `HwConvert`.
- The model to compare with (ECONOMY, "Halloween Candy and the event cues"): ~170 Candy an hour
  from pockets and ~130 from the ground, 560 a day from quests; the Pitchfork in ~17-22 min, the
  Broom ~4.6 h, the Jack ~8.4 h, the Sword ~14.4 h of play (each saved for alone).
- Creator Hub: server FPS P10/P50, client memory (phones especially: the menu's card effects
  use the cues' particle sheets), concurrent users, the error report. Alarms: P10 under 20 for
  an hour, or memory P50 over about 200 two hours running.

## 7. Discord announcement (draft; you post it)

> 🎃 **The HALLOWEEN UPDATE is live!** 🎃
> The rooftop has gone haunted. Every ball you pot pays **Candy**, candy drops all over the
> lobby (grab it while you wait for your turn), and daily quests pay more. Spend it on four
> Halloween cues that never come back: the **Pitchfork**, the **Witch's Broom**, the
> **Jack-o'-Lantern** and the **Halloween Sword**. Play in the first 10 minutes of every hour
> for **2x Candy**, and all day on Oct 31! Codes **5KLIKES** and **10KLIKES** for free spins.
> Ends Nov 3!
