#!/usr/bin/env bash
# Resize one Roblox Studio window (the one whose title contains NAME) so a lane can check its
# screens at phone / iPad / TV sizes without the device emulator (docs/halloween/PLAN.md §7).
#   tools/halloween/studio_size.sh lane-hw-gui.rbxl 1100 640     # outer window size, points
#   tools/halloween/studio_size.sh lane-hw-gui.rbxl show         # print the window's size
# Then read workspace.CurrentCamera.ViewportSize through MCP and adjust until it matches the
# target (844x390 phone, 1024x768 iPad, 1920x1080 PC/TV). Needs Terminal in System Settings ->
# Privacy & Security -> Accessibility.
set -euo pipefail
NAME="${1:?place file name, e.g. lane-hw-gui.rbxl}"
shift
osascript - "$NAME" "$@" <<'OSA'
on run argv
	set needle to item 1 of argv
	tell application "System Events"
		repeat with p in (every process whose name is "RobloxStudio")
			repeat with w in (every window of p)
				if (name of w) contains needle then
					if (count of argv) is 2 then return (name of w) & " size " & ((item 1 of (get size of w)) as text) & "x" & ((item 2 of (get size of w)) as text)
					set position of w to {0, 25}
					set size of w to {(item 2 of argv) as integer, (item 3 of argv) as integer}
					return "resized " & (name of w)
				end if
			end repeat
		end repeat
	end tell
	return "no Studio window title contains " & needle
end run
OSA
