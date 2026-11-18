#!/bin/bash
source "$(dirname "$0")/../lib.sh"
# serial
agent="test-$CASE_NAME-agent"
page="$CASE_DIR/pages/plan.html"
printf '<!doctype html><title>Lorem ipsum</title><style>body{margin:0;background:white}</style><div id="target" style="margin:60px 40px;width:200px;height:80px"></div>' > "$page"
repo
(cd "$CASE_DIR/pages" && claude_session "$agent" idle)
(cd "$CASE_DIR/pages" && BRIDGE_SESSION="$agent" bridge plan.html); wait_ready; settle 0.3
screen="$XDG_STATE_HOME/bridge-dev/freeze/screen.html"
on_screen() { bridge --js "$screen" "@bridge $1"; }
note() { bridge --do freeze-mark "$1" >/dev/null; settle 0.3; bridge --do freeze-note "$2" >/dev/null; settle 0.5; }
type_in() { on_screen "const box = document.querySelector('.bridge-composer:popover-open textarea'); box.value = $1; box.dispatchEvent(new Event('input', { bubbles: true }))" >/dev/null; settle 0.3; }
picture() { bridge --shot "$CASE_DIR/shots/$1.png" --screen >/dev/null; }
measure() { python3 "$ROOT/harness/measure.py" "$@"; }
colours() { measure "$1" region $2 | awk '{ print ($2 > 3) ? "inked" : $2 }'; }
around() { jq -rn --arg at "$1" --argjson p "$2" --argjson k "$3" --argjson box "$4" '($at | split(" ") | map(tonumber)) as [$x, $y] | [$x - $p[0] + $box[0], $y - $p[1] + $box[1], $x - $p[0] + $box[2], $y - $p[1] + $box[3]] | map(. * $k | round) | join(" ")'; }
bridge --do resize "1180 1000" >/dev/null; settle 0.5
scale=$(bridge --state | jq -r '.backingScale')

# ---- the agent's picture: a ring on the spot, the badge beside it

bridge --do freeze >/dev/null; settle 1
blank=$(freeze_at "400 190")
corner=$(freeze_at "0 0")
target=$(freeze_at "$(bridge --js "$page" "const r = document.querySelector('#target').getBoundingClientRect(); return (r.left + r.width / 2) + ' ' + (r.top + r.height / 2)" | jq -r .)")
note "$blank" "Lorem ipsum"
framed=$(bridge --state | jq -c '.freeze.pictures[0]')
note "$target" "Dolor sit amet"
picture pinned
bridge --do freeze-send 0 >/dev/null
for i in $(seq 1 40); do [ "$(inbox "$agent" | grep -c 'sent you notes')" = 1 ] && break; settle 0.1; done
settle 0.5
first=$(inbox "$agent" | grep -o '/[^ ]*\.1\.png$')
cp "$first" "$CASE_DIR/shots/agent-pin.png"
check "in the agent's picture the spot itself stays visible, a ring around it and the badge beside it" "$(colours "$first" "$(around "$blank" "$framed" "$scale" '[-2,-2,2,2]')") $(colours "$first" "$(around "$blank" "$framed" "$scale" '[-8,-8,8,8]')") $(colours "$first" "$(around "$blank" "$framed" "$scale" '[6,-18,18,-6]')")" "1 inked inked"

# ---- pins already on a page stay out of the next capture

