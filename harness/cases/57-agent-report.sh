#!/bin/bash
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/speed.html"
cat > "$page" <<'HTML'
<!doctype html><html><head><title>Speed</title></head><body>
<div class="dials">
  <label class="dial"><span>duration</span><input type="range" min="100" max="800" value="300" data-record="duration"><output></output></label>
  <label class="dial"><span>travel</span><input type="range" min="0" max="40" value="12" data-record="travel"><output></output></label>
</div>
</body></html>
HTML
repo
(cd "$CASE_DIR/pages" && bridge speed.html); wait_ready
js() { bridge --js "$page" "$1"; }
js "const r = document.querySelector('[data-record=travel]'); r.value = 30; r.dispatchEvent(new Event('change', {bubbles: true})); return 1" >/dev/null
settle 0.4
sed -i '' 's/min="0" max="40"/min="-100" max="40"/' "$page"; settle 0.8
check_json "a new version" "$(bridge --read "$page")" '.version' "2"
check_json "the untouched dial gets no hint, only the one the user moved" "$(js "return [...document.querySelectorAll('.bridge-previous')].map(h => h.previousElementSibling.querySelector('input').dataset.record).join()")" '.' "travel"
check_json "the hint sits after the dial row, not inside it" "$(js "const h = document.querySelectorAll('.dial')[1].nextElementSibling; return h.matches('.bridge-previous') && h.textContent")" '.' "30"
check_json "the travel readout is still on the row" "$(js "const d = document.querySelectorAll('.dial')[1], o = d.querySelector('output').getBoundingClientRect(), r = d.getBoundingClientRect(); return o.bottom <= r.bottom && o.top >= r.top && o.width > 0")" '.' "true"
check_json "the hint does not overlap the row" "$(js "const h = document.querySelectorAll('.dial')[1].nextElementSibling.getBoundingClientRect(), r = document.querySelectorAll('.dial')[1].getBoundingClientRect(); return h.top >= r.bottom")" '.' "true"
snap dial-hint "A last-time hint under a dial row"

page2="$CASE_DIR/pages/next.html"
cat > "$page2" <<'HTML'
<!doctype html><html><head><title>Next</title></head><body>
<p>Which next?</p>
<div class="actions"><button data-record="next" data-value="look:accordion" data-send>Look</button> <button data-record="next" data-value="skip" data-send>Skip</button></div>
</body></html>
HTML
(cd "$CASE_DIR/pages" && bridge next.html); wait_ready
js2() { bridge --js "$page2" "$1"; }
check_json "the button is drawn as a send button, its label readable" "$(js2 "const b = document.querySelector('button'), s = getComputedStyle(b); return s.color !== s.backgroundColor && s.backgroundColor !== getComputedStyle(document.body).backgroundColor")" '.' "true"
js2 "document.querySelector('button').click(); return 1" >/dev/null; settle 0.5
read=$(bridge --read "$page2")
check_json "pressing it records the value" "$read" '.answers.next' "look:accordion"
check_json "and sends" "$read" '.status' "sent"
snap send-option "An option that is also Send"

bridge --remove "$page" >/dev/null; settle 0.3
(cd "$CASE_DIR/pages" && bridge speed.html); wait_ready
check_json "remove keeps the user's record" "$(bridge --read "$page")" '.version' "2"
bridge --reset "$page" >/dev/null; settle 0.3
check_json "reset takes it off the list" "$(bridge --state)" "[.sidebar[].bridges[] | select(.title==\"Speed\")] | length" "0"
check "reset deletes the record" "$([ -e "$(sidecar "$page")" ] && echo kept || echo gone)" "gone"
(cd "$CASE_DIR/pages" && bridge speed.html); wait_ready
read=$(bridge --read "$page")
check_json "presented again it is version 1" "$read" '.version' "1"
check_json "with no history" "$read" '.history' "null"
check_json "and no hint" "$(js "return document.querySelectorAll('.bridge-previous').length")" '.' "0"
finish
