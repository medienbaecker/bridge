#!/bin/bash
# Every documented recording control, driven, and the record read back: the
# gallery photographs how controls look; this is whether they record. Radio
# card picked by a click on its description, not the circle; checkbox as
# boolean; range and number as numbers; text delayed; textarea; select; a
# checkbox group as a list.
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/controls.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Controls</title></head><body>
<fieldset class="options">
  <div><input type="radio" name="hours" id="h-mid" value="mid" data-record="hours" checked><label for="h-mid">Around 15 units</label><span id="mid-desc">Lorem ipsum dolor.</span></div>
  <div id="card-range"><input type="radio" name="hours" id="h-range" value="range" data-record="hours"><label for="h-range">10 to 20 units</label><span id="range-desc">Sit amet, consectetur adipiscing.</span></div>
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
settle 1
record=$(bridge --read "$page")
check_json "the radio card records the option a click on its description picked" "$record" '.answers.hours' "range"
check_json "the checkbox records a boolean" "$record" '.answers.money' "true"
check_json "range and number record numbers" "$record" '"\(.answers.rate | type) \(.answers.rate) \(.answers.days | type) \(.answers.days)"' "number 7 number 4"
check_json "text, textarea and select record their strings" "$record" '"\(.answers.name)|\(.answers.note)|\(.answers.size)"' "Alex|a note|m"
check_json "a checkbox group records the checked values as a list" "$record" '.answers.tags | join(",")' "a,b"
finish
