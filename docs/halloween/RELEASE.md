# Halloween 2026: release checklist

For Justin. Tonight's build (Oct 29 evening): branch `halloween`, the commit the coordinator
names in STATUS. The code reads the clock: the event has been Live since 19:00 EDT Oct 28, so a
server with this update boots straight into Live. It ends by itself Nov 3 19:00 EST. Config line
numbers re-read 09:45 Oct 29.

## 1. Check by hand (Studio Play or the test place first, then the live game after the publish)

On a phone, a PC and a controller where you can:

1. Join on a **new account** and an **old account**. The tutorial shows nothing of Halloween
   until it is done or skipped.
2. Play one match. The result shows Candy: 3 a ball, +10 for finishing, +25 for a win.
3. **Walk around** while it is the other player's turn, and pick up **ground candy** (+1 each).
   A candy spawns near you about every 4 seconds, in a match too, so there are always a few
   around you.
4. The **HALLOWEEN** button opens the menu: the Candy balance, today's 4 quests, the three cues
   (Pitchfork 300 Candy or 49 R$, Witch's Broom 2,500 or 249 R$, Halloween Sword 7,500 or 599 R$)
   and the two Candy packs (300 for 49 R$, 1,200 for 149 R$). No Candy track, no Spider.
5. **Buy the Pitchfork with Candy** (play for it, or `/hw candy 300` on your account). The balance drops by
   300 and the cue is yours (My Cues). A Robux button opens the Roblox prompt (cancel it unless
   you want to test a real buy).
6. The **Pumpkin King** visits at :15 and :45 for 12 minutes. When he comes, players free in the
   lobby see a short black-bar cutscene of him rising out of the roof on his throne (a tap
   skips). Check his **cape**: smooth and swaying, also while he shoots. Beat him once: +150
   Candy, +$2,500, +100 XP, and the 5% Jack-o'-Lantern roll.
7. The **Pitchfork** has the old large fork at its tip (the end that hits the ball), on the card
   too; while you aim, the outer prongs fade so you aim at the middle point. The **Witch's
   Broom** is thinner than before. Look at the Pitchfork from another player's screen once: they
   see the whole fork at the tip.
8. Settings > **Lower effects** on and off with a Halloween cue.

## 2. Publishing

1. Use the **Team Create** Studio window ("[EMOTES] CRAZY 8 Ball"). Rojo must say connected.
   The folder must be clean (nothing uncommitted): Rojo ships whatever is in it.
2. **File > Publish to Roblox.**
3. Creator Hub > the game > **Configure > Server management > Restart Servers**, choose
   **"Restart only servers with outdated versions"**. Old servers have to go: their code has no
   Candy shop, still runs the Candy track and does not know the new cues.
4. Save the place to `place/8ball.rbxl` once (File > Save to File As), so git has the rebuilt
   Pitchfork and Broom templates.
5. Tell the coordinator it is out (the LIVE icon goes up then:
   `python3 tools/halloween/store_page.py icon-set LIVE --go`).

## 3. Every switch (Config, `src/shared/Config.luau`)

Off = the old behaviour; one line, then publish with the outdated-only restart.

| Switch | Line | Off does |
|---|---|---|
| `Config.Halloween.Enabled` | 3764 | no Candy, no event UI; saved Candy still converts after the end |
| `Config.Halloween.Rush.Enabled` | 3773 | no 2x Candy minutes (UTC :00-:09) |
| `Config.Halloween.Match` | 3784 | match Candy (3 a ball, 10, 25) |
| `Config.Halloween.Pickup` | 3815 | ground candy: 1 a pickup, 400 pickups an hour at most |
| `Config.Halloween.Quests.Enabled` | 3823 | no quest boards |
| `Config.Halloween.Cues.Enabled` | 3917 | the three cues cannot be bought (Candy or Robux) |
| `Config.Halloween.Packs.Enabled` | 3926 | Candy packs not sold |
| `Config.Halloween.Convert.Enabled` | 3929 | Candy does not turn into money ($10 each) after the end |
| `Config.HalloweenMap.Enabled` | 9281 | the master map switch: no night, tables, decor, props, throne, King, drops |
| `Config.HalloweenMap.Boss.Enabled` | 9488 | no Pumpkin King |
| `Config.HalloweenMap.Boss.Entrance.Enabled` | 9563 | he appears at once with the burst (no rise, no cutscene) |
| `Config.HalloweenMap.Boss.Entrance.Cutscene` | 9564 | the rise without the camera, bars and title |
| `Config.HalloweenMap.King.Cloth.Enabled` | 9710 | the old cape (three rigid boxes) |
| `Config.HalloweenMap.Candy.Enabled` | 9742 | no ground candy (`SpawnEverySeconds` 9743 sets how often, `MaxAlive` the most at once) |
| `Config.Multiplayer.Roam.Enabled` | 8341 | in-match players stay at their table, as before |
| `Config.Badges.Enabled` | 18344 | no badge is awarded |
| `Config.Economy.FriendBoostEnabled` | 2037 | no +10% per friend |

## 4. If something breaks

Tell the coordinator what you see. The coordinator flips the switch, commits and pushes; you
publish with the outdated-only restart. Cut order for a bad night: the cutscene
(`Boss.Entrance.Cutscene`), the cape (`King.Cloth`), the King (`Boss.Enabled`), the ground
candy (`HalloweenMap.Candy`), roaming, the badge queue, then the whole event
(`Halloween.Enabled`).

## 5. Nov 3, 19:00 EST

The event ends and converts Candy into money by itself. Rename the game back. The icon: set the
original back (asset 123614794049673):
`python3 tools/halloween/store_page.py icon-set 123614794049673 --go`.

## 6. What to read after launch (custom events and funnels)

- The `Halloween` funnel: 1_Button, 2_Opened, 3_FirstCandy, 4_Pitchfork, 5_Broom, 6_Sword (each
  cue owned however it was got).
- `HwBuy` (cue, Candy / Robux / Gift): which cues sell and how. `HwCandy` "Match" against
  `CandyPickups`: the 50/50 split the designer asked for. `HwPack`, `HwQuest`, `HwKing`,
  `HwMenu`, `HwConvert`.
- `KingCutscene` (Shown / Skipped / Cut / Done): how many skip it.
- The model to compare with (ECONOMY, "Halloween Candy and the event cues"): ~280 Candy an hour
  from matches and ~270 from the ground; the Pitchfork in ~25 min, the Broom in ~4 h, the
  Sword in ~13-15 h of play.
- Creator Hub: server FPS P10/P50, client memory, concurrent users, the error report. Alarms:
  P10 under 20 for an hour, or memory P50 over about 200 two hours running.

## 7. Discord announcement (draft; you post it)

> 🎃 **The HALLOWEEN UPDATE is live!** 🎃
> The rooftop has gone haunted. Play matches and grab **Candy** all over the lobby (even while
> you wait for your turn), finish daily quests, and spend your Candy on Halloween cues that
> never come back: the **Pitchfork**, the **Witch's Broom** and the **Halloween Sword**. The
> **Pumpkin King** rises at :15 and :45 every hour: beat him for Candy, money and XP, and a
> **5% chance at the Jack-o'-Lantern Cue**! Play in the first 10 minutes of every hour for
> **2x Candy**. Ends Nov 3!
