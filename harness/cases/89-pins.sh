#!/bin/bash
source "$(dirname "$0")/../lib.sh"
# serial
agent="test-$CASE_NAME-agent"
page="$CASE_DIR/pages/section.html"
write() { printf '<!doctype html><title>Section IX without the form</title><style>body{margin:0;font:16px/1.5 system-ui} h2,p,button{margin:16px}</style>%s' "$1" > "$page"; }
write '<h2>Abschnitt IX</h2><p>Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><button id="send">Absenden</button>'
repo
(cd "$CASE_DIR/pages" && claude_session "$agent" idle)
(cd "$CASE_DIR/pages" && BRIDGE_SESSION="$agent" bridge section.html); wait_ready; settle 0.3
list="$XDG_STATE_HOME/bridge-dev/list.json"
drafts() { jq '[.bridges[] | select(.location | contains("/drafts/"))] | length' "$list"; }
js() { bridge --js "$page" "$1"; }
at() { freeze_at "$(js "const r = document.querySelector('$1').getBoundingClientRect(); return (r.left + 20) + ' ' + (r.top + r.height / 2)" | jq -r .)"; }
note() { bridge --do freeze-mark "$1" >/dev/null; settle 0.3; bridge --do freeze-note "$2" >/dev/null; settle 0.5; }
press() { js "@bridge const pin = document.querySelector('.bridge-pin[data-n=\"$1\"]'); const r = pin.getBoundingClientRect(); const at = { bubbles: true, clientX: r.left + r.width / 2, clientY: r.top + r.height / 2, button: 0 }; pin.dispatchEvent(new PointerEvent('pointerdown', at)); pin.dispatchEvent(new PointerEvent('pointerup', at)); pin.click()" >/dev/null; settle 0.3; }
on() { js "@bridge const pin = document.querySelector('.bridge-pin[data-n=\"$1\"]'); const el = document.querySelector('$2'); if (!pin || !el) return 'missing'; const p = pin.getBoundingClientRect(), r = el.getBoundingClientRect(); const x = (p.left + p.right) / 2, y = p.bottom; return x >= r.left && x <= r.right && y >= r.top - 1 && y <= r.bottom + 1" | jq -r .; }

bridge --do freeze >/dev/null; settle 1
note "$(at h2)" "Überschrift größer"
note "$(at '#send')" "Donaudampfschifffahrtsgesellschaftskapitänswitwenrentenantragsformular statt Absenden"
outside=$(bridge --state | jq -r '.freeze.screenFrame as $s | .windowFrame as $w | "\(($w.x - $s[0] + $w.width + $s[2]) / 2) \(($s[1] + $s[3]) - ($w.y + $w.height / 2))"')
note "$outside" "Lorem ipsum in Safari"
bridge --do freeze-send 0 >/dev/null
for i in $(seq 1 40); do [ "$(bridge --pins "$page" | jq length)" = 2 ] && break; settle 0.1; done
settle 0.5
check "the two pins on the page land on it, and nothing becomes a draft" "$(bridge --pins "$page" | jq -c 'map(.text[0:10])') $(drafts)" '["Überschrif","Donaudampf"] 0'
check_json "--pins names the element each one sits on, with its picture" "$(bridge --pins "$page")" 'map([.element, (.picture | test("\\.[12]\\.png$"))] | map(tostring) | join(" ")) | join(",")' "h2 true,#send true"
check "one message tells the agent about the page and carries the note from elsewhere" "$(inbox "$agent" | grep -c 'sent you notes') $(inbox "$agent" | grep -c 'On `'"$page"'` they pinned notes to elements') $(inbox "$agent" | grep -c '^3\. "Lorem ipsum in Safari" on .*\.3\.png$')" "1 1 1"
check "the page shows each pin on its element" "$(on 1 h2) $(on 2 '#send')" "true true"

press 2
check_json "clicking a pin shows its note beside it" "$(js "@bridge const n = document.querySelector('.bridge-note:popover-open'); return n ? n.textContent : 'closed'")" '.[0:9]' "Donaudamp"
check_json "the note stays on screen at 320 wide" "$(js "@bridge const r = document.querySelector('.bridge-note:popover-open').getBoundingClientRect(); return r.right <= innerWidth && r.width <= 320")" '.' "true"
press 2
press 2
press 2
check_json "and a second click closes it, again and again" "$(js "@bridge return document.querySelectorAll('.bridge-note:popover-open').length")" '.' "0"

write '<p>Neu davor: sed do eiusmod tempor incididunt ut labore.</p><h2>Abschnitt IX</h2><p>Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p>'
for i in $(seq 1 40); do [ "$(js "@bridge return document.querySelectorAll('.bridge-pin[data-lost]').length" | jq -r .)" = 1 ] && break; settle 0.1; done
check "after a rewrite the pin finds its heading where it moved" "$(on 1 h2)" "true"
check_json "and the button's pin, its element gone, waits in the corner, marked lost" "$(js "@bridge const pin = document.querySelector('.bridge-pin[data-n=\"2\"]'); const r = pin.getBoundingClientRect(); return [pin.hasAttribute('data-lost'), r.right > innerWidth - 60, r.top < 80]")" 'map(tostring) | join(",")' "true,true,true"
press 2
check_json "its note says so" "$(js "@bridge return document.querySelector('.bridge-note:popover-open .bridge-lost')?.textContent")" '.' "Pointing at nothing now"
js "@bridge document.querySelector('.bridge-note:popover-open').hidePopover()" >/dev/null

