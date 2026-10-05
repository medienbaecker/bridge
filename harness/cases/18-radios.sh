#!/bin/bash
# Radio option cards, swatch groups, and the rule that typing never changes a question.
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/radios.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Radios</title></head><body>
<fieldset class="options"><legend>Where?</legend>
  <div><input type="radio" name="w" id="w-a" value="pool" data-record="where"><label for="w-a">Pool</label><span>desc</span></div>
  <div><input type="radio" name="w" id="w-b" value="page" data-record="where"><label for="w-b">Page</label><span>desc</span></div>
</fieldset>
<div class="swatches" data-record="tint" data-drive="--tint" data-target=".card">
  <button type="button" data-color="#2f6feb"></button><button type="button" data-color="#b42318"></button>
  <input type="text" value="#2f6feb" aria-label="Hex">
</div>
<div class="card" style="border:1px solid var(--tint,gray)">Card</div>
<div data-record="label"><span>Label</span> <input type="text" value="Archive"></div>
<script>document.body.dataset.answers = JSON.stringify(window.__bridgeAnswers || null)</script>
</body></html>
HTML
repo
(cd "$CASE_DIR/pages" && bridge radios.html)
wait_ready
js() { bridge --js "$page" "$1"; }
before=$(bridge --read "$page")
check_json "radio cards are styled cards" "$(js "return getComputedStyle(document.querySelector('.options > div')).borderRadius")" '.' "8px"
js "document.querySelector('#w-b').click(); return 1" >/dev/null; settle 0.3
check_json "a radio records its value" "$(bridge --read "$page")" '.answers.where' "page"
js "document.querySelector('[data-color=\"#b42318\"]').click(); return 1" >/dev/null; settle 0.3
read=$(bridge --read "$page")
check_json "a swatch records the hex on the group" "$read" '.answers.tint' "#b42318"
check_json "and drives" "$(js "return getComputedStyle(document.querySelector('.card')).getPropertyValue('--tint')")" '.' "#b42318"
check_json "the swatch is marked pressed" "$(js "return document.querySelector('[data-color=\"#b42318\"]').getAttribute('aria-pressed')")" '.' "true"
js "const h = document.querySelector('.swatches input'); h.value = '#123456'; h.dispatchEvent(new Event('change', {bubbles: true})); return 1" >/dev/null; settle 0.3
check_json "a typed hex records too" "$(bridge --read "$page")" '.answers.tint' "#123456"
js "const t = document.querySelector('[data-record=label] input'); t.value = 'Archiv, neu'; t.dispatchEvent(new Event('change', {bubbles: true})); return 1" >/dev/null; settle 0.3
check_json "a grouped text input records" "$(bridge --read "$page")" '.answers.label' "Archiv, neu"
sed -i '' 's/Where?/Where, then?/' "$page"; settle 0.5
read=$(bridge --read "$page")
check_json "typing in a group never changes the question" "$read" '.version' "1"
check_json "the typed text stands after the patch" "$read" '.answers.label' "Archiv, neu"
check_json "and so does the hex" "$read" '.answers.tint' "#123456"
check_json "the field still shows it" "$(js "return document.querySelector('[data-record=label] input').value")" '.' "Archiv, neu"
check_json "page scripts can read the answers" "$(js "return document.body.dataset.answers")" '.' "null"
bridge --quit; sleep 0.4
(cd "$CASE_DIR/pages" && bridge radios.html); wait_ready; settle 0.3
check_json "after a restart the hex field is restored" "$(js "return document.querySelector('.swatches input').value")" '.' "#123456"
check_json "the chosen radio is checked again" "$(js "return [document.querySelector('#w-b').checked, document.querySelector('#w-a').checked].join(',')")" '.' "true,false"
check_json "and the other radio keeps its own value" "$(js "return document.querySelector('#w-a').value")" '.' "pool"
check_json "and page scripts see the answers" "$(js "return JSON.parse(document.body.dataset.answers).where")" '.' "page"
check_json "still version 1" "$(bridge --read "$page")" '.version' "1"
snap radios "Radio cards and a swatch group"
finish
