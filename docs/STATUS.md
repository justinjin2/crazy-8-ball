# Status

**2026-09-22: multiplayer implementation and integrated QA in progress.**

The current update is the designer-approved scope in [MULTIPLAYER_SPEC.md](../MULTIPLAYER_SPEC.md),
which supersedes conflicting older roadmap/GDD match rules. Shared 1v1, 2v2 and 3v3 queues,
rules, turn flow, HUD, setup controls, surrender voting and match lifecycle are implemented.
The baseplate now has three dedicated blue-cloth tables. The stored lounge remains disabled.
No bots, rewards, saved wins, difficulty or abilities are included.

See [MULTIPLAYER_PROGRESS.md](../MULTIPLAYER_PROGRESS.md) for current tests, recovery notes,
remaining work and tooling limits. 194 automated tests and lint pass. Three simultaneous
server-fixture replays matched all 45 object balls on one actual client within 0.000006 in.
Desktop/phone-emulator layouts and live keyboard confirmation flows have been inspected.
These do not constitute full six-client or physical-device acceptance.

The existing physics A-F, imported art, cue impact/spin, audio and replay systems are retained.
Earlier detailed physics measurements remain in git history and docs/DECISIONS.md.
Known art debt: imported mesh pockets differ slightly from regulation simulation geometry.

Required acceptance remains real full matches in each mode, concurrent 1v1+2v2 with six
clients, touch and controller play, and audio listening. Do not tick historical milestone
boxes whose full acceptance or out-of-scope features (solo, bots, rewards) remain incomplete.