id=$(bridge --pins "$page" | jq -r '.[1].id')
bridge --done "$page" "$id" >/dev/null; settle 0.5
check "--done takes its pin off the page" "$(bridge --pins "$page" | jq length) $(js "@bridge return document.querySelectorAll('.bridge-pin').length" | jq -r .)" "1 1"
bridge --reload "$page" >/dev/null; wait_ready; settle 0.5
check "a reload shows the open pin again on its element" "$(on 1 h2)" "true"

bridge --do freeze >/dev/null; settle 1
note "$(at h2)" "Sed ut perspiciatis"
before=$(drafts)
bridge --js "$XDG_STATE_HOME/bridge-dev/freeze/screen.html" "@bridge [...document.querySelectorAll('.bridge-agents button')].pop().click()" >/dev/null; settle 1
check "Draft with only page pins pins them at once and makes no draft" "$(bridge --pins "$page" | jq length) $(drafts)" "2 $before"
check_json "and shows the page" "$(bridge --state)" '.selected' "$page"

kept=$(bridge --pins "$page" | jq -r '.[0].picture')
bridge --do remove >/dev/null; settle 0.5
check "removing the page takes its pins' pictures along" "$(ls "$kept" 2>/dev/null | wc -l | tr -d ' ')" "0"
printf '<!doctype html><title>Lorem</title><style>body{margin:0;font:16px/1.5 system-ui} h2{margin:16px}</style><h2>Lorem ipsum</h2>' > "$CASE_DIR/pages/drag.html"
(cd "$CASE_DIR/pages" && BRIDGE_SESSION="$agent" bridge drag.html); wait_ready; settle 0.3
screen="$XDG_STATE_HOME/bridge-dev/freeze/screen.html"
glass() { bridge --js "$screen" "@bridge $1"; }
drag() { glass "const pin = [...document.querySelectorAll('.bridge-pin')].pop(); const r = pin.getBoundingClientRect(); const x = r.left + r.width / 2, y = r.top + r.height / 2; const at = (dx) => ({ bubbles: true, clientX: x + dx, clientY: y, button: 0, buttons: 1, pointerId: 1 }); pin.dispatchEvent(new PointerEvent('pointerdown', at(0))); for (const dx of [10, 30, 60]) pin.dispatchEvent(new PointerEvent('pointermove', at(dx))); pin.dispatchEvent(new PointerEvent('pointerup', at(60))); pin.click()" >/dev/null; settle 0.8; }
pin_x() { glass "return Math.round([...document.querySelectorAll('.bridge-pin')].pop().getBoundingClientRect().left)" | jq -r .; }
bridge --do select "$CASE_DIR/pages/drag.html" >/dev/null; wait_ready; settle 0.3
bridge --do freeze front >/dev/null; settle 1
bridge --do freeze-mark "$(freeze_at "$(bridge --js "$CASE_DIR/pages/drag.html" "const r = document.querySelector('h2').getBoundingClientRect(); return (r.left + 20) + ' ' + (r.top + r.height / 2)" | jq -r .)")" >/dev/null; settle 0.3
glass "document.querySelector('.bridge-composer:popover-open textarea').value = 'Halb geschrieben'" >/dev/null
before=$(pin_x); drag
check "dragging a new pin moves it and keeps its note open with what you typed" "$(( $(pin_x) - before )) $(glass "const c = document.querySelector('.bridge-composer:popover-open'); return c ? c.querySelector('textarea').value : 'closed'" | jq -r .)" "60 Halb geschrieben"
glass "document.querySelector('.bridge-composer:popover-open textarea').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', shiftKey: true, bubbles: true }))" >/dev/null; settle 0.3
check_json "⇧↩ does not save" "$(bridge --state)" '.freeze.notes | length' "0"
glass "document.querySelector('.bridge-composer:popover-open textarea').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))" >/dev/null; settle 0.8
moved=$(bridge --state | jq -r '.freeze.notes[0].anchor.x')
check "↩ saves it where it was dropped" "$(bridge --state | jq -r '[(.freeze.notes | length), .freeze.notes[0].text] | join(" ")') $(glass "return document.querySelectorAll('.bridge-composer:popover-open').length" | jq -r .)" "1 Halb geschrieben 0"
before=$(pin_x); drag
check "dragging a saved pin moves it and its record, and does not open its note" "$(( $(pin_x) - before )) $(bridge --state | jq -r --argjson m "$moved" '.freeze.notes[0].anchor.x > $m') $(glass "return document.querySelectorAll('.bridge-composer:popover-open').length" | jq -r .)" "60 true 0"
glass "document.querySelector('.bridge-pin').click()" >/dev/null; settle 0.5
glass "document.querySelector('.bridge-composer:popover-open textarea').value = 'Halb geschrieben, jetzt fertig'; document.querySelector('.bridge-composer:popover-open textarea').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', metaKey: true, bubbles: true }))" >/dev/null
for i in $(seq 1 40); do [ "$(bridge --state | jq '.freeze == null')" = true ] && break; settle 0.1; done
settle 0.5
check "⌘↩ saves and sends to the picked agent at once" "$(bridge --state | jq '.freeze == null') $(bridge --pins "$CASE_DIR/pages/drag.html" | jq -r '.[0].text')" "true Halb geschrieben, jetzt fertig"
finish
