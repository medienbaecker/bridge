#!/bin/bash
# Chrome is glass: the page runs under the titlebar, which is the window's own
# material, so a row of buttons scrolled half under it blurs through instead of
# being cut at a hairline; and at scroll zero nothing is hidden beneath it.
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/grid.html"
python3 - "$page" <<'PY'
import sys
rows = "".join('<div class="row">' + "".join(f'<button>{r}.{c}</button>' for c in range(6)) + '</div>' for r in range(40))
open(sys.argv[1], 'w').write(f'<!doctype html><title>Grid</title><style>body{{margin:0;padding:24px;font:15px system-ui}} .row{{display:flex;gap:12px;margin:0 0 18px}} button{{flex:1;height:44px;border:2px solid #333;border-radius:10px;background:#f4d35e;font:600 15px system-ui}}</style>{rows}')
PY
repo
(cd "$CASE_DIR/pages" && bridge grid.html); wait_ready; settle 0.5
# Wait for the page to have painted rather than assume it: under load a shot
# can come before the first row is on screen.
px0=$(bridge --state | jq -r '((.pageX + 120) * .backingScale) | floor')
for i in $(seq 1 30); do bridge --shot "$CASE_DIR/shots/paint.png" >/dev/null; [ -n "$(python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/paint.png" column "$px0" 0 400 3 | awk '$3 + $4 + $5 < 300 {print; exit}')" ] && break; sleep 0.2; done
js() { bridge --js "$page" "$1"; }
state=$(bridge --state); tb=$(printf '%s' "$state" | jq -r '(.titlebarHeight * .backingScale) | floor')
# A column 120 pt into the page, whatever the columns to its left take.
px=$(printf '%s' "$state" | jq -r '((.pageX + 120) * .backingScale) | floor')
# A column through the buttons' left third: the first dark run is the first button's border.
first_ink() { python3 "$ROOT/harness/measure.py" "$1" column "$px" 0 400 3 | awk '$3 + $4 + $5 < 300 {print $1; exit}'; }
bridge --shot "$CASE_DIR/shots/zero.png" >/dev/null
check "at scroll zero the first row starts below the bar ($(first_ink "$CASE_DIR/shots/zero.png") px, bar $tb)" "$([ "$(first_ink "$CASE_DIR/shots/zero.png")" -ge "$tb" ] && echo below)" "below"
check_json "the layout viewport is inset by the bar, so the page lays out below it" "$(js "return innerHeight")" ". == $(printf '%s' "$state" | jq -r '.windowFrame.height - .titlebarHeight')" "true"
js "window.scrollTo(0, 232); return window.scrollY" >/dev/null
for i in $(seq 1 20); do [ "$(js "return window.scrollY")" = "232" ] && break; sleep 0.1; done; settle 0.4
bridge --shot "$CASE_DIR/shots/half.png" >/dev/null
# Half a row now lies under the bar: through the glass its yellow tints the band.
tint=$(python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/half.png" column "$px" 0 "$tb" 1 | awk '$5 < 245 {n++} END {print n+0}')
check "a row half under the bar shows through it: tinted runs in the band ($tint)" "$([ "$tint" -ge 3 ] && echo yes)" "yes"
snap glass "A row of buttons passing under the glass"
finish
