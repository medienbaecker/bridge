#!/bin/bash
source "$(dirname "$0")/../lib.sh"

with_b
page=$(fixture decision.html)
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready
id=$(bridge --share "$page" | jq -r '.share')
there="$CASE_DIR/state-b/bridge-dev/shared/$id/page.html"
for i in $(seq 1 80); do [ -f "$there" ] && break; sleep 0.25; done
b --do select "$there" >/dev/null
for i in $(seq 1 60); do [ "$(b --state | jq -r '.ready')" = "true" ] && break; sleep 0.25; done
sleep 0.3

until_is() { for i in $(seq 1 80); do [ "$(eval "$1")" = "$2" ] && return; sleep 0.1; done; }
chips() { b --js "$there" "@bridge return [...document.querySelectorAll('.bridge-pick-value')].map((d) => (d.classList.contains('bridge-pick-draft') ? 'typing ' : '') + d.textContent).join(' | ')" | jq -r .; }

bridge --js "$page" "const t = document.querySelector('[data-record=note]'); t.focus(); t.value = 'half a thought'; t.dispatchEvent(new InputEvent('input', { bubbles: true })); return 1" >/dev/null
until_is chips "typing thomas: half a thought"
check "what he types shows on her Mac as he types" "$(chips)" "typing thomas: half a thought"
check "and it sits just under the field, in view" "$(b --js "$there" "@bridge const d = document.querySelector('.bridge-pick-draft').getBoundingClientRect(), t = document.querySelector('[data-record=note]').getBoundingClientRect(); return d.width > 20 && d.top >= t.bottom && d.top - t.bottom < 40 && d.bottom <= innerHeight")" "true"
b --shot "$CASE_DIR/shots/her-typing.png" >/dev/null

bridge --js "$page" "const r = document.querySelector('[data-record=radius]'); r.value = 17; r.dispatchEvent(new InputEvent('input', { bubbles: true })); return 1" >/dev/null
until_is "chips | grep -c 'typing thomas: 17'" 1
check "dragging a slider shows the live value" "$(chips | grep -o 'typing thomas: 17')" "typing thomas: 17"

bridge --js "$page" "const t = document.querySelector('[data-record=note]'); t.dispatchEvent(new Event('change', { bubbles: true })); t.blur(); return 1" >/dev/null
until_is "chips | grep -c 'typing thomas: half'" 0
check "leaving the field ends the draft and shows his answer" "$(chips | grep -o 'thomas: half a thought' | head -1) $(chips | grep -c 'typing thomas: half')" "thomas: half a thought 0"
finish
