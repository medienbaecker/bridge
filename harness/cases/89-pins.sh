#!/bin/bash
source "$(dirname "$0")/../lib.sh"
# serial
agent="test-$CASE_NAME-agent"
page="$CASE_DIR/pages/section.html"
write() { printf '<!doctype html><title>Section IX without the form</title><style>body{margin:0;font:16px/1.5 system-ui} h2,p,button{margin:16px}</style>%s<div style="height:150vh"></div><p id="last">Ut enim ad minim veniam, quis nostrud exercitation.</p>' "$1" > "$page"; }
write '<h2>Abschnitt IX</h2><p>Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p><button id="send" onclick="document.title = \x27clicked\x27">Absenden</button>'
repo
(cd "$CASE_DIR/pages" && claude_session "$agent" idle)
(cd "$CASE_DIR/pages" && BRIDGE_SESSION="$agent" bridge section.html); wait_ready; settle 0.3
js() { bridge --js "$page" "$1"; }
pinning() { js "@bridge return [document.documentElement.hasAttribute('data-bridge-pinning'), getComputedStyle(document.body).cursor.startsWith('url(')].join()" | jq -r .; }
point() { bridge --state | jq -r '.toolbar[] | select(.id == "point") | .prominent'; }
on() { js "@bridge const pin = document.querySelector('.bridge-pin[data-n=\"$1\"]'); const el = document.querySelector('$2'); if (!pin || !el) return 'missing'; const p = pin.getBoundingClientRect(), r = el.getBoundingClientRect(); const x = (p.left + p.right) / 2, y = p.bottom; return x >= r.left && x <= r.right && y >= r.top - 1 && y <= r.bottom + 1" | jq -r .; }
open() { js "@bridge const n = document.querySelector('.bridge-composer:popover-open textarea'); return n ? n.value : 'closed'" | jq -r .; }
press() { js "@bridge const pin = document.querySelector('.bridge-pin[data-n=\"$1\"]'); const r = pin.getBoundingClientRect(); const at = { bubbles: true, clientX: r.left + r.width / 2, clientY: r.top + r.height / 2, button: 0 }; pin.dispatchEvent(new PointerEvent('pointerdown', at)); pin.dispatchEvent(new PointerEvent('pointerup', at)); pin.click()" >/dev/null; settle 0.3; }
told() { inbox "$agent" 5 | grep -c 'pinned to elements'; }

bridge --do point >/dev/null; settle 0.3
check "Point on a Bridge page pins on the page: its cursor is the pin, the button is lit, and the screen stays as it is" "$(pinning) $(point) $(bridge --state | jq '.freeze != null')" "true,true true false"
page_mark "$page" h2
check "a click on the page opens a note on the element" "$(js "@bridge return !!document.querySelector('.bridge-composer:popover-open')" | jq -r .) $(on 1 h2)" "true true"
page_note "$page" "Überschrift größer"
page_mark "$page" "#send" box
page_note "$page" "Donaudampfschifffahrtsgesellschaftskapitänswitwenrentenantragsformular statt Absenden"
check "the pins land on their elements, the box on the button" "$(bridge --pins "$page" | jq -c 'map([.element, .text[0:10]])') $(js "@bridge return document.querySelectorAll('.bridge-box').length" | jq -r .)" '[["h2","Überschrif"],["#send","Donaudampf"]] 1'
check "--pins names what each one sits on, with no picture" "$(bridge --pins "$page" | jq -c 'map([.target, .picture])')" '[["h2 \"Abschnitt IX\"",null],["button \"Absenden\"",null]]'
check "the page shows each pin on its element, and the button under the box was not clicked" "$(on 1 h2) $(on 2 '#send') $(js "return document.title" | jq -r .)" "true true Section IX without the form"
drag() { js "@bridge const pin = document.querySelector('.bridge-pin[data-n=\"$1\"]'); const r = pin.getBoundingClientRect(), to = document.querySelector('$2').getBoundingClientRect(); const x = r.left + r.width / 2, y = r.bottom, dx = to.left + 30 - x, dy = to.top + to.height / 2 - y; const at = (d) => ({ bubbles: true, clientX: x + d * dx, clientY: y + d * dy, button: 0, buttons: 1, pointerId: 1 }); pin.dispatchEvent(new PointerEvent('pointerdown', at(0))); for (const d of [0.1, 0.5, 1]) pin.dispatchEvent(new PointerEvent('pointermove', at(d))); pin.dispatchEvent(new PointerEvent('pointerup', at(1))); pin.click()" >/dev/null; settle 0.8; }
drag 1 p
check "a pin dragged onto another element moves there, without opening its note" "$(bridge --pins "$page" | jq -r '.[0].element') $(on 1 p) $(open)" "p:nth-of-type(1) true closed"
drag 1 h2
check "nothing reaches the agent before Send" "$(told) $(bridge --read "$page" | jq -r .status)" "0 open"

