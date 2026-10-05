#!/bin/bash
# Waiting holds on entry: membership is decided when the user enters the list and
# held while they are in it. A bridge that arrives joins; one the user answers, or an
# agent crosses, stays where it is and goes quiet (dimmed, from pixels); the
# count on the Waiting row is the live number; leaving and coming back
# re-evaluates. A property of the view: nothing of it reaches the files.
source "$(dirname "$0")/../lib.sh"
for i in 1 2 3 4; do fixture decision.html d$i.html >/dev/null; done
repo
(cd "$CASE_DIR/pages" && bridge d1.html d2.html d3.html 2>/dev/null); wait_ready; settle 0.5
bridge --do project waiting >/dev/null; settle 0.3
names() { bridge --state | jq -r "$1 | map(split(\"/\") | last) | join(\",\")"; }
check "three waiting on entry" "$(names .bridgesColumn)" "d3.html,d2.html,d1.html"
bridge --do select "$CASE_DIR/pages/d2.html" >/dev/null; settle 0.3
bridge --js "$CASE_DIR/pages/d2.html" "document.querySelector('[data-value=grid]').click(); document.querySelector('[data-send]').click()" >/dev/null; settle 0.8
state=$(bridge --state)
check_json "the user answers the second: it stays where it is" "$state" '[.bridgesColumn[] | split("/") | last] | join(",")' "d3.html,d2.html,d1.html"
check_json "and goes quiet; the selection does not move" "$state" '([.quietRows[] | split("/") | last] | join(",")) + " " + (.selected // "" | split("/") | last)' "d2.html d2.html"
check_json "the Waiting row's count is the live number" "$state" '.projects.rows[0].count' "2"
bridge --cross "$CASE_DIR/pages/d3.html" >/dev/null; settle 0.5
check "an agent crosses the third: it stays too, quiet" "$(names .bridgesColumn) / $(names .quietRows)" "d3.html,d2.html,d1.html / d3.html,d2.html"
(cd "$CASE_DIR/pages" && bridge d4.html 2>/dev/null); wait_ready; settle 0.5
check "a bridge that arrives joins at the top" "$(names .bridgesColumn)" "d4.html,d3.html,d2.html,d1.html"

# The quiet row reads quieter than the live one, from the ink of a real frame.
bridge --do select "$CASE_DIR/pages/d4.html" >/dev/null; settle 0.3
# The darkest ink across a row's title band: a live title is near black, a quiet one is the secondary grey.
tone() { python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/held.png" "$(awk "BEGIN {print int(($top + $h * $1) * $scale)}")" 1 | awk -v from="$(awk "BEGIN {print ($col + 22) * $scale}")" -v to="$(awk "BEGIN {print ($col + $colw - 60) * $scale}")" 'BEGIN {m = -1} $1 > from && $1 < to && $5 < $3 + 60 && (m < 0 || $3 + $4 + $5 < m) {m = $3 + $4 + $5} END {if (m >= 0) print m}'; }
# A frame taken before the list drew has no dark ink on the live row; take another,
# up to five, and let ink() fail the case if the fifth still finds none.
for i in 1 2 3 4 5; do
  settle 0.4; r=$(shot held) || true
  state=$(bridge --state); scale=$(printf '%s' "$state" | jq -r .backingScale); col=$(printf '%s' "$state" | jq -r '.sidebarGeometry.columnX'); colw=$(printf '%s' "$state" | jq -r '.columnWidths[1]')
  top=$(printf '%s' "$state" | jq -r '.sidebarGeometry.rowInWindow.top'); h=$(printf '%s' "$state" | jq -r '.sidebarGeometry.rowInWindow.height')
  live=$(tone 3.3); quiet=$(tone 1.3)
  [ -n "$live" ] && [ "$live" -lt 250 ] && break
done
check_json "the frame holds the window and nothing else, so the state's geometry is this picture's" "$r" '.windows | length == 1' "true"
live=$(ink "the live row's title" tone 3.3); quiet=$(ink "the quiet row's title" tone 1.3)
check "the held row's title is dimmed against a live one (live $live, quiet $quiet)" "$(awk "BEGIN {print ($live < 250 && $quiet - $live >= 100) ? \"dimmer\" : \"same\"}")" "dimmer"
# The crossed one is struck: along the strike's scanline the ink covers most of
# the title's width, where a plain title's densest scanline covers about half.
cover() { for dy in -8 -6 -4 -2 0 2 4 6 8; do python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/held.png" "$(awk "BEGIN {print int(($top + $h * $1) * $scale) + $dy}")" 1 | awk -v from="$(awk "BEGIN {print ($col + 22) * $scale}")" -v span="$(awk "BEGIN {print 150 * $scale}")" '$2 > from && $1 < from + span && $3 + $4 + $5 < 640 {a = ($1 > from) ? $1 : from; b = ($2 < from + span) ? $2 : from + span; ink += b - a} END {if (ink > 0) printf "%.2f\n", ink / span}'; done | sort -n | tail -1; }
struck=$(ink "the crossed row's title" cover 1.3); plain=$(ink "the answered row's title" cover 2.3)
check "the crossed one is struck through and the answered one is not (ink across the title: $struck vs $plain)" "$(awk "BEGIN {print ($struck >= 0.9 && $plain <= 0.7 && $plain >= 0.25) ? \"struck\" : \"plain\"}")" "struck"
bridge --do project all >/dev/null; settle 0.3; bridge --do project waiting >/dev/null; settle 0.4
check "leaving and coming back re-evaluates" "$(names .bridgesColumn) / $(names .quietRows)" "d4.html,d1.html / "
check "nothing of it is saved" "$(grep -l held "$XDG_STATE_HOME/bridge-dev/ui.json" "$XDG_STATE_HOME/bridge-dev/list.json" 2>/dev/null | wc -l | tr -d ' ')" "0"
finish
