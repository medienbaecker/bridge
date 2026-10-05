#!/bin/bash
# The sidebar's selection pill is inset the same on both sides, with few rows
# and with enough to scroll, with overlay and legacy scrollers, measured from
# the drawn pixels of a real-window shot, never from computed geometry: a
# computed number can pass while the picture shows the pill flush right. The
# trailing time stays legible in every selection state; the list
# sits in the sidebar material.
source "$(dirname "$0")/../lib.sh"
for i in 1 2 3; do printf '<!doctype html><title>Page %s</title><p>Page %s</p>' $i $i > "$CASE_DIR/pages/p$i.html"; done
mkdir -p "$CASE_DIR/other"; printf '<!doctype html><title>Other one</title><p>o</p>' > "$CASE_DIR/other/o.html"
repo
for i in 1 2 3; do (cd "$CASE_DIR/pages" && bridge p$i.html); done; wait_ready; settle 0.3
# A second project, presented last: the column follows it, so it is the scope now.
(cd "$CASE_DIR/other" && bridge o.html); wait_ready; settle 0.4
# A fresh state launches into All (nothing was waiting); a bridge presented is visible there, so the column stays and the bridge heads it.
check_json "presented into a column that shows it, the column stays and the bridge heads it" "$(bridge --state)" '(.projects.scope == "all") and (.bridgesColumn[0] | endswith("/o.html"))' "true"
geo() { bridge --state | jq -c '.sidebarGeometry'; }
# Insets of the drawn pill, in points, from a shot: "left right". The pill is the
# first colour after the sidebar's own on the selected row's middle scanline;
# its extent is the span of that colour up to the clip's edge.
pill_insets() {  # $1 shot name
  local g y clip scale png
  g=$(bridge --state); png="$CASE_DIR/shots/$1.png"
  bridge --shot "$png" >/dev/null
  y=$(printf '%s' "$g" | jq -r '((.sidebarGeometry.rowInWindow.top + .sidebarGeometry.rowInWindow.height / 2) * .backingScale) | floor')
  clip=$(printf '%s' "$g" | jq -r '.sidebarGeometry.clip * .backingScale | floor'); scale=$(printf '%s' "$g" | jq -r '.backingScale'); x0=$(printf '%s' "$g" | jq -r '.sidebarGeometry.columnX * .backingScale | floor')
  python3 "$ROOT/harness/measure.py" "$png" "$y" 4 | python3 -c '
import sys
clip, scale, x0 = int(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3])
runs = [l.split() for l in sys.stdin]
runs = [(int(a) - x0, int(b) - x0, (c, d, e)) for a, b, c, d, e in runs if int(b) > x0]
runs[0] = (max(runs[0][0], 0), runs[0][1], runs[0][2])
side = runs[0][2]
pill = next((r[2] for r in runs if r[2] != side and r[0] < clip), None)
if pill is None: print("none"); sys.exit()
xs = [r for r in runs if r[2] == pill and r[1] <= clip]
print(round(xs[0][0] / scale, 1), round((clip - xs[-1][1]) / scale, 1))' "$clip" "$scale" "$x0"
}
symmetric() { printf '%s' "$1" | jq -R -r 'split(" ") | map(tonumber) | (.[0] - .[1] | fabs) <= 1 and .[0] >= 8'; }

