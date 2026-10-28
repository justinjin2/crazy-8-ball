#!/usr/bin/env bash
# Restart any Halloween Rojo server (coordinator + six lanes) that has died, every 10 s.
# Rojo 7.7 can panic on an editor's temp file (seen 2026-10-28 08:44 on hw-map:
# "Canonicalize ... Config.luau.tmp.<pid>..." in change_processor.rs). A restarted server still
# needs its Studio window's Rojo plugin to click Connect again; every restart is logged to
# ~/Desktop/8ball-refs/halloween/shots/coordinator/rojo-watchdog.log so the coordinator can see it.
#
#   nohup tools/halloween/rojo_watchdog.sh >/dev/null 2>&1 &     (start outside any sandbox)
set -u
MAIN="$(cd "$(dirname "$0")/../.." && pwd)"
PARENT="$(dirname "$MAIN")"
LOG="$HOME/Desktop/8ball-refs/halloween/shots/coordinator/rojo-watchdog.log"
mkdir -p "$(dirname "$LOG")"
pairs="coordinator:34872 hw-core:34883 hw-cues-a:34884 hw-cues-b:34885 hw-map:34886 hw-sys:34887 hw-gui:34888"
echo "$(date '+%F %T') watchdog started (pid $$)" >>"$LOG"
while true; do
	for pair in $pairs; do
		lane="${pair%%:*}"
		port="${pair##*:}"
		if [ "$lane" = coordinator ]; then dir="$MAIN"; else dir="$PARENT/8ball-$lane"; fi
		[ -d "$dir" ] || continue
		if ! lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
			mkdir -p "$dir/.lanes"
			[ -f "$dir/.lanes/rojo.log" ] && cp "$dir/.lanes/rojo.log" "$dir/.lanes/rojo.crash.$(date +%H%M%S).log"
			(cd "$dir" && nohup rojo serve default.project.json --port "$port" >"$dir/.lanes/rojo.log" 2>&1 &)
			sleep 2
			if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then s=restarted; else s=FAILED; fi
			echo "$(date '+%F %T') $lane $port $s (Studio must click Connect)" >>"$LOG"
		fi
	done
	sleep 10
done