js "@bridge scrollTo(0, 400)" >/dev/null; settle 0.3
check "the page scrolls in pin mode and the pins go with their elements" "$(js "@bridge return scrollY" | jq -r .) $(on 1 h2)" "400 true"
js "@bridge document.querySelector('#last').scrollIntoView()" >/dev/null; settle 0.3
page_mark "$page" "#last"
page_note "$page" "Lorem"
check "a pin lands further down too" "$(on 3 '#last')" "true"
js "@bridge scrollTo(0, 0)" >/dev/null; settle 0.3

js "@bridge document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))" >/dev/null; settle 0.3
check "Escape ends pin mode, and the pins stay" "$(pinning) $(point) $(js "@bridge return document.querySelectorAll('.bridge-pin').length" | jq -r .)" "false,false false 3"
js "@bridge document.querySelector('h2').click()" >/dev/null; settle 0.3
check "a click on the page now drops no pin" "$(open) $(bridge --pins "$page" | jq length)" "closed 3"

press 2
check "clicking a pin opens its note to edit" "$(open | cut -c1-9)" "Donaudamp"
check_json "beside its pin, not elsewhere on the page" "$(js "@bridge const p = document.querySelector('.bridge-pin[data-n=\"2\"]').getBoundingClientRect(), c = document.querySelector('.bridge-composer:popover-open').getBoundingClientRect(); return Math.min(Math.abs(c.top - p.bottom), Math.abs(p.top - c.bottom)) < 40 && Math.abs(c.left - p.left) < 40")" '.' "true"
check_json "the note stays inside the window at 320 wide" "$(bridge --do resize "320 600" >/dev/null; settle 0.5; js "@bridge const r = document.querySelector('.bridge-composer:popover-open').getBoundingClientRect(); return r.left >= 0 && r.right <= innerWidth")" '.' "true"
bridge --do resize "1180 800" >/dev/null; settle 0.5
press 2
for i in 1 2 3; do press 2; press 2; done
check "it opens and closes again and again" "$(open)" "closed"
press 3
js "@bridge document.querySelector('.bridge-composer:popover-open [data-act=delete]').click()" >/dev/null; settle 0.5
check "Delete takes the pin off" "$(bridge --pins "$page" | jq length) $(js "@bridge return document.querySelectorAll('.bridge-pin').length" | jq -r .)" "2 2"

bridge --do send >/dev/null; settle 0.5
check "Send tells the agent about the pins with the answer" "$(told) $(bridge --read "$page" | jq -r .status)" "1 sent"
press 1
page_note "$page" "Überschrift kleiner"
check "editing a pin after Send puts the page back to Send" "$(bridge --read "$page" | jq -r .status) $(bridge --pins "$page" | jq -r '.[0].text')" "open Überschrift kleiner"

bridge --do point >/dev/null; settle 0.3
page_mark "$page" p
page_note "$page" "Sed do eiusmod" true
check "⌘↩ in a note saves it, sends the page and ends pin mode" "$(bridge --read "$page" | jq -r .status) $(bridge --pins "$page" | jq length) $(pinning) $(point)" "sent 3 false,false false"

write '<p>Neu davor: sed do eiusmod tempor incididunt ut labore.</p><h2>Abschnitt IX</h2><p>Lorem ipsum dolor sit amet, consectetur adipiscing elit.</p>'
for i in $(seq 1 40); do [ "$(js "@bridge return document.querySelectorAll('.bridge-pin[data-lost]').length" | jq -r .)" = 1 ] && break; settle 0.1; done
check "after a rewrite the pin finds its heading where it moved" "$(on 1 h2)" "true"
check_json "and the button's pin, its element gone, waits in the corner, marked lost" "$(js "@bridge const pin = document.querySelector('.bridge-pin[data-n=\"2\"]'); const r = pin.getBoundingClientRect(); return [pin.hasAttribute('data-lost'), r.right > innerWidth - 60, r.top < 80]")" 'map(tostring) | join(",")' "true,true,true"
press 2
check_json "its note says so" "$(js "@bridge return document.querySelector('.bridge-composer:popover-open .bridge-lost')?.textContent")" '.' "Pointing at nothing now"
js "@bridge document.querySelector('.bridge-composer:popover-open').hidePopover()" >/dev/null

id=$(bridge --pins "$page" | jq -r '.[1].id')
bridge --done "$page" "$id" >/dev/null; settle 0.5
check "--done takes its pin off the page" "$(bridge --pins "$page" | jq length) $(js "@bridge return document.querySelectorAll('.bridge-pin').length" | jq -r .)" "2 2"
bridge --reload "$page" >/dev/null; wait_ready; settle 0.5
check "a reload shows the open pins again on their elements" "$(on 1 h2) $(js "@bridge return document.querySelectorAll('.bridge-pin').length" | jq -r .)" "true 2"
finish