i=$(pill_insets three-overlay)
check "three rows, overlay scrollers: the drawn pill is inset the same on both sides ($i)" "$(symmetric "$i")" "true"
# The time's room inside the pill against the dot's: from the selected row's
# middle scanline, ink to pill edge on the right, pill edge to ink on the left.
# Two scanlines, because they measure two things: the title sits on the upper line
# of a row that may carry a subtitle, the time stays on the row's middle. Read from
# one line, the "room" for the time was the gap to the pill's far edge, 168 pt of it.
side_room() {  # <fraction of the row> -> "<pill edge to first ink> <last ink to pill edge>"
  local g y x0 x1
  g=$(bridge --state)
  y=$(printf '%s' "$g" | jq -r "((.sidebarGeometry.rowInWindow.top + .sidebarGeometry.rowInWindow.height * $1) * .backingScale) | floor")
  x0=$(printf '%s' "$g" | jq -r '.sidebarGeometry.columnX * .backingScale | floor')
  x1=$(printf '%s' "$g" | jq -r '(.sidebarGeometry.columnX + .sidebarGeometry.clip) * .backingScale | floor')
  python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/three-overlay.png" "$y" 1 | python3 -c '
import sys
x0, x1 = int(sys.argv[1]), int(sys.argv[2])
runs = [l.split() for l in sys.stdin]; runs = [(int(a), int(b), (int(c), int(d), int(e))) for a, b, c, d, e in runs if int(a) >= x0 and int(b) <= x1]
side = runs[0][2]
pill = next(r[2] for r in runs if r[2] != side)
ink = [r for r in runs if r[2] != side and r[2] != pill and sum(r[2]) < 600]
pills = [r for r in runs if r[2] == pill]
if not ink: sys.exit(1)
print(round((ink[0][0] - pills[0][0]) / 2), round((pills[-1][1] - ink[-1][1]) / 2))' "$x0" "$x1"
}
room="$(ink "the title inside the pill" side_room 0.3 | cut -d" " -f1) $(ink "the time inside the pill" side_room 0.5 | cut -d" " -f2)"
# The title starts on the column's reading edge (case 42), 15 pt inside the pill;
# the time has its room on the right.
check "the title starts on the reading edge inside the pill and the time has room ($room pt)" "$(printf '%s' "$room" | awk '{print ($1 >= 13 && $1 <= 18 && $2 >= 6) ? "yes" : "no"}')" "yes"
# The blue dot means unread, as it does on this platform, and clears when the user selects the row.
sel=$(bridge --state | jq -r '.selected')
check_json "the page just presented is unread" "$(bridge --state)" '[.sidebar[].bridges[] | select(.location == "'"$sel"'") | .unread][0]' "true"
dot_in_row() { local g y0 y1 x; g=$(bridge --state); y0=$(printf '%s' "$g" | jq -r '(.sidebarGeometry.rowInWindow.top * .backingScale) | floor'); y1=$(printf '%s' "$g" | jq -r '((.sidebarGeometry.rowInWindow.top + .sidebarGeometry.rowInWindow.height) * .backingScale) | floor'); x=$(printf '%s' "$g" | jq -r '((.sidebarGeometry.dotX + 3.5) * .backingScale) | floor'); bridge --shot "$1" >/dev/null; python3 "$ROOT/harness/measure.py" "$1" column "$x" "$y0" "$y1" 1 | awk '$5 > 200 && $3 < 120 {n++} END {print n+0}'; }
before=$(dot_in_row "$CASE_DIR/shots/dot-before.png")
check "and its row shows the dot" "$([ "$before" -ge 1 ] && echo dot)" "dot"
bridge --do select "$sel" >/dev/null; settle 0.3
check_json "selecting it clears unread" "$(bridge --state)" '[.sidebar[].bridges[] | select(.location == "'"$sel"'") | .unread][0]' "false"
# The dot found a moment ago is what says this column is the dot's: on its own,
# "no blue here" passed with the column moved 900 pt away from the row.
check "and the dot is gone" "$([ "$before" -ge 1 ] && echo looked) $(dot_in_row "$CASE_DIR/shots/dot-after.png")" "looked 0"
bridge --do select "$(bridge --state | jq -r '[.sidebar[].bridges[] | select(.title == "Page 3") | .location][0]')" >/dev/null; settle 0.3
g=$(geo)
check_json "the projects column sits in the window's sidebar material (glass on macOS 26); the list does not" "$(bridge --state)" '.projects.vibrant and (.sidebarGeometry.vibrant | not)' "true"
# The harness app is an accessory whose window is never key: that is the inactive state.
check_json "the inactive pill draws its time in secondary, not tertiary" "$g" '(.emphasized | not) and .timeColor == "secondaryLabelColor"' "true"
check_json "the active pill's time maps to white" "$g" '.activeTimeColor' "alternateSelectedControlTextColor"
bridge --do scrollers legacy >/dev/null; settle 0.4
i=$(pill_insets three-legacy)
check "three rows, legacy scrollers: still symmetric ($i)" "$(symmetric "$i")" "true"
for i in $(seq 4 40); do printf '<!doctype html><title>Page %s</title><p>Page %s</p>' $i $i > "$CASE_DIR/pages/p$i.html"; (cd "$CASE_DIR/pages" && bridge p$i.html >/dev/null); done
wait_ready; settle 0.6
i=$(pill_insets forty-legacy)
check "forty rows, legacy scrollers: symmetric with the scroller showing ($i)" "$(symmetric "$i")" "true"
bridge --do scrollers overlay >/dev/null; settle 0.4
i=$(pill_insets forty-overlay)
check "forty rows, overlay scrollers: symmetric ($i)" "$(symmetric "$i")" "true"
finish
