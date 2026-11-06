#!/bin/bash
# Send is never a dead end. Three steps: answered, sent, an answer changed;
# the button's state and label at each.
source "$(dirname "$0")/../lib.sh"
# serial
page="$CASE_DIR/pages/send.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Send</title></head><body>
<fieldset class="options"><legend>Where?</legend>
  <div><input type="radio" name="w" id="w-a" value="pool" data-record="where"><label for="w-a">Pool</label><span>desc</span></div>
  <div><input type="radio" name="w" id="w-b" value="page" data-record="where"><label for="w-b">Page</label><span>desc</span></div>
</fieldset>
</body></html>
HTML
repo
(cd "$CASE_DIR/pages" && bridge send.html); wait_ready
js() { bridge --js "$page" "$1"; }
send_item() { bridge --state | jq -c '[.toolbar[] | select(.id=="send") | .enabled, .symbol] | @tsv' -r; }
# The Send item as drawn: a digest of the pixels under the rightmost 100 pt of the
# toolbar in a real shot, so the three states are compared on screen, not by a property.
send_pixels() {
  local g png; g=$(bridge --state); png="$CASE_DIR/shots/send-$1.png"
  bridge --shot "$png" >/dev/null
  printf '%s' "$g" | jq -r '[(.windowFrame.width - 100) * .backingScale, 0, (.windowFrame.width - 8) * .backingScale, 110 * .backingScale] | map(floor) | @sh' | xargs python3 "$ROOT/harness/measure.py" "$png" region | cut -d' ' -f1
}
# Where the toolbar's glyphs are: clusters of dark columns in the icon row across
# the right 300 pt. A label that changes width would move its neighbours.
glyph_columns() {  # $1 shot name (already taken)
  local g png; g=$(bridge --state); png="$CASE_DIR/shots/send-$1.png"
  printf '%s' "$g" | jq -r '[(.windowFrame.width - 300) * .backingScale, 6 * .backingScale, .windowFrame.width * .backingScale, 44 * .backingScale, 190] | map(floor) | @sh' | xargs python3 "$ROOT/harness/measure.py" "$png" columns
}

js "document.querySelector('#w-b').click(); return 1" >/dev/null; settle 0.3
# A large answer: a sixty-item list and a 15,000-character script. Chrome must not care.
js "bridge.set('items-in-order', Array.from({length: 60}, (_, i) => 'D' + i)); bridge.set('script', 'x'.repeat(15000)); return 1" >/dev/null; settle 0.5
frame_before=$(bridge --state | jq -c '.windowFrame')
check "1 answered, not yet sent: enabled, says Send" "$(send_item)" "$(printf 'true\tSend')"
p1=$(send_pixels 1-send); c1=$(glyph_columns 1-send)
bridge --do send >/dev/null; settle 0.3
check "2 after Send: a sixty-item list and a 15,000-character script did not touch the window's size" "$(bridge --state | jq -c '.windowFrame')" "$frame_before"
p2=$(send_pixels 2-sent); c2=$(glyph_columns 2-sent)
same_place() { python3 -c '
import sys
a = [list(map(int, r.split("-"))) for r in sys.argv[1].split()]; b = [list(map(int, r.split("-"))) for r in sys.argv[2].split()]
ok = len(a) >= 1 and len(b) >= 1
d = b[0][0] - a[0][0] if ok else 0
ok = ok and abs(d) <= 8 and all(abs((y[0]-x[0]) - d) <= 1 and abs((y[1]-x[1]) - d) <= 1 for x, y in zip(a[:1], b[:1]))
print("same" if ok else "moved")' "$1" "$2"; }
bridge --read "$page" >/dev/null

check "   on screen, Send and Sent are two different drawings" "$([ "$p1" != "$p2" ] && echo differs)" "differs"
check "   and Point kept its place ($c2)" "$(same_place "$c1" "$c2")" "same"

js "document.querySelector('#w-a').click(); return 1" >/dev/null; settle 0.3
check "3 changed an answer: open again, says Send" "$(send_item)" "$(printf 'true\tSend')"
finish
