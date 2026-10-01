#!/usr/bin/env bash
# Stop hook for the cue skins run (docs/prompts/CUE_SKINS_PROMPT.md), which the designer watches.
# Loaded only through `claude --settings tools/overnight/cue_skins.json`.
# - If the brief's Notes hold a line starting "WAITING FOR DESIGNER:", Claude is asking the
#   designer something (the pilot check, a missing concept, the spend check): let it stop.
# - Otherwise, while the Progress list still has an unticked "- [ ]" line, send it back to work.
# Gives up after MAX blocks so a stuck run can't loop forever. Exit 2 = block; stderr is read.
set -u
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
BRIEF="$ROOT/docs/prompts/CUE_SKINS_PROMPT.md"
GITDIR="$(git -C "$ROOT" rev-parse --git-dir 2>/dev/null || echo /tmp)"
COUNT_FILE="$GITDIR/skins-stop-count"
MAX="${SKINS_MAX:-300}"

cat >/dev/null # the hook's JSON input is not needed

[ -f "$BRIEF" ] || exit 0
grep -q '^WAITING FOR DESIGNER:' "$BRIEF" && exit 0
open_steps=$(grep -c '^- \[ \]' "$BRIEF" || true)
[ "${open_steps:-0}" -gt 0 ] || exit 0

n=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" >"$COUNT_FILE"
[ "$n" -le "$MAX" ] || exit 0

first=$(grep -m1 '^- \[ \]' "$BRIEF")
cat >&2 <<MSG
Not finished: $open_steps step(s) in the Progress list of docs/prompts/CUE_SKINS_PROMPT.md are
still unticked. Re-read the brief (rules, section 8, Progress, Notes), run
\`git log --oneline -10\`, and carry on with the first unticked step:
$first
If you really need the designer (only the cases the brief lists), add a line starting
"WAITING FOR DESIGNER: <question>" at the top of Notes, ask in chat, and stop. Remove that
line once they answer.
MSG
exit 2
