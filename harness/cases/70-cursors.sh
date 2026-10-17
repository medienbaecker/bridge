#!/bin/bash
source "$(dirname "$0")/../lib.sh"

page=$(fixture decision.html)
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready
js() { bridge --js "$page" "$1"; }
check_json "an unpaired Mac shows no Share button" "$(bridge --state)" '[.toolbar[] | select(.id == "share")][0].hidden' "true"
centre="const r = document.querySelector('[data-value=grid]').getBoundingClientRect(); return [Math.round(r.left + r.width / 2), Math.round(r.top + r.height / 2)]"

js "@bridge __bridge.trackCursor(true); const r = document.querySelector('[data-value=grid]').getBoundingClientRect(); document.querySelector('[data-value=grid]').dispatchEvent(new PointerEvent('pointermove', { bubbles: true, clientX: r.left + r.width / 2, clientY: r.top + r.height / 2 })); return 1" >/dev/null
settle 0.2
state=$(bridge --state)
check_json "moving the pointer reports the element under it" "$state" '.cursor.tag' "div"
check_json "with where on it" "$state" '(.cursor.x - 0.5 | fabs) < 0.05 and (.cursor.y - 0.5 | fabs) < 0.05' "true"
anchor=$(echo "$state" | jq -c '.cursor')

js "@bridge __bridge.cursors([{ person: 'yoshie', anchor: $anchor }]); return 1" >/dev/null
settle 0.2
at() { js "@bridge const c = document.querySelector('.bridge-cursor'); return c.hidden ? 'hidden' : [Math.round(parseFloat(c.style.left)), Math.round(parseFloat(c.style.top))]"; }
check "her cursor sits where she points" "$(at | jq -c .)" "$(js "$centre" | jq -c .)"
snap cursor "Yoshie's cursor on the grid option"
check "and carries her name" "$(js "@bridge return document.querySelector('.bridge-cursor span').textContent" | jq -r .)" "yoshie"

python3 - "$page" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace('<h2>Layout</h2>', '<p style="height:180px">Room above the options</p>\n<h2>Layout</h2>', 1)
open(p,'w').write(s)
PY
settle 0.5
check "after an edit moves the option down, her cursor follows it" "$(at | jq -c .)" "$(js "$centre" | jq -c .)"

js "@bridge __bridge.cursors([{ person: 'yoshie', anchor: $anchor, color: '#2f9e44' }, { person: 'mika', anchor: $anchor }, { person: 'ren', anchor: $anchor }]); return 1" >/dev/null
colours() { js "@bridge return [...document.querySelectorAll('.bridge-cursor')].map((c) => c.querySelector('span').textContent + ' ' + c.style.getPropertyValue('--bridge-cursor'))" | jq -r '.[]'; }
check "a chosen colour is used as it is" "$(colours | grep yoshie)" "yoshie #2f9e44"
check "people who chose none get different colours" "$(colours | grep -v yoshie | cut -d' ' -f2 | sort -u | wc -l | tr -d ' ')" "2"
check "the cursor is the system arrow" "$(js "@bridge return getComputedStyle(document.querySelector('.bridge-cursor')).getPropertyValue('--bridge-arrow').startsWith('url(\"data:image/png')")" "true"
snap colours "Three cursors on one option, one with a chosen colour"

js "@bridge __bridge.cursors([{ person: 'yoshie', anchor: { tag: 'section', selector: 'section.gone', classes: ['gone'], index: 0, text: '', x: 0.5, y: 0.5 } }]); return 1" >/dev/null
check "a cursor on something this page doesn't have hides" "$(at | jq -r .)" "hidden"
js "@bridge __bridge.cursors([]); return 1" >/dev/null
check "when she leaves, her cursor goes" "$(js "@bridge return document.querySelectorAll('.bridge-cursor').length")" "0"
js "const s = document.createElement('div'); s.style.height = '3000px'; document.querySelector('h1').after(s); scrollTo(0, 0); return 1" >/dev/null
note=$(js "@bridge const t = document.querySelector('textarea'); const r = t.getBoundingClientRect(); return { selector: 'textarea', tag: 'textarea', classes: [], index: 0, text: '', x: 0.5, y: 0.5 }" | jq -c .)
js "@bridge __bridge.cursors([{ person: 'yoshie', anchor: $note }]); return 1" >/dev/null
edge() { js "@bridge const c = document.querySelector('.bridge-cursor'); return c.dataset.off + ' ' + Math.round(parseFloat(c.style.top)) + ' ' + innerHeight" | jq -r .; }
read -r off top height <<< "$(edge)"
check "a cursor below the view shows at the bottom edge" "$off $(( height - top < 60 ))" "down 1"
snap edge "Her cursor is below the view: an arrow at the bottom edge"
js "@bridge document.querySelector('.bridge-cursor-off span').click(); return __bridge.following()" >/dev/null
check "clicking it follows her" "$(js "@bridge return __bridge.following()" | jq -r .)" "yoshie"
for i in $(seq 1 30); do [ "$(edge | cut -d' ' -f1)" = "" ] && break; js "@bridge __bridge.cursors([{ person: 'yoshie', anchor: $note }]); return 1" >/dev/null; sleep 0.1; done
check "the page scrolls until her cursor is in view" "$(edge | cut -d' ' -f1)" ""
check "and it is drawn as a cursor again" "$(js "@bridge return document.querySelector('.bridge-cursor').classList.contains('bridge-cursor-off')")" "false"
js "dispatchEvent(new WheelEvent('wheel', { deltaY: -100 })); return 1" >/dev/null
check "scrolling yourself stops following" "$(js "@bridge return __bridge.following()")" "null"

check "a Mac has no colour until one is chosen" "$(bridge --colour)" "none"
check "a colour is saved in lowercase" "$(bridge --colour '#E8590C')" "#e8590c"
check "and read back" "$(bridge --colour)" "#e8590c"
check "nonsense is refused" "$(bridge --colour orange 2>&1 >/dev/null)" "a colour is a hex value like #e8590c, or none"
check "none goes back to Bridge's pick" "$(bridge --colour none)" "none"
finish