bridge --do point >/dev/null; settle 0.3
page_mark "$page" "#target"
page_note "$page" "Dolor sit amet"
bridge --do point >/dev/null; settle 0.3
for i in $(seq 1 40); do [ "$(bridge --js "$page" "@bridge return document.querySelectorAll('.bridge-pin').length" | jq -r .)" = 1 ] && break; settle 0.1; done
old=$(bridge --js "$page" "@bridge const r = document.querySelector('.bridge-pin').getBoundingClientRect(); return [r.left - 4, r.top - 4, r.right + 4, r.bottom + 4]")
inner=$(bridge --state | jq -r '"\(.pageX) \(.pageY)"')
there() { jq -rn --arg c "$1" --argjson o "$old" --argjson k "$scale" '($c | split(" ") | map(tonumber)) as [$x, $y] | [$o[0] + $x, $o[1] + $y, $o[2] + $x, $o[3] + $y] | map(. * $k | round) | join(" ")'; }
picture before
bridge --do freeze >/dev/null; settle 1
for i in $(seq 1 30); do [ "$(bridge --state | jq '.freeze.frozen')" = true ] && break; settle 0.1; done
settle 0.3
picture frozen
check "the page's own pin is there before, and not on the frozen screen" "$(colours "$CASE_DIR/shots/before.png" "$(there "$inner")") $(colours "$CASE_DIR/shots/frozen.png" "$(there "$corner")")" "inked 1"
check_json "once captured, the page shows its pin again under the glass" "$(bridge --js "$page" "@bridge return [document.documentElement.hasAttribute('data-bridge-capturing'), getComputedStyle(document.querySelector('.bridge-pin')).visibility]")" 'map(tostring) | join(",")' "false,visible"
note "$blank" "Consectetur"
check_json "the new pin starts at 1, the only number on screen" "$(on_screen "return [...document.querySelectorAll('.bridge-pin')].map((p) => p.dataset.n).join()")" '.' "1"

# ---- edges

bridge --do freeze-mark "600 10" >/dev/null; settle 0.3
picture top
check_json "a pin near the top hangs below its spot, whole, its tip on the spot" "$(on_screen "const pin = [...document.querySelectorAll('.bridge-pin')].pop(); const r = pin.getBoundingClientRect(); return [pin.hasAttribute('data-below'), r.top >= 0, Math.abs(r.top - 10) < 2, Math.abs((r.left + r.right) / 2 - 600) < 2]")" 'map(tostring) | join(",")' "true,true,true,true"
check_json "and its note opens under it, inside the screen" "$(on_screen "const pin = [...document.querySelectorAll('.bridge-pin')].pop().getBoundingClientRect(); const c = document.querySelector('.bridge-composer:popover-open').getBoundingClientRect(); return c.top >= pin.bottom && c.top >= 0")" '.' "true"
bridge --do freeze-note "Adipiscing" >/dev/null; settle 0.5
check_json "lower down a pin stands above its spot as before" "$(on_screen "const pin = document.querySelector('.bridge-pin'); const r = pin.getBoundingClientRect(); return [pin.hasAttribute('data-below'), r.bottom <= r.top + 40]")" 'map(tostring) | join(",")' "false,true"
item=$(bridge --state | jq -r '.freeze.screenFrame as $s | "\($s[2] - 300) 12"')
note "$item" "Elit sed do"
check_json "a pin on the menu bar pictures at least 240 points of height" "$(bridge --state)" '.freeze.pictures | map(.[3] >= 240) | join(",")' "true,true,true"

low=$(bridge --state | jq -r '.freeze.screenFrame as $s | "300 40 900 \($s[3] - 40)"')
bridge --do freeze-mark "$low" >/dev/null; settle 0.5
picture low-box
check_json "the note of a box as tall as the screen stays above the agents bar" "$(on_screen "const c = document.querySelector('.bridge-composer:popover-open').getBoundingClientRect(); const bar = document.querySelector('.bridge-agents').getBoundingClientRect(); return [c.height > 0, c.bottom <= bar.top - 8, c.top >= 0]")" 'map(tostring) | join(",")' "true,true,true"
box=$(on_screen "const r = document.querySelector('.bridge-composer:popover-open').getBoundingClientRect(); return [r.left, r.top, r.width, r.height].map(Math.round)" | jq -c .)
check "and the glass is under it there" "$(bridge --state | jq -c '.freeze.glass | map(round)')" "$box"

# ---- long notes

