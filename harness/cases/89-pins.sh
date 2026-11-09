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
check "the two pins on the page land on it, the one elsewhere becomes a draft" "$(bridge --pins "$page" | jq -c 'map(.text[0:10])') $(drafts)" '["Überschrif","Donaudampf"] 1'
check_json "--pins names the element each one sits on, with its picture" "$(bridge --pins "$page")" 'map([.element, (.picture | test("\\.[12]\\.png$"))] | map(tostring) | join(" ")) | join(",")' "h2 true,#send true"
check "the agent is told about the page and the draft" "$(inbox "$agent" | grep -c 'pinned notes on `'"$page"'`') $(inbox "$agent" | grep -c 'numbered note')" "1 1"
check "the page shows each pin on its element" "$(on 1 h2) $(on 2 '#send')" "true true"
row=$(bridge --state | jq -r '[.sidebar[].bridges[] | select(.location | contains("/drafts/"))][0].subtitle')
check "the draft waits as a message to the agent's project" "$row" "Sent to pages"

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
finish
