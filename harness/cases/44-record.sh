#!/bin/bash
# Every documented recording control, driven, and the record read back: the
# gallery photographs how controls look; this is whether they record. Every
# declared question gets an answer, not only the ones a script writes. Radio
# card picked by a click on its description, not the circle; checkbox as
# boolean; range and number as numbers; text delayed; textarea; select; a
# checkbox group as a list; the div shape.
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/controls.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Controls</title></head><body>
<fieldset class="options">
  <div class="option"><input type="radio" name="hours" id="h-mid" value="mid" data-record="hours" checked><label for="h-mid">Around 15 units</label><span id="mid-desc">Lorem ipsum dolor.</span></div>
  <div class="option" id="card-range"><input type="radio" name="hours" id="h-range" value="range" data-record="hours"><label for="h-range">10 to 20 units</label><span id="range-desc">Sit amet, consectetur adipiscing.</span></div>
</fieldset>
<label><input type="checkbox" data-record="money" id="money"> Include extras</label>
<label>Rate <input type="range" data-record="rate" id="rate" min="0" max="10" step="1" value="5"></label>
<label>Days <input type="number" data-record="days" id="days" value="3"></label>
<label>Name <input type="text" data-record="name" id="name"></label>
<textarea data-record="note" id="note"></textarea>
<select data-record="size" id="size"><option value="s">S</option><option value="m">M</option></select>
<div data-record="tags" id="tags"><label><input type="checkbox" value="a" checked> a</label><label><input type="checkbox" value="b"> b</label></div>
<div class="options"><div data-record="verdict" data-value="send" id="send-card">Send it</div><div data-record="verdict" data-value="rework">Rework</div></div>
</body></html>
HTML
repo
(cd "$CASE_DIR/pages" && bridge controls.html 2>/dev/null); wait_ready; settle 0.8
# What the page shows at ready is what the record says: the checked radio, the
# checked box in the group, the range's and the select's values, before the user touches
# anything. A click on the already-checked radio fires nothing, and need not.
first=$(bridge --read "$page")
check_json "a control showing a value at ready has it recorded as the page's default" "$first" '"\(.defaults.hours) \(.defaults.rate) \(.defaults.days) \(.defaults.size) \(.defaults.money) \(.defaults.tags | join(","))"' "mid 5 3 s false a"
check_json "an empty text or textarea records nothing yet" "$first" '[(.answers, .defaults) | has("name"), has("note"), has("verdict")] | join(",")' "false,false,false,false,false,false"
check_json "and none of them is among the user's answers" "$first" '.answers | length' "0"
js() { bridge --js "$page" "$1" >/dev/null; }
js "document.getElementById('h-mid').click()"; settle 0.4
check_json "clicking the already-checked radio changes nothing and loses nothing" "$(bridge --read "$page")" '"\(.answers.hours) \(.defaults.hours)"' "null mid"
fire() { js "const el = document.getElementById('$1'); $2; el.dispatchEvent(new Event('input', { bubbles: true })); el.dispatchEvent(new Event('change', { bubbles: true }))"; }
js "document.getElementById('range-desc').click()"
fire money "el.checked = true"
fire rate "el.value = '7'"
fire days "el.value = '4'"
fire name "el.value = 'Alex'"
fire note "el.value = 'a note'"
fire size "el.value = 'm'"
js "const b = document.querySelector('#tags input[value=b]'); b.checked = true; b.dispatchEvent(new Event('change', { bubbles: true }))"
js "document.getElementById('send-card').click()"
settle 1
record=$(bridge --read "$page")
check_json "the radio card records the option a click on its description picked" "$record" '.answers.hours' "range"
check_json "the checkbox records a boolean" "$record" '.answers.money' "true"
check_json "range and number record numbers" "$record" '"\(.answers.rate | type) \(.answers.rate) \(.answers.days | type) \(.answers.days)"' "number 7 number 4"
check_json "text, textarea and select record their strings" "$record" '"\(.answers.name)|\(.answers.note)|\(.answers.size)"' "Alex|a note|m"
check_json "a checkbox group records the checked values as a list" "$record" '.answers.tags | join(",")' "a,b"
check_json "the div shape records its value" "$record" '.answers.verdict' "send"
check_json "every declared question has an answer" "$record" '[.answers | keys[]] | sort | join(",")' "days,hours,money,name,note,rate,size,tags,verdict"
check_json "touching a control makes it the user's answer" "$record" '.defaults | keys | join(",")' ""
# Reopened, the record keeps the user's answers: a default never overwrites an answer.
bridge --quit >/dev/null 2>&1; sleep 0.5; (cd "$CASE_DIR/pages" && bridge controls.html 2>/dev/null); wait_ready; settle 0.8
check_json "reopening the page keeps what the user answered over the page's defaults" "$(bridge --read "$page")" '"\(.answers.hours) \(.answers.rate) \(.answers.money) \(.version)"' "range 7 true 1"
check_json "the picked card shows as checked" "$(bridge --js "$page" "return document.getElementById('h-range').checked")" '.' "true"

