#!/bin/bash
# The list column has one reading edge: the header over it and every row's
# title start at the same x, the unread dot hangs to the left of that edge in
# a gutter its own size, and a row does not move when it goes unread or read.
# Both edges measured from the ink of a real frame, not from constraints.
source "$(dirname "$0")/../lib.sh"
fixture editor-map.html >/dev/null; fixture editor-columns.html >/dev/null
repo
(cd "$CASE_DIR/pages" && bridge editor-map.html editor-columns.html 2>/dev/null); wait_ready; settle 0.4
# Selecting is looking: the selected row is read, the other still unread.
bridge --do select "$CASE_DIR/pages/editor-map.html" >/dev/null; settle 0.5
r=$(shot edges) || true
state=$(bridge --state); scale=$(printf '%s' "$state" | jq -r .backingScale); tb=$(printf '%s' "$state" | jq -r .titlebarHeight)
col=$(printf '%s' "$state" | jq -r '.sidebarGeometry.columnX'); colw=$(printf '%s' "$state" | jq -r '.columnWidths[1]')
# First ink right of the column edge along a scanline: dark and not the accent dot (blue), or any ink at all.
ink() { python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/edges.png" "$1" 1 | awk -v from="$(awk -v c=$col -v s=$scale 'BEGIN {print c * s + 2}')" -v to="$(awk -v c=$col -v w=$colw -v s=$scale 'BEGIN {print (c + w) * s}')" -v mode="$2" '$1 > from && $1 < to && $3 + $4 + $5 < 620 && (mode == "any" || $5 < $3 + 60) {print $1; exit}'; }
py() { awk "BEGIN {print $1}"; }
hy=$(py "int(($tb / 2) * $scale)")
sel=$(printf '%s' "$state" | jq -r '.sidebarGeometry.rowInWindow | .top + .height * 0.3'); sy=$(py "int($sel * $scale)")
oth=$(printf '%s' "$state" | jq -r '.sidebarGeometry.rowInWindow | if .top > 80 then .top - .height * 0.7 else .top + .height * 1.3 end'); oy=$(py "int($oth * $scale)")
# The titles sit on the upper line of a row that may carry a subtitle; the dot and
# the time stay on the row's middle, so they are read from their own scanline.
selc=$(printf '%s' "$state" | jq -r '.sidebarGeometry.rowInWindow | .top + .height * 0.5'); syc=$(py "int($selc * $scale)")
othc=$(printf '%s' "$state" | jq -r '.sidebarGeometry.rowInWindow | if .top > 80 then .top - .height * 0.5 else .top + .height * 1.5 end'); oyc=$(py "int($othc * $scale)")
header=$(ink $hy title); title=$(ink $sy title); other=$(ink $oy title)
check "the header and the selected row's title start on one edge (header $(py "$header / $scale - $col") pt, title $(py "$title / $scale - $col") pt in)" "$(py "(($header - $title) ^ 2 <= 9)")" "1"
check "the unread row's title starts on the same edge, nothing reserved before it" "$(py "(($other - $title) ^ 2 <= 9)")" "1"
check "the reading edge is about 25 pt into the column" "$(py "((($title / $scale - $col) >= 23) && (($title / $scale - $col) <= 27))")" "1"
# Unread is the dot at the trailing edge, beside the time: blue ink where the state puts it, on the unread row only.
dx=$(printf '%s' "$state" | jq -r '.sidebarGeometry.dotX'); tx=$(printf '%s' "$state" | jq -r '.sidebarGeometry.timeX')
blue() { python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/edges.png" "$1" 1 | awk -v from="$(py "($dx - 1) * $scale")" -v to="$(py "($dx + 8) * $scale")" '$2 > from && $1 < to && $5 > 200 && $3 < 120 {n++} END {print n + 0}'; }
# The unread row is the proof that this column is the dot's: an absence measured
# without it is indistinguishable from not having looked. The expectation is a
# constant, never computed from the same call it judges.
check "the unread row shows the dot there, the selected (read) row does not" "$([ "$(blue $oyc)" -ge 1 ] && echo shown) $(blue $syc)" "shown 0"
check "the dot sits just before the time, its room kept whether or not it shows (dot to time $(py "$tx - $dx") pt)" "$(py "(($tx - $dx >= 10) && ($tx - $dx <= 15))")" "1"
# Reading a bridge must not move its title's end: the time's x is the same before and after.
bridge --do select "$CASE_DIR/pages/editor-columns.html" >/dev/null; settle 0.3
check_json "the time and the title's end stay put when the other bridge is read" "$(bridge --state)" "(.sidebarGeometry.timeX == $tx)" "true"
finish
