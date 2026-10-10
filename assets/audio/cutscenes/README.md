# Pull cutscene audio — 2026-10-05

The designer's files for the Legendary pull cutscene (Config.Cutscenes.Legendary) and, from
2026-10-10, the Mythic "Starfall" and Secret "The Dream" (docs/prompts/PULL_CUTSCENES_V2.md),
trimmed with ffmpeg and uploaded to group 675425213. Volumes are in Config.Audio.Ui. Times below
were measured on these files at 10 ms (1 ms for the cuts).

| File | Original | Trim | Use | Roblox ID |
| --- | --- | --- | --- | --- |
| LegendaryCinematic.wav | 1021252 "CINEMATIC_MISC_Logo_Reveal_Sequence_01" | 0–5.0 s, 0.3 s fade out | From the film's first frame: its bass drop at once, its impact at 4.0 s (the beam's hit, `ImpactAt`) | 111448999523683 |
| LegendaryRise.wav | 274570 "Chaos-Rise" | from 1.8 s (the quiet start skipped), 0.15 s fade in; 3.42 s, peak at ~3.1 s | From the hard cut to black; its peak is the white flash (`InterludeSeconds`) | 119943211186448 |
| LegendaryHit.wav | 219703 "Cinematic-Hit-016" | from its onset at 0.32 s to 4.8 s, 1.2 s fade out | On the white flash, over the card's own reveal sound | 98145599201576 |
| LegendaryAurora.wav | 214981 "Aurora" | its first 40 s, 1 s fade in, 3 s fade out, 16-bit | Looped very faintly under the Legendary card; plays on 1 s after it closes, then tapers away | 138935380522596 |
| MythicLogo.wav | 1021265 "CINEMATIC_MISC_Transition_Logo_Reveal_Sequence_01" | 0–8.3 s, 0.3 s fade out, 24-bit to 16-bit, 48 kHz | Mythic from the black: hit at 0.36 s (attack from 0.335 s, full body 0.41 s); highs sucked out 3.86–4.20 s; reveal hits 4.22, 4.47, 4.56, 4.59, 4.87, 4.95 s; last sub hit 5.13 s (peak 5.14 s); tail under -30 dBFS from 7.36 s | 70660822484246 |
| MythicRise.wav | 274661 "Robo-Rise" | whole file (4.04 s), 16-bit 44.1 kHz | Mythic forging: loudest 2.45–3.2 s; its high band cuts at 3.597 s, which is the white flash | 77718729000824 |
| SecretRise.wav | 274686 "Tonal-Rise" | whole file (5.39 s), 16-bit 44.1 kHz | Secret's pull: builds to its loudest at 5.30–5.34 s and stops dead at 5.377 s, the hard cut to black | 122183012463871 |

The other sounds in these two scenes are Roblox library sounds, not files here (ids and volumes
in `Config.Audio.Ui`): the Secret's "DREAMCORE (Fever Dream)" track (`SecretDream`, public), its
heartbeat (`Heartbeat`, one lub-dub a play), the fluorescent hum, flicker, clunk, VHS glitch and
CRT switch-on, and the Mythic's star whoosh, gather, boom and time-slow swell.
