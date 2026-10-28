# Badges: full list (draft, 2026-10-28)

The rules are data (a `Config.Badges` row each), and the same evaluator decides both live and
catch-up awards. The "Back-pay" column says whether existing players get the badge on their
next join from data the save already has.

| # | Key | Badge name | How to get it | Back-pay |
|---|---|---|---|---|
| 1 | Welcome | Welcome to Crazy 8 Ball! | Join the game | yes (on join) |
| 2 | FirstWin | First Win! | Win your first match (the tutorial counts) | yes (Wins ≥ 1) |
| 3 | Wins5 | Rookie | Win 5 matches | yes |
| 4 | Wins10 | Contender | Win 10 matches | yes |
| 5 | Wins25 | Hustler | Win 25 matches | yes |
| 6 | Wins50 | Pool Shark | Win 50 matches | yes |
| 7 | Wins100 | Pro | Win 100 matches | yes |
| 8 | Wins250 | Cue Master | Win 250 matches | yes |
| 9 | Wins500 | Legend | Win 500 matches | yes |
| 10 | Wins1000 | 8 Ball God | Win 1,000 matches | yes |
| 11 | RankBronze | Bronze | Reach Bronze | yes* |
| 12 | RankSilver | Silver | Reach Silver | yes* |
| 13 | RankGold | Gold | Reach Gold | yes* |
| 14 | RankPlatinum | Platinum | Reach Platinum | yes* |
| 15 | RankDiamond | Diamond | Reach Diamond | yes* |
| 16 | RankExpert | Expert | Reach Expert | yes* |
| 17 | RankVeteran | Veteran | Reach Veteran | yes* |
| 18 | RankMaster | Master | Reach Master | yes* |
| 19 | RankGrandmaster | Grandmaster | Reach Grandmaster | yes* |
| 20 | RankReyes | Reyes | Reach Reyes, the top rank | yes* |
| 21 | Streak3 | Hot Streak | Win 3 in a row | yes (BestWinStreak) |
| 22 | Streak5 | On Fire | Win 5 in a row | yes |
| 23 | Streak10 | Unstoppable | Win 10 in a row | yes |
| 24 | CueRare | Shiny! | Own a Rare cue | yes |
| 25 | CueEpic | Epic Find | Own an Epic cue | yes |
| 26 | CueLegendary | Legendary Pull | Own a Legendary cue | yes |
| 27 | CueMythic | Mythic Moment | Own a Mythic cue | yes |
| 28 | CueSecret | Secret Keeper | Own a Secret cue | yes |
| 29 | CueUnique | One of a Kind | Own a Unique cue | yes |
| 30 | Cues5 | Collector | Own 5 cues | yes |
| 31 | Cues10 | Curator | Own 10 cues | yes |
| 32 | Cues25 | Cue Rack | Own 25 cues | yes |
| 33 | Cues50 | Museum | Own 50 cues | yes |
| 34 | Balls100 | Sharpshooter | Pocket 100 balls | yes |
| 35 | Balls1000 | Pocket Pro | Pocket 1,000 balls | yes |
| 36 | Balls10000 | Pocket Machine | Pocket 10,000 balls | yes |
| 37 | Matches10 | Regular | Play 10 matches | yes |
| 38 | Matches100 | Dedicated | Play 100 matches | yes |
| 39 | Matches1000 | Lives Here | Play 1,000 matches | yes |
| 40 | Nice10 | Nice Shot! | Make 10 nice shots | yes |
| 41 | Nice100 | Trick Shot Artist | Make 100 nice shots | yes |
| 42 | Money1M | Millionaire | Earn $1,000,000 total | yes (MoneyEarned) |
| 43 | Money10M | Tycoon | Earn $10,000,000 total | yes |
| 44 | Squad | Squad Goals | Play a 2v2 or 3v3 match | from now on** |
| 45 | Ability1 | Power Up | Use an ability in a match | from now on** |
| 46 | Ability100 | Ability Master | Use abilities in 100 matches | from now on (new counter) |
| 47 | Crew | Part of the Crew | Be in the Crazy 8 Ball group while playing | yes (checked on join) |
| 48 | MetOwner | Met the Owner | Be in a server with Painicane | from now on |
| 49 | BeatOwner | Beat the Owner! | Win a match against Painicane | from now on |
| 50 | Halloween2026 | Halloween 2026 | Play during the 2026 Halloween event | event only |
| 51 | PumpkinSlayer | Pumpkin Slayer | Beat the Pumpkin King | event only |
| 52 | BroomRider | Broom Rider | Earn the Witch's Broom | event only |

\* Back-pay for ranks needs the highest rank ever reached. If the save keeps only the current
rank, back-pay goes up to the current rank only.
\** Unless the save already counts it (the code check confirms this).

Room to grow: adding a badge = one Config row + its Roblox badge id. `tools/roblox_badges.py`
can create the badge (name, description, icon) through Open Cloud and write the id back into
Config, if the badge API allows it for group games (being checked).