# The circle sits on the title's first line: the ink of both, from a real frame.
# A client rect is measured from the page's own origin, which starts under the
# titlebar, so pageY places it in the frame; without it the scanline reads white
# above the card, and -1 against -1 is not a measurement.
extent() { python3 -c '
import sys; sys.path.insert(0, "'"$ROOT"'/harness"); import measure
path, x0, x1, y0, y1 = sys.argv[1], *map(int, sys.argv[2:6])
first = last = None
for row, width, px in measure.rows(path, y1):
    if row < y0: continue
    if any(sum(p) < 500 for p in px[x0:x1]):
        if first is None: first = row
        last = row
if first is not None: print((first + last) / 2)' "$CASE_DIR/shots/radio.png" "$1" "$2" "$3" "$4"; }
for i in 1 2 3 4 5 6; do
  settle 0.6; r=$(shot radio) || true
  state=$(bridge --state); scale=$(printf '%s' "$state" | jq -r .backingScale); px=$(printf '%s' "$state" | jq -r .pageX); py=$(printf '%s' "$state" | jq -r .pageY)
  geo=$(bridge --js "$page" "const c = document.getElementById('card-range'); const r = c.querySelector('input[type=radio]').getBoundingClientRect(); const l = c.querySelector('label').getBoundingClientRect(); return { top: Math.round(r.top), left: Math.round(r.left), w: Math.round(r.width), h: Math.round(r.height), labelLeft: Math.round(l.left), labelTop: Math.round(l.top), labelH: Math.round(l.height) }")
  rx0=$(printf '%s' "$geo" | jq -r "(($px + .left) * $scale) | floor"); rx1=$(printf '%s' "$geo" | jq -r "(($px + .left + .w) * $scale) | ceil"); y0=$(printf '%s' "$geo" | jq -r "(($py + .top) * $scale) | floor"); y1=$(printf '%s' "$geo" | jq -r "(($py + .top + .h) * $scale) | ceil")
  tx0=$(printf '%s' "$geo" | jq -r "(($px + .labelLeft) * $scale) | floor"); tx1=$(printf '%s' "$geo" | jq -r "(($px + .labelLeft + 30) * $scale) | floor"); ty0=$(printf '%s' "$geo" | jq -r "(($py + .labelTop) * $scale) | floor"); ty1=$(printf '%s' "$geo" | jq -r "(($py + .labelTop + .labelH) * $scale) | floor")
  radio=$(extent $rx0 $rx1 $y0 $y1); title=$(extent $tx0 $tx1 $ty0 $ty1)
  [ -n "$radio" ] && [ -n "$title" ] && break
done
radio=$(ink "the circle" extent $rx0 $rx1 $y0 $y1); title=$(ink "the title's first line" extent $tx0 $tx1 $ty0 $ty1)
check "the circle's centre is on the title's cap-height centre, within a pixel at 2x (radio $radio, title $title)" "$(awk "BEGIN {d = $radio - $title; print (d <= 1.5 && d >= -1.5) ? \"level\" : \"off\"}")" "level"
finish
