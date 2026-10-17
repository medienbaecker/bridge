#!/bin/bash
source "$(dirname "$0")/../lib.sh"

page=$(fixture decision.html)
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready
js() { bridge --js "$page" "$1"; }
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

js "@bridge __bridge.cursors([{ person: 'yoshie', anchor: { tag: 'section', selector: 'section.gone', classes: ['gone'], index: 0, text: '', x: 0.5, y: 0.5 } }]); return 1" >/dev/null
check "a cursor on something this page doesn't have hides" "$(at | jq -r .)" "hidden"
js "@bridge __bridge.cursors([]); return 1" >/dev/null
check "when she leaves, her cursor goes" "$(js "@bridge return document.querySelectorAll('.bridge-cursor').length")" "0"
finish
