#!/bin/bash
# Send is never a dead end. Four steps: answered, sent, a pin written after
# sending, an answer changed; the button's state and label at each, and a
# second Send handing the note over.
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/send.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Send</title></head><body>
<fieldset class="options"><legend>Where?</legend>
  <div><input type="radio" name="w" id="w-a" value="pool" data-record="where"><label for="w-a">Pool</label><span>desc</span></div>
  <div><input type="radio" name="w" id="w-b" value="page" data-record="where"><label for="w-b">Page</label><span>desc</span></div>
</fieldset>
<p id="para">A paragraph the user will pin after sending.</p>
</body></html>
HTML
repo
(cd "$CASE_DIR/pages" && bridge send.html); wait_ready
js() { bridge --js "$page" "$1"; }
send_item() { bridge --state | jq -c '[.toolbar[] | select(.id=="send") | .enabled, .symbol] | @tsv' -r; }
side() { jq -c '{status, collected: (.collectedAt != null), notes: (.comments|length)}' "$(sidecar "$page")"; }
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

check_json "no labels in the toolbar: the state is the icon" "$(bridge --state)" '.toolbarLabelsShown' "false"
js "document.querySelector('#w-b').click(); return 1" >/dev/null; settle 0.3
# A large answer: a sixty-item list and a 15,000-character script. Chrome must not care.
js "bridge.set('items-in-order', Array.from({length: 60}, (_, i) => 'D' + i)); bridge.set('script', 'x'.repeat(15000)); return 1" >/dev/null; settle 0.5
frame_before=$(bridge --state | jq -c '.windowFrame')
check "1 answered, not yet sent: enabled, says Send" "$(send_item)" "$(printf 'true\tSend')"
p1=$(send_pixels 1-send); c1=$(glyph_columns 1-send)
bridge --do send >/dev/null; settle 0.3
check_json "2 after Send: still a verb, the icon is the clock (Sent)" "$(bridge --state)" '[.toolbar[] | select(.id=="send") | ((.enabled|tostring) + " " + .symbol)][0]' "true Sent"
check "   status sent" "$(side)" '{"status":"sent","collected":false,"notes":0}'
# Nothing in the strip after Send (the toolbar says sent), and the window is the size it was.
st=$(bridge --state)
check_json "   the strip says nothing after Send" "$st" '.banner' "null"
check "   a sixty-item list and a 15,000-character script did not touch the window's size" "$(printf '%s' "$st" | jq -c '.windowFrame')" "$frame_before"
p2=$(send_pixels 2-sent); c2=$(glyph_columns 2-sent)
check "   on screen, the Send item after sending differs from before" "$([ "$p1" != "$p2" ] && echo differs)" "differs"
# Glyph clusters compared with a tolerance of one pixel at 2x: half a point of
# sub-pixel rounding between two labels is not the furniture moving.
# Point and Notes must not move at all; the Send glyph changes shape with the
# state (plane, clock, filled plane), so it is held to its centre.
same_place() { python3 -c '
import sys
a = [list(map(int, r.split("-"))) for r in sys.argv[1].split()]; b = [list(map(int, r.split("-"))) for r in sys.argv[2].split()]
ok = len(a) == len(b) and len(a) >= 3
ok = ok and all(abs(x[0]-y[0]) <= 1 and abs(x[1]-y[1]) <= 1 for x, y in zip(a[:2], b[:2]))
ok = ok and abs(sum(a[2]) - sum(b[2])) <= 6
print("same" if ok else "moved")' "$1" "$2"; }
check "   and nothing in the toolbar moved ($c2)" "$(same_place "$c1" "$c2")" "same"
bridge --read "$page" >/dev/null
check "   the agent read it: collected" "$(side)" '{"status":"sent","collected":true,"notes":0}'

bridge --do point >/dev/null
js "const el = document.querySelector('#para'); const r = el.getBoundingClientRect(); el.dispatchEvent(new MouseEvent('click', {bubbles: true, clientX: r.left + 20, clientY: r.top + 8}))" >/dev/null; settle 0.3
js "const t = document.querySelector('.bridge-thread:popover-open textarea'); t.value = 'this paragraph is wrong'; t.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', metaKey: true, bubbles: true}))" >/dev/null; settle 0.4
check "3 pin written after sending: enabled, says Send again" "$(send_item)" "$(printf 'true\tSend again')"
check "   status still sent, note counted" "$(side)" '{"status":"sent","collected":true,"notes":1}'
p3=$(send_pixels 3-send-again); c3=$(glyph_columns 3-send-again)
check "   on screen, Send again differs from Sent and from Send" "$([ "$p3" != "$p2" ] && [ "$p3" != "$p1" ] && echo differs)" "differs"
check "   and still nothing moved ($c3)" "$(same_place "$c1" "$c3")" "same"
bridge --do send >/dev/null; settle 0.3
check "   Send again: collect marks cleared, so the hook delivers" "$(side)" '{"status":"sent","collected":false,"notes":1}'
read=$(bridge --read "$page")
check_json "   and --read hands the note over with the answer" "$read" '.status + " " + .answers.where + " " + (.comments | length | tostring)' "sent page 1"
check_json "   now the clock again" "$(bridge --state)" '[.toolbar[] | select(.id=="send") | .symbol][0]' "Sent"

js "document.querySelector('#w-a').click(); return 1" >/dev/null; settle 0.3
check "4 changed an answer: open again, says Send" "$(send_item)" "$(printf 'true\tSend')"
check "   status open" "$(side)" '{"status":"open","collected":false,"notes":1}'
finish
