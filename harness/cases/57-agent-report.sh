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
check_json "the untouched dial gets no hint, only the one the user moved" "$(js "return [...document.querySelectorAll('.bridge-previous')].map(h => h.previousElementSibling.querySelector('input').dataset.record).join()")" '.' "travel"
check_json "the hint sits after the dial row, not inside it or over it" "$(js "const d = document.querySelectorAll('.dial')[1], h = d.nextElementSibling; return h.matches('.bridge-previous') && h.getBoundingClientRect().top >= d.getBoundingClientRect().bottom && h.textContent")" '.' "30"
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
js2 "document.querySelector('button').click(); return 1" >/dev/null; settle 0.5
check_json "pressing it records the value and sends" "$(bridge --read "$page2")" '"\(.answers.next) \(.status)"' "look:accordion sent"
snap send-option "An option that is also Send"

bridge --remove "$page" >/dev/null; settle 0.3
(cd "$CASE_DIR/pages" && bridge speed.html); wait_ready
check_json "remove keeps the user's record" "$(bridge --read "$page")" '.version' "2"
bridge --reset "$page" >/dev/null; settle 0.3
check_json "reset takes it off the list" "$(bridge --state)" "[.sidebar[].bridges[] | select(.title==\"Speed\")] | length" "0"
check "reset deletes the record" "$([ -e "$(sidecar "$page")" ] && echo kept || echo gone)" "gone"
(cd "$CASE_DIR/pages" && bridge speed.html); wait_ready
check "presented again it is version 1, with no history and no hint" "$(bridge --read "$page" | jq -r '"\(.version) \(.history)"') $(js "return document.querySelectorAll('.bridge-previous').length")" "1 null 0"
check "one web view in the window" "$(bridge --state | jq '.webViews')" "1"
finish
