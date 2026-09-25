# Map research: what keeps players in a hub that never changes

Research for the new hub map (2026-09-24). This is the reference for map design.
Nothing here is Decided until it is copied into the GDD. Evidence strength is
marked: **strong** (repeated observation or experiments), **moderate**, **soft** (expert
opinion or anecdote).

## The one idea

**A fixed stage with a changing show.** Keep the building the same forever, because a place
people know by heart feels like home (familiarity makes people like it more). Make everything
*on* the building change: the other players, live screens, statues, the light, the weekly
decor. In a social hub the other players are the novelty.

## What Roblox actually rewards (official, create.roblox.com/docs/discovery)

- Recommendations count playtime only up to **60 minutes per player, per game, per day**.
  Endless AFK does not help. Roblox publishes nothing about AFK time.
- They measure **first-play bounce** (leaving within 60 s or 61 to 180 s), **play days** in
  day 1, days 2 to 7 and days 8 to 28, qualified sessions, and **intentional co-play days**
  (joining a friend, invites, private servers; matchmaking does not count).
- So the goal is not "stay for hours". It is: **(1) hook them in the first 3 minutes,
  (2) hold them about 5 minutes longer per visit, (3) give them a reason to come back on more
  days, (4) make it the place friends meet.**
- Benchmarks (GameAnalytics 2026, 500+ games): median session 9.8 min, top 10% 14.7 min;
  median D1 retention 10.3%, D7 1.6%. Longer sessions go with better D1 retention. One pool
  match plus a short linger is about the median; the hub has to earn one more match or
  about 5 more minutes.
- Market: 8-Ball Pool Classic (6 years old) peaked at 2,051 players, 8-Ball X at 980. The
  niche is small and nobody owns the "pool hangout" yet.

## Architecture and psychology

| Idea | Evidence | Strength | For our hub |
|---|---|---|---|
| **People attract people** (Whyte) | Years of filming New York plazas; people stop to chat in the busiest spot, not quiet corners | strong | Compact map; put the busiest things together |
| **Sittable space** (Whyte) | Seating mattered more than looks; about 6 to 10% of open space | strong | Lots of seats, ledges, stair seats, rails, all next to walking routes |
| **Triangulation** (Whyte) | A shared thing to look at makes strangers talk | strong | Featured-match screen, leaderboard wall, trick-shot table |
| **Edge effect** (Gehl) | People settle at edges first; seats against a wall with a view are most wanted | strong | "Thick" edges: booths, rails, alcoves. Open middle for walking |
| **Active walls** (Gehl) | Lively, varied frontages had about 7x more activity than blank ones | strong | No blank walls: every wall shows skins, trophies, screens or windows |
| **Viewing distance** (Gehl) | Faces readable at 20 to 25 m, actions at 70 to 100 m | strong | On a phone it is tighter: nothing social more than 60 to 80 studs from a table |
| **Prospect** (Appleton) | Meta-analysis of 34 studies: open views consistently liked; "refuge" mixed | moderate | Balconies and raised booths looking over the tables |
| **Mystery** (Kaplan) | Most consistent predictor in a 61-study meta-analysis | moderate | Curving balcony, half-seen rooftop, arches framing the next zone |
| **Legibility** (Kaplan) | Places you can make sense of are preferred | moderate | Read the whole layout from spawn; clear landmarks |
| **Medium complexity** (Berlyne) | Too plain is boring, too busy is tiring (inverted U) | moderate | Calm surfaces, detail where people gather |
| **Habituation** | Unchanging things fade from notice; variety and surprise slow it | moderate | Change the show, not the stage |
| **Ceiling height** (Meyers-Levy & Zhu) | High ceilings feel free and open, low ones focused | moderate | Tall central atrium, low cozy ceilings over lounges |
| **Nature and views** (Ulrich) | Real tree views helped hospital patients; on-screen nature is weaker | strong (real), soft (screen) | Plants, water and outside views for comfort and looks |
| **Intimacy gradient, alcoves, stair seats, pools of light** (Alexander) | Expert patterns, lightly tested | soft | Loud to quiet: spawn/shop, then tables, then lounges, then quiet nooks |
| **Third place** (Oldenburg) | Regulars, playful mood, conversation, easy access | soft | Visible regulars (rank frames, badges), seats made for chat |

## Games research

