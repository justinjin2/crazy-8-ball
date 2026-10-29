# Halloween 2026: release checklist

For Justin, tonight (Wed Oct 28 2026). The code reads the clock: from **19:00 EDT** a server
with this update is Live. Justin, 17:46: the publish no longer has to beat 19:00; it goes out
tonight once the robustness pass is done (target about 20:30). A server that starts after 19:00
boots straight into Live. Line numbers re-read 17:50.

## 1. Check by hand (test place or Studio Play, then on the live game after the publish)

On a phone, a PC and a controller where you can:

1. Join on a **new account** and an **old account**. The tutorial shows no Halloween popups
   until it is done or skipped.
2. Play one match. The result shows Candy: 3 a ball, +10 for finishing, +25 for a win.
3. The **HALLOWEEN** button (right side) opens the menu: the Candy track, quests, the Spider,
   the Candy packs.
4. The **Pumpkin King**: he visits the middle of the roof at :15 and :45 past every hour for 12
   minutes (the top pill counts down, then "PUMPKIN KING IS HERE!"; tap it for the arrow).
   Challenge him once; a first win in a visit pays +150 Candy, +$2,500 and +100 XP, and rolls
   the **5% Jack-o'-Lantern Cue drop** (the sign over him shows the chance; it is hidden once you
   own the cue, and a drop shows a "From the Pumpkin King" card).
5. Pick up a **lobby Candy**.
6. The boost text (Money Boost / Candy Boost) and its card.
7. **Walk around** while it is the other player's turn.
8. A **Candy pack** prompt opens (cancel it; don't buy).
9. Each new cue (My Cues and the Index, in hand, one pot; `/givecue <Id>` to check quickly):
   Pitchfork (500 Candy), Witch's Broom (2,000), Halloween Sword (7,000), the Spider (3 h of
   play) and the Jack-o'-Lantern (the Pumpkin King's 5% drop).
11. The **Shop** opens on Blocks: the Grand Opening block is gone (blocks already owned still
    open from the inventory).
10. Settings > **Lower effects** on and off with a Halloween cue.

## 2. Publishing (tonight, after the robustness pass; target about 20:30)

1. Use the **Team Create** Studio window ("[EMOTES] CRAZY 8 Ball"). Rojo must say connected,
   and the coordinator says which commit it is synced at. The folder must be clean (nothing
   uncommitted).
2. **File > Publish to Roblox.**
3. Creator Hub > the game > **Configure > Server management > Restart Servers**, choose
   **"Restart only servers with outdated versions"**, with no delay longer than 10 minutes.
   Old servers have to go: old code resets an equipped new cue to Classic (`SaveSchema.luau`
   refuses newer saves) and pays no Candy. Servers also restart by
   themselves after 5-6 h (`Config.ServerRestart`).
4. Rename the game by hand once it is out: add the pumpkin (your words: "[🎃] … nothing else").
5. Tell the coordinator it is out: the LIVE icon goes up then (`store_page.py icon-set LIVE --go`).

## 3. What you should see

- **Published after 19:00 (the plan now):** a new server is Live at once (no countdown pill):
  night falls on the rooftop; the event tables, trees, pumpkins and lights; the
  HALLOWEEN button; the King's timer pill (he visits at :15 and :45); Candy in matches and
  lobby pickups; the **2x CANDY** chip in the first 10 minutes of every hour (UTC minutes 0-9).
- **(Only if published before 19:00:** the boost text first, the "HALLOWEEN EVENT IN" pill
  from 18:30, then all of the above at 19:00.)
- **The store page:** the countdown icons ran 5H (14:00) and 2H (17:42; the Mac slept through
  4H and 3H); at Justin's word (17:46) the "STARTS IN" badge is gone: the plain Halloween icon
  is up (121071839544374) and the countdown job is stopped. The LIVE icon (91272722538693) goes
  up when the publish is out, the plain one again a day later (log:
  `~/Desktop/8ball-refs/halloween/shots/coordinator/store/log.txt`). Your Experience Event runs
  19:00 Oct 28 to 19:00 Nov 3 (times fixed by API at 11:54; nothing else changed).

## 4. Every switch (Config, `src/shared/Config.luau`)

Off = the old behaviour; one line, then publish with the outdated-only restart.

