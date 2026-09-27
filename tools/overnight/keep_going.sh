#!/usr/bin/env bash
# Stop hook for an unattended overnight run (loaded only through
# `claude --settings tools/overnight/settings.json`, never by normal sessions).
# While the brief's Progress list still has an unticked "- [ ]" line, it sends Claude back to
# work instead of letting the session end. It gives up after MAX blocks so a stuck run cannot
# loop forever. Exit 2 = block the stop; stderr is what Claude reads.
set -u
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
BRIEF="$ROOT/${OVERNIGHT_BRIEF:-docs/prompts/RANKS_MONEY_PROMPT.md}"
COUNT_FILE="$ROOT/.git/overnight-stop-count"
MAX=60

cat >/dev/null # the hook's JSON input is not needed

[ -f "$BRIEF" ] || exit 0
open_steps=$(grep -c '^- \[ \]' "$BRIEF" || true)
[ "${open_steps:-0}" -gt 0 ] || exit 0

n=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" >"$COUNT_FILE"
[ "$n" -le "$MAX" ] || exit 0

first=$(grep -m1 '^- \[ \]' "$BRIEF")
cat >&2 <<MSG
Not finished: $open_steps step(s) in the Progress list of ${BRIEF#"$ROOT"/} are still unticked.
The designer is asleep; do not stop and do not ask questions. Re-read that brief (the rules, the
Progress list and your Notes), run \`git log --oneline -15\`, and carry on with the first
unticked step:
$first
If a step is truly blocked, tick it as "- [x] BLOCKED: <why>", note it for the morning report,
and move on to the next one.
MSG
exit 2