- **"Alone Together"** (Ducheneaut et al., WoW, 2006): players spend most time *near* others,
  not *with* them. Others are "an audience, a sense of social presence, and a spectacle".
  Players parked top-geared characters in town just to be admired. **Design for watchers and
  show-offs, not only players.**
- **Virtual third places** (Star Wars Galaxies cantinas, 2007): a sprawling, low-density
  town layout drove players *out* of the social spaces. **Keep it compact.**
- **Self-Determination Theory** (Ryan, Rigby, Przybylski 2006): freedom, feeling skilled and
  feeling connected each predict enjoyment and coming back. Free roam and toys, rank badges and
  a practice table, friends and spectating.
- **Shared fun is doubled fun** (Gajadhar et al. 2008): a co-located co-player made games
  more fun and players feel more skilled. **Matches should feel watched.**
- **Honey-pot effect** (Brignull & Rogers 2003): a crowd at a display pulls more people in.
  Put the featured-match screen where the crowd is visible from spawn.

## Hubs that stayed alive (same geometry, changing show)

| Game | What they did | Our version |
|---|---|---|
| Destiny Tower | Kickable ball, hidden rooms, seasonal redecoration, podiums showing live event standings | Weekly top-3 statues wearing their cues; a kickable toy |
| Club Penguin | A party nearly every month redecorated rooms; a new hidden pin every 1 to 2 weeks | Monthly decor overlay; a hidden collectible every two weeks |
| FFXIV Limsa | Busiest hub because market, bank and teleport sit together | Shop, trade and queue at one crossroads |
| Monster Hunter World | Canteen seats everyone; arm-wrestling barrels | Bar seating for 10 to 15; small toys |
| Sea of Thieves | Shared instruments sync into group songs | Voted jukebox, synced emotes |
| CoD WWII HQ | Opening rewards in public for others to watch | Optional public "cue reveal" pedestal (cosmetic only) |
| Animal Crossing | Real-time clock and seasons | Light follows real time; dated seasonal decor |
| Fortnite | Scheduled one-off events cause huge spikes | Weekly tournament night on the big screen |
| VRChat | Mirrors give social comfort; people linger at them together | A mirror or showcase wall to admire skins |
| Rivals (Roblox) | Step on a pad to queue; free range to try every weapon | Sit-to-queue; a practice table where any cue skin can be tried |
| Murder Mystery 2 (Roblox) | Spectate the live round from the lobby; trading with an anti-scam delay | Watch any table; safe trading spot |
| Pls Donate (Roblox) | Personal booths; people come to be seen | Personal display spots |
| Grow a Garden (Roblox) | Everyone's progress visible in one shared world; weekly admin weather events | Visible high-rank cues and titles; scheduled server events |

## Roblox limits that shape the map

- **Walk speed 16 studs/s.** Whole hub within a 10 s walk (about 160 studs across); spawn
  within about 50 studs of the nearest table.
- **Voice chat fades from 7 studs, silent at 80.** Chat bubbles show to 100. Spectator seats
  7 to 20 studs from a table so watchers hear the players.
- **About 80% mobile.** Must look good in the Soft lighting style (Realistic drops to Soft on
  low graphics settings). Shadows switch off below graphics level 4. All 16 tables share one
  mesh; few lights with short range; small textures 256 px.
- **Build for change:** the model needs named decor anchor points and swappable prop sets so
  seasonal overlays, statues and screens can change without touching the building.

## Sources

