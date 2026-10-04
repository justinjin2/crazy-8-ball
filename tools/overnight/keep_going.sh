#!/usr/bin/env bash
# Stop hook for an unattended overnight run (loaded only through
# `claude --settings tools/overnight/settings.json`, never by normal sessions).
# While the brief's Progress list still has an unticked "- [ ]" line, it sends Claude back to
# work instead of letting the session end. It gives up after MAX blocks so a stuck run cannot
# loop forever. Exit 2 = block the stop; stderr is what Claude reads.
# OVERNIGHT_ATTENDED=1 is for a run the designer watches: Claude may stop to ask them something
# by creating .git/overnight-waiting first; the hook then lets that one stop through (and removes
# the file), so the question waits for the designer's answer instead of being sent back to work.
set -u
ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
BRIEF="$ROOT/${OVERNIGHT_BRIEF:-docs/prompts/RANKS_MONEY_PROMPT.md}"
# In a git worktree (the parallel lanes) `.git` is a file, so the marker files go in the real
# git directory (`git rev-parse --absolute-git-dir`); a plain checkout gets `.git` as before.
GITDIR="$(git -C "$ROOT" rev-parse --absolute-git-dir 2>/dev/null || echo "$ROOT/.git")"
COUNT_FILE="$GITDIR/overnight-stop-count"
MAX="${OVERNIGHT_MAX:-60}"
ATTENDED="${OVERNIGHT_ATTENDED:-0}"
WAITING_FILE="$GITDIR/overnight-waiting"

cat >/dev/null # the hook's JSON input is not needed

[ -f "$BRIEF" ] || exit 0
if [ "$ATTENDED" = "1" ] && [ -f "$WAITING_FILE" ]; then
	rm -f "$WAITING_FILE" # a question for the designer: let this stop through, once
	exit 0
fi
open_steps=$(grep -c '^- \[ \]' "$BRIEF" || true)
[ "${open_steps:-0}" -gt 0 ] || exit 0

n=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" >"$COUNT_FILE"
[ "$n" -le "$MAX" ] || exit 0

first=$(grep -m1 '^- \[ \]' "$BRIEF")
if [ "$ATTENDED" = "1" ]; then
	cat >&2 <<MSG
Not finished: $open_steps step(s) in the Progress list of ${BRIEF#"$ROOT"/} are still unticked.
The designer is awake and watching. Keep going on your own wherever you can do it at full
quality. If you truly need them (access you can't get yourself, a click only they can make, or a
call where guessing would lower the quality), run \`touch .git/overnight-waiting\`, then ask one
short, clear question and stop; this hook lets that stop through so they can answer. Otherwise
re-read the brief (the rules, the Progress list and your Notes), run \`git log --oneline -15\`,
and carry on with the first unticked step:
$first
MSG
	exit 2
fi
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
