#!/bin/bash
# Pointing shows itself: the toolbar item reads on, a ghost pin rides with the
# cursor with its tip on the pointer, and both go once a pin is placed or Escape is pressed.
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/point.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Point</title><style>p{margin:200px 40px}</style></head><body>
<p id="para">Something to point at, some way down the page.</p>
</body></html>
HTML
repo
(cd "$CASE_DIR/pages" && bridge point.html); wait_ready
js() { bridge --js "$page" "$1"; }
point_on() { bridge --state | jq -r '[.toolbar[] | select(.id=="point") | .on][0]'; }
check "before: the Point item reads off" "$(point_on)" "false"
glyphs() { local g; g=$(bridge --state); bridge --shot "$CASE_DIR/shots/$1.png" >/dev/null; printf '%s' "$g" | jq -r '[(.windowFrame.width - 300) * .backingScale, 6 * .backingScale, .windowFrame.width * .backingScale, 44 * .backingScale, 190] | map(floor) | @sh' | xargs python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/$1.png" columns; }
c0=$(glyphs point-off)
bridge --do point >/dev/null; settle 0.3
check "pointing: the Point item reads on" "$(point_on)" "true"
check_json "no word: the state is the accent symbol (Pointing)" "$(bridge --state)" '[.toolbar[] | select(.id=="point") | .symbol][0] + " " + (.toolbarLabelsShown|tostring)' "Pointing false"
c1=$(glyphs point-on)
# Notes and Send must not move at all; the Point glyph renders a pixel or two
# differently once tinted, so it is held to its centre.
check "and nothing in the toolbar moved when pointing went on ($c1)" "$(python3 -c '
import sys
a = [list(map(int, r.split("-"))) for r in sys.argv[1].split()]; b = [list(map(int, r.split("-"))) for r in sys.argv[2].split()]
ok = len(a) == len(b) and len(a) >= 3 and abs(sum(a[0]) - sum(b[0])) <= 6
ok = ok and all(abs(x[0]-y[0]) <= 1 and abs(x[1]-y[1]) <= 1 for x, y in zip(a[1:], b[1:]))
print("same" if ok else "moved")' "$c0" "$c1")" "same"
check_json "a ghost pin is on the page" "$(js "return document.querySelector('.bridge-ghost') !== null")" '.' "true"
js "document.dispatchEvent(new PointerEvent('pointermove', {clientX: 120, clientY: 260, bubbles: true})); return 1" >/dev/null; settle 0.2
off=$(js "const r = document.querySelector('.bridge-ghost').getBoundingClientRect(); return [Math.round(((r.left + r.right) / 2 - 120) * 10) / 10, Math.round((r.bottom - 260) * 10) / 10].join(' ')" | tr -d '"')
check "its tip is on the pointer (dx dy within a pixel)" "$(printf '%s' "$off" | jq -R -r 'split(" ") | map(tonumber | fabs) | max <= 1.5')" "true"
snap ghost "The ghost pin at the cursor while pointing"
js "const el = document.querySelector('#para'); const r = el.getBoundingClientRect(); el.dispatchEvent(new MouseEvent('click', {bubbles: true, clientX: r.left + 20, clientY: r.top + 8}))" >/dev/null; settle 0.3
check_json "a click places the pin and the ghost is gone" "$(js "return [document.querySelector('.bridge-ghost') === null, document.querySelector('.bridge-thread:popover-open') !== null].join(',')")" '.' "true,true"
check "and the Point item reads off again" "$(point_on)" "false"
js "document.querySelector('.bridge-thread:popover-open textarea').value = 'here'; document.querySelector('.bridge-thread:popover-open textarea').dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', metaKey: true, bubbles: true})); return 1" >/dev/null; settle 0.3
bridge --do point >/dev/null; settle 0.2
check "pointing again: on" "$(point_on)" "true"
js "document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true})); return 1" >/dev/null; settle 0.3
check_json "Escape: ghost gone" "$(js "return document.querySelector('.bridge-ghost') === null")" '.' "true"
check "and off" "$(point_on)" "false"
finish