Official and data: [Roblox discovery docs](https://create.roblox.com/docs/discovery),
[Roblox recommendation update (DevForum)](https://devforum.roblox.com/t/recommended-for-you-algorithm-improvements-that-better-value-long-term-retention/4684575),
[Roblox newsroom, discovery 2026](https://about.roblox.com/newsroom/2026/06/optimizing-discovery-great-games-reach-millions-players-roblox),
[GameAnalytics 2026 Roblox report](https://www.gameanalytics.com/reports/2026-roblox-report),
[Rolimons: 8-Ball Pool Classic](https://www.rolimons.com/game/5523851880),
[Rolimons: 8-Ball X](https://www.rolimons.com/game/105423512432229),
[Roblox performance guide](https://create.roblox.com/docs/performance-optimization/improve),
[AudioEmitter reference](https://create.roblox.com/docs/reference/engine/classes/AudioEmitter),
[Unified lighting (DevForum)](https://devforum.roblox.com/t/let-there-be-unified-light-unified-lighting-is-fully-live/3401512).

Architecture and psychology: [Whyte, Social Life of Small Urban Spaces](https://en.wikipedia.org/wiki/The_Social_Life_of_Small_Urban_Spaces),
[Gehl's three types of activity](https://publicspaces.guide/gehls-three-types-of-activities/),
[Close encounters with buildings (Gehl et al.)](https://thecityateyelevel.com/stories/close-encounters-with-buildings/),
[Pattern Language contents](https://experiencingartsculture2015.wordpress.com/wp-content/uploads/2015/05/pattern-language-contents.pdf),
[Stamps, mystery and complexity meta-analysis](https://www.sciencedirect.com/science/article/abs/pii/S0272494403000239),
[Prospect-refuge meta-analysis](https://www.researchgate.net/publication/301814805_Evidence_for_prospect-refuge_theory_a_meta-analysis_of_the_findings_of_environmental_preference_research),
[Stevenson et al., nature and attention](https://pubmed.ncbi.nlm.nih.gov/30130463/),
[Hedonic adaptation (Sheldon et al.)](https://greatergood.berkeley.edu/images/uploads/The_Challenge_of_Staying_Happier.pdf),
[Novelty and dopamine (Bunzeck & Düzel)](https://www.sciencedirect.com/science/article/pii/S0896627306004752),
[Ellard on boring streets](https://aeon.co/essays/why-boring-streets-make-pedestrians-stressed-and-unhappy),
[Ulrich 1984, view through a window](https://pubmed.ncbi.nlm.nih.gov/6143402/),
[Meyers-Levy & Zhu, ceiling height](https://academic.oup.com/jcr/article-abstract/34/2/174/1793118),
[Vartanian et al., ceiling height and beauty](https://www.sciencedirect.com/science/article/abs/pii/S0272494414001030),
[Third place](https://en.wikipedia.org/wiki/Third_place).

Games: [Ducheneaut et al., Alone Together](https://www.nickyee.com/pubs/Ducheneaut,%20Yee,%20Nickell,%20Moore%20-%20Alone%20Together%20(2006).pdf),
[Virtual third places](https://www.semanticscholar.org/paper/Virtual-%E2%80%9CThird-Places%E2%80%9D:-A-Case-Study-of-Sociability-Ducheneaut-Moore/2e2b13595abf147350ac4ef23dd195521d1304dd),
[Steinkuehler & Williams](https://academic.oup.com/jcmc/article-abstract/11/4/885/4617703),
[Ryan, Rigby, Przybylski](https://selfdeterminationtheory.org/SDT/documents/2006_RyanRigbyPrzybylski_MandE.pdf),
[Shared fun is doubled fun](https://research.tue.nl/en/publications/shared-fun-is-doubled-fun-player-enjoyment-as-a-function-of-socia/),
[Starcraft from the stands](https://jeffhuang.com/papers/StarcraftSpectator_CHI11.pdf),
[Koster, making virtual spaces social](https://www.raphkoster.com/2009/01/28/ways-to-make-your-virtual-space-more-social/),
[GDC: Building Headquarters](https://www.gdcvault.com/play/1025984/Building-Headquarters-The-Social-Hub),
[Destiny 2 Tower secrets](https://gamerant.com/destiny-2-tower-secret-easter-eggs/),
[Guardian Games](https://help.bungie.net/hc/en-us/articles/14974910354068-Destiny-2-Guardian-Games-Guide),
[Club Penguin parties](https://clubpenguin.fandom.com/wiki/Parties),
[Club Penguin pins](https://clubpenguinlegacy.fandom.com/wiki/Pins),
[MHW Gathering Hub](https://monsterhunterworld.wiki.fextralife.com/The+Gathering+Hub),
[Sea of Thieves shanties](https://seaofthieves.fandom.com/wiki/Shanties),
[VRChat mirror dwellers](https://dl.acm.org/doi/10.1145/3544548.3581464),
[Rivals lobby](https://robloxrivals.fandom.com/wiki/Lobby),
[MM2 lobby](https://murder-mystery-2.fandom.com/wiki/Lobby),
[Pls Donate](https://rowatcher.com/news/pls-donate-roblox-s-weirdest-social-experiment),
[Grow a Garden](https://en.wikipedia.org/wiki/Grow_a_Garden).