| Switch | Line (21:15) | Off does |
|---|---|---|
| `Config.Halloween.Enabled` | 3763 | no Candy, no event UI; saved Candy still converts after the end |
| `Config.Halloween.Rush.Enabled` | 3772 | no 2x Candy minutes |
| `Config.Halloween.Match.Enabled` | 3783 | no match Candy |
| `Config.Halloween.Boss.Visit` | 3796 | the King's visit reward (Candy 150, Money 2500, Xp 100): one line to change |
| `Config.Halloween.Boss.CountsForQuests` | 3800 | King matches stop counting for the Matches/Balls quests |
| `Config.Halloween.Quests.Enabled` | 3812 | no quest boards |
| `Config.Halloween.Spider.Enabled` | 3901 | no Spider active-time cue |
| `Config.Halloween.Packs.Enabled` | 3918 | Candy packs not sold |
| `Config.Halloween.Convert.Enabled` | 3920 | Candy does not turn into money after the end |
| `Config.HalloweenMap.Enabled` | 9257 | the master map switch: no night, tables, decor, props, throne, King, drops |
| `Config.HalloweenMap` Night / Tables / Decor / Props / Throne / Boss / Candy | 9267-9578 | each part alone (Throne and Boss go off together) |
| `Config.HalloweenMap.Boss.Mode` | 9440 | `"Throne"`: the King sits on his throne at the piano all event (the old way) instead of visiting |
| `Config.CueSkins.Bodies.Enabled` | 6590 | the body cues draw the normal stick |
| `Config.Multiplayer.Roam.Enabled` | 8317 | in-match players stay at their table, as before |
| `Config.Badges.Enabled` | 18081 | no badge is awarded |
| `Config.Economy.FriendBoostEnabled` | 2037 | no +10% per friend |
| `Config.UI.BoostPill.Enabled` | 10078 | the old VIP tag instead of the boost text |
| `Config.UI.CuePreview.Enabled` | 10146 | already off |

## 5. If something breaks

Tell the coordinator what you see. The coordinator flips the switch, commits and pushes;
you publish with the outdated-only restart. Cut order for a bad night (PLAN): the King
(`HalloweenMap.Boss.Enabled`, or `Boss.Mode = "Throne"` to keep him seated), then the lobby drops
(`HalloweenMap.Candy`), then roaming, then the badge queue, then the whole event
(`Halloween.Enabled`).

## 6. Nov 3, 19:00 EST

The event ends and converts Candy into money by itself; the Experience Event ends itself.
Rename the game back (`[EMOTES] CRAZY 8 Ball`, or what you choose then). The icon: set the
original back (asset 123614794049673): `python3 tools/halloween/store_page.py icon-set 123614794049673 --go`.

## 7. What to read after launch (custom events and funnels)

- Core: the `Halloween` funnel (1_Button, 2_Opened, 3_FirstCandy, 4_Cue150, 5_Cue500,
  6_Cue2000, 7_Cue7000; named by Candy step, so a cue swap keeps them) and `HwCandy`, `HwMatch`, `HwQuest`, `HwTrack`, `HwSpider`, `HwPack`,
  `HwConvert`, `HwMenu`.
- Cues A: `HalloweenCueEquipped` (counts every Equip press, not distinct players).
- Sys: `RoamHome` (how far players roam), `BadgeAwarded` (Retro back-pay on day one).
- GUI: `FriendBoost` (friends at leave), `BoostCard` (card opens).
- Creator Hub: server FPS P10/P50, memory, concurrent users, the error report. Baselines
  before the publish (analytics API, hourly, Oct 27 10:00 to Oct 28 20:00 UTC; query and result
  in `~/Desktop/8ball-refs/halloween/analytics/watch/base_*.json`): peak concurrent players
  690-2,270; server FPS P10 swings 27-59 through the day (P50 60); `MemoryUsageP50` 156-168 (one
  hour 194); DAU 24,887 and 23.1 min per DAU (Oct 26). Alarms: P10 under 20 for an hour, or
  memory P50 over about 200 two hours running.

## 8. Discord announcement (draft; you post it)

> 🎃 **The HALLOWEEN UPDATE is live!** 🎃
> The rooftop has gone haunted. Play matches to collect **Candy**, finish daily quests and
> unlock Halloween cues that never come back: the **Pitchfork**, the **Witch's Broom** and the
> **Halloween Sword** on the Candy track, and the **Spider** for 3 hours of play. The **Pumpkin
> King** visits the middle of the roof at :15 and :45 every hour: beat him for Candy, money and
> XP, and a **5% chance at the Jack-o'-Lantern Cue**! Grab Candy around the lobby, and play in
> the first 10 minutes of every hour for **2x Candy**. Ends Nov 3!
