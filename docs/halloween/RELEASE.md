# Halloween 2026: release checklist

For Justin, tonight (Wed Oct 28 2026). The event goes live at **19:00 EDT** by itself (the
code reads the clock); the publish only has to be out before then. DRAFT 12:00, final at 16:45
(the cue rework and the boost pill restyle land until 16:00; line numbers are re-read then).

## 1. Check by hand (test place or Studio Play, then on the live game after the publish)

On a phone, a PC and a controller where you can:

1. Join on a **new account** and an **old account**. The tutorial shows no Halloween popups
   until it is done or skipped.
2. Play one match. The result shows Candy: 3 a ball, +10 for finishing, +25 for a win.
3. The **HALLOWEEN** button (right side) opens the menu: the Candy track, quests, the Spider,
   the Candy packs.
4. The **Pumpkin King**: he visits the middle of the roof at :15 and :45 past every hour for 12
   minutes (the top pill counts down, then "PUMPKIN KING IS HERE!"; tap it for the arrow).
   Challenge him once; a first win in a visit pays +150 Candy, +$2,500 and +100 XP.
5. Pick up a **lobby Candy**.
6. The boost text (Money Boost / Candy Boost) and its card.
7. **Walk around** while it is the other player's turn.
8. A **Candy pack** prompt opens (cancel it; don't buy).
9. Each new cue: Candy Corn, Jack-o'-Lantern, Black Cat, Spider, Witch Broom (My Cues and the
   Index, in hand, one pot).
10. Settings > **Lower effects** on and off with a Halloween cue.

## 2. Publishing (about 18:30)

1. Use the **Team Create** Studio window ("[EMOTES] CRAZY 8 Ball"). Rojo must say connected,
   and the coordinator says which commit it is synced at. The folder must be clean (nothing
   uncommitted).
2. **File > Publish to Roblox.**
3. Creator Hub > the game > **Configure > Server management > Restart Servers**, choose
   **"Restart only servers with outdated versions"**, with no delay longer than 10 minutes.
   Old servers have to be gone before 19:00: old code resets an equipped new cue to Classic
   (`SaveSchema.luau` refuses newer saves) and pays no Candy. Servers also restart by
   themselves after 5-6 h (`Config.ServerRestart`).
4. Rename the game by hand at 19:00: add the pumpkin (your words: "[🎃] … nothing else").

## 3. What you should see

- **Before 18:30:** nothing new except the boost text.
- **18:30:** the countdown banner only.
- **19:00:** night falls on the rooftop; the event tables, trees, pumpkins and lights; the
  HALLOWEEN button; the King's timer pill (his first visit is 19:15); Candy in matches and
  lobby pickups; and a **2x CANDY** chip at once (19:00 EDT is UTC minute 0, the start of a
  Candy Rush).
- **The store page (automatic):** the icon counts down 5H at 14:00, 4H, 3H, 2H, 1H, then LIVE
  at 19:00 and the plain icon at 19:00 Oct 29 (`tools/halloween/store_page.py icon-schedule`,
  log in `~/Desktop/8ball-refs/halloween/shots/coordinator/store/log.txt`). Your Experience
  Event runs 19:00 Oct 28 to 19:00 Nov 3 (times fixed by API at 11:54; nothing else changed).

## 4. Every switch (Config, `src/shared/Config.luau`)

Off = the old behaviour; one line, then publish with the outdated-only restart.

| Switch | Line (12:00) | Off does |
|---|---|---|
| `Config.Halloween.Enabled` | 3763 | no Candy, no event UI; saved Candy still converts after the end |
| `Config.Halloween.Rush.Enabled` | 3772 | no 2x Candy minutes |
| `Config.Halloween.Match.Enabled` | 3783 | no match Candy |
| `Config.Halloween.Quests.Enabled` | 3797 | no quest boards |
| `Config.Halloween.Spider.Enabled` | 3886 | no Spider active-time cue |
| `Config.Halloween.Packs.Enabled` | 3892 | Candy packs not sold |
| `Config.Halloween.Convert.Enabled` | 3894 | Candy does not turn into money after the end |
| `Config.HalloweenMap.Enabled` | 9219 | the master map switch: no night, tables, decor, props, throne, King, drops |
| `Config.HalloweenMap` Night / Tables / Decor / Props / Throne / Boss / Candy | 9230-9517 | each part alone (Throne and Boss go off together) |
| `Config.HalloweenMap.Boss.Mode` | 9422 | `"Throne"`: the King sits on his throne at the piano all event (the old way) instead of visiting |
| `Config.Halloween.Boss.Visit` | 3796 | the King's visit reward (Candy 150, Money 2500, Xp 100): one line to change |
| `Config.CueSkins.Bodies.Enabled` | 6560 | the body cues draw the normal stick |
| `Config.Multiplayer.Roam.Enabled` | 8287 | in-match players stay at their table, as before |
| `Config.Badges.Enabled` | 17986 | no badge is awarded |
| `Config.Economy.FriendBoostEnabled` | 2037 | no +10% per friend |
| `Config.UI.BoostPill.Enabled` | 10016 | the old VIP tag instead of the boost text |
| `Config.UI.CuePreview.Enabled` | 10083 | already off |

## 5. If something breaks

Tell the coordinator what you see. The coordinator flips the switch, commits and pushes;
you publish with the outdated-only restart. Cut order for a bad night (PLAN): the King, then
the lobby drops, then roaming, then the badge queue, then the whole event (`Halloween.Enabled`).

## 6. Nov 3, 19:00 EST

The event ends and converts Candy into money by itself; the Experience Event ends itself.
Rename the game back (`[EMOTES] CRAZY 8 Ball`, or what you choose then). The icon: set the
original back (asset 123614794049673): `python3 tools/halloween/store_page.py icon-set 123614794049673 --go`.

## 7. What to read after launch (custom events and funnels)

- Core: the `Halloween` funnel (1_Button, 2_Opened, 3_FirstCandy, 4_Cue150, 5_Cue500,
  6_Cue2000, 7_Broom) and `HwCandy`, `HwMatch`, `HwQuest`, `HwTrack`, `HwSpider`, `HwPack`,
  `HwConvert`, `HwMenu`.
- Cues A: `HalloweenCueEquipped` (counts every Equip press, not distinct players).
- Sys: `RoamHome` (how far players roam), `BadgeAwarded` (Retro back-pay on day one).
- GUI: `FriendBoost` (friends at leave), `BoostCard` (card opens).
- Creator Hub: server FPS P10/P50, memory, concurrent users, the error report. Baselines:
  server FPS P10 about 37-47; DAU 24,887 and 23.1 min per DAU (Oct 26).

## 8. Discord announcement (draft; you post it)

> 🎃 **The HALLOWEEN UPDATE is live!** 🎃
> The rooftop has gone haunted. Play matches to collect **Candy**, finish daily quests and
> unlock **5 Halloween cues** that never come back: Candy Corn, Jack-o'-Lantern, Black Cat,
> Spider and the Witch's Broom. The **Pumpkin King** visits the middle of the roof at :15 and
> :45 every hour: beat him for Candy, money and XP! Grab Candy around the lobby, and play in the
> first 10 minutes of every hour for **2x Candy**. Ends Nov 3!