type_in "'Lorem ipsum'"
short=$(on_screen "return document.querySelector('.bridge-composer:popover-open textarea').offsetHeight" | jq -r .)
type_in "Array.from({ length: 5 }, (_, i) => 'Zeile ' + (i + 1) + ' Donaudampfschifffahrtsgesellschaft').join('\\n')"
five=$(on_screen "const t = document.querySelector('.bridge-composer:popover-open textarea'); return [t.offsetHeight, t.scrollHeight <= t.clientHeight].join()" | jq -r .)
picture five-lines
type_in "Array.from({ length: 30 }, (_, i) => 'Zeile ' + (i + 1) + ' Donaudampfschifffahrtsgesellschaft').join('\\n')"
picture thirty-lines
check_json "the note grows with its text: five lines fit without scrolling" "\"$short $five\"" 'split(" ") as [$short, $five] | ($five | split(",")) as [$h, $fits] | [($h | tonumber) > ($short | tonumber) + 40, $fits] | join(",")' "true,true"
check_json "at about eight lines it stops growing and scrolls" "$(on_screen "const t = document.querySelector('.bridge-composer:popover-open textarea'); const line = parseFloat(getComputedStyle(t).lineHeight); return [Math.round((t.clientHeight - 18) / line), t.scrollHeight > t.clientHeight, getComputedStyle(t).overflowY]")" 'map(tostring) | join(",")' "8,true,auto"
box=$(on_screen "const r = document.querySelector('.bridge-composer:popover-open').getBoundingClientRect(); return [r.left, r.top, r.width, r.height].map(Math.round)" | jq -c .)
check "grown, it is still above the bar with the glass exactly under it" "$(bridge --state | jq -c '.freeze.glass | map(round)') $(on_screen "return document.querySelector('.bridge-composer:popover-open').getBoundingClientRect().bottom <= document.querySelector('.bridge-agents').getBoundingClientRect().top - 8" | jq -r .)" "$box true"
bridge --do freeze-note "Tempor" >/dev/null; settle 0.5

# ---- a pin dragged off the screen

drag() { on_screen "const pin = document.querySelector('.bridge-pin[data-n=\"$1\"]'); const r = pin.getBoundingClientRect(); const x = r.left + r.width / 2, y = r.top + r.height / 2; const at = (d) => ({ bubbles: true, clientX: x + d * $2, clientY: y + d * $3, button: 0, buttons: 1, pointerId: 1 }); pin.dispatchEvent(new PointerEvent('pointerdown', at(0))); for (const d of [0.1, 0.5, 1]) pin.dispatchEvent(new PointerEvent('pointermove', at(d))); pin.dispatchEvent(new PointerEvent('pointerup', at(1))); pin.click()" >/dev/null; settle 0.8; }
inside() { bridge --state | jq -r --argjson n "$1" --argjson bar "$(on_screen "return document.querySelector('.bridge-agents').offsetTop / innerHeight")" '.freeze.notes[$n].anchor | [.x >= 0, .x + (.w // 0) <= 1, .y >= 0, .y + (.h // 0) <= $bar + 0.0001] | map(tostring) | join(",")'; }
drag 1 5000 5000
picture dragged
check "a pin dragged past the bottom right corner is saved on the screen, above the bar" "$(inside 0) $(bridge --state | jq -r '.freeze.notes[0].anchor.x')" "true,true,true,true 1"
drag 1 -9000 -9000
check "and past the top left corner, at the corner" "$(inside 0) $(bridge --state | jq -r '.freeze.notes[0].anchor | "\(.x) \(.y)"')" "true,true,true,true 0 0"
drag 4 5000 5000
check "a dragged box stays whole on the screen too" "$(inside 3)" "true,true,true,true"
picture dragged-box
bridge --do freeze-send 0 >/dev/null
for i in $(seq 1 40); do [ "$(inbox "$agent" | grep -c 'sent you notes')" = 2 ] && break; settle 0.1; done
settle 0.5
heights=""
for n in 1 2 3 4; do
  sent=$(inbox "$agent" | grep -o "/[^ ]*\.$n\.png$" | tail -1)
  cp "$sent" "$CASE_DIR/shots/agent-$n.png"
  heights="$heights$(sips -g pixelHeight "$sent" | awk -v least="$scale" '/pixelHeight/ { print ($2 >= 240 * least) ? "tall" : $2 }') "
done
check "every picture the agent gets, the corner pin's and the menu bar pin's too, is at least 240 points high" "$heights" "tall tall tall tall "
finish
