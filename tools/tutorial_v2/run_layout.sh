#!/usr/bin/env bash
# Runs eval_layout.luau on several processes.
#   tools/tutorial_v2/run_layout.sh <shortlist.json> <breaks.jsonl> <out.jsonl> [n] [k] [powers] [workers]
set -euo pipefail
cd "$(dirname "$0")/../.."
short="$1"; breaks="$2"; out="$3"; n="${4:-40}"; k="${5:-8}"; powers="${6:-0.6,0.8,1}"; workers="${7:-18}"
tmp="$(dirname "$out")/.layout_$$"
mkdir -p "$tmp"
for i in $(seq 0 $((workers - 1))); do
	lune run tools/tutorial_v2/eval_layout.luau "$short" "$breaks" "$i" "$workers" "$tmp/part_$i.jsonl" "$n" "$k" "$powers" >"$tmp/part_$i.log" 2>&1 &
done
wait
cat "$tmp"/part_*.jsonl >"$out"
tail -q -n1 "$tmp"/part_*.log | sed -n 1,3p
rm -rf "$tmp"
