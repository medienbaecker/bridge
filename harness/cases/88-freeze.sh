#!/bin/bash
source "$(dirname "$0")/../lib.sh"
# serial
agent="test-$CASE_NAME-agent"
printf '<!doctype html><title>Card layout for the archive</title><h1>Lorem ipsum</h1><p><button id="save">Speichern</button></p><section id="cards" style="height: 100vh"></section>' > "$CASE_DIR/pages/cards.html"
repo
transcript="$(dirname "$BRIDGE_CLAUDE_SESSIONS")/projects/$(cd "$CASE_DIR/pages" && pwd | sed 's/[^A-Za-z0-9]/-/g')"
mkdir -p "$transcript"
printf '{"type":"ai-title","aiTitle":"Old title"}\n{"type":"user"}\n{"type":"ai-title","aiTitle":"Freeze review"}\n' > "$transcript/$agent.jsonl"
other="test-$CASE_NAME-other"
printf '{"type":"ai-title","aiTitle":"Lorem draft"}\n' > "$transcript/$other.jsonl"
printf '<!doctype html><title>Dolor</title><p>Dolor sit amet</p>' > "$CASE_DIR/pages/other.html"
(cd "$CASE_DIR/pages" && claude_session "$agent" idle)
(cd "$CASE_DIR/pages" && claude_session "$other" idle)
(cd "$CASE_DIR/pages" && BRIDGE_SESSION="$agent" bridge cards.html); wait_ready; settle 0.3
(cd "$CASE_DIR/pages" && BRIDGE_SESSION="$other" bridge other.html); wait_ready; settle 0.3
bridge --do select "$CASE_DIR/pages/cards.html" >/dev/null; wait_ready; settle 0.3
screen="$XDG_STATE_HOME/bridge-dev/freeze/screen.html"
on_screen() { bridge --js "$screen" "@bridge $1"; }

bridge --do freeze >/dev/null
settle 0.3
bridge --do freeze >/dev/null; settle 0.5
(bridge --do freeze >/dev/null & bridge --do freeze >/dev/null & wait); settle 0.5
check_json "pressing the shortcut fast never leaves a second frozen screen behind" "$(bridge --state)" '.freezePanels <= 1' "true"
[ "$(bridge --state | jq '.freeze != null')" = true ] || { bridge --do freeze >/dev/null; settle 0.5; }
state=$(bridge --state)
check_json "the freeze covers the test screen, never the user's" "$state" '.freeze.screen' "Test Screen"
check_json "the screen is in point mode, a pin under the pointer" "$(on_screen "return [document.documentElement.hasAttribute('data-bridge-freeze'), getComputedStyle(document.body).cursor.startsWith('url(')]")" 'map(tostring) | join(",")' "true,true"
check_json "the cursor Bridge sets is the pin above the bar, the arrow on it" "$(on_screen "return [__bridge.pinsAt(innerWidth / 2, innerHeight / 2), __bridge.pinsAt(innerWidth / 2, innerHeight - 10)]")" 'map(tostring) | join(",")' "true,false"
check_json "the hover outline is drawn under the page, so pins and note boxes cover it" "$(bridge --state)" '.freeze.outlineUnderPage' "true"
check_json "over an agent the page shows the normal cursor" "$(on_screen "return getComputedStyle(document.querySelector('.bridge-agents button')).cursor")" '.' "auto"
centre=$(printf '%s' "$state" | jq -r '.freeze.screenFrame as $s | "\(.windowFrame.x - $s[0] + .windowFrame.width / 2) \(($s[1] + $s[3]) - (.windowFrame.y + .windowFrame.height) + .windowFrame.height / 2)"')
corner=$(printf '%s' "$centre" | awk '{ print $1 - 60, $2 - 60 }')
listed() { jq '.bridges | length' "$XDG_STATE_HOME/bridge-dev/list.json"; }
before=$(listed)
bridge --do freeze-mark "$centre" >/dev/null; settle 0.3; bridge --do freeze-note "Sit amet" >/dev/null; settle 0.5
bridge --do freeze-cancel >/dev/null; settle 0.3
check "Esc makes nothing" "$(listed)" "$before"
bridge --do freeze >/dev/null
for i in $(seq 1 60); do entrance=$(on_screen "const a = document.querySelector('.bridge-agents').getAnimations().find((a) => a.effect.getTiming().duration === 220); return a ? a.playState + ' ' + a.effect.getKeyframes()[0].translate : ''" | jq -r .); case "$entrance" in *100%) break;; esac; done
check "a later freeze slides the bar up again" "$entrance" "running 0px 100%"
settle 1
bridge --do freeze-hover "$centre" >/dev/null
for i in $(seq 1 20); do [ "$(bridge --state | jq '.freeze.highlight != null')" = true ] && break; settle 0.1; done
cards=$(bridge --js "$CASE_DIR/pages/cards.html" "@bridge const r = document.querySelector('#cards').getBoundingClientRect(); return [r.top, innerHeight]")
check_json "hovering over Bridge's own window outlines the element under the pointer, not the window, exactly on it" "$(bridge --state)" '.windowFrame.width as $w | ("'"$centre"'" | split(" ") | map(tonumber)) as [$x, $y] | .freeze.screenFrame as $s | ('"$cards"') as [$top, $height] | (($s[1] + $s[3]) - (.windowFrame.y + .windowFrame.height) + .windowFrame.height - $height + $top) as $want | .freeze.highlight | [length, (.[2] < $w * 0.9), ($x >= .[0] and $x <= .[0] + .[2] and $y >= .[1] and $y <= .[1] + .[3]), ((.[1] - $want) | fabs < 2)] | map(tostring) | join(",")' "4,true,true,true"
bridge --do freeze-mark "$centre" >/dev/null; settle 0.3
check_json "a click opens the composer" "$(on_screen "return !!document.querySelector('.bridge-thread:popover-open textarea')")" '.' "true"
first=$(on_screen "return [...document.querySelectorAll('.bridge-pin')].map((p) => p.dataset.n).join()")
check_json "while a note is open the cursor is the normal one everywhere, a text cursor in the box" "$(on_screen "const t = document.querySelector('.bridge-thread:popover-open'); return [getComputedStyle(t.querySelector('textarea')).cursor, getComputedStyle(t.querySelector('button')).cursor, getComputedStyle(document.body).cursor.startsWith('url(')]")" 'map(tostring) | join(",")' "auto,auto,false"
bridge --do freeze-note "Lorem ipsum dolor sit amet" >/dev/null; settle 0.5
check "over a Bridge window it is a screenshot note like any other, not a pin on the page" "$(bridge --state | jq -r '.freeze.notes | [length, .[0].text] | map(tostring) | join(",")') $(bridge --pins "$CASE_DIR/pages/cards.html" | jq length)" "1,Lorem ipsum dolor sit amet 0"
check_json "and the screen stays in point mode for the next one" "$(on_screen "return getComputedStyle(document.body).cursor.startsWith('url(')")" '.' "true"
bridge --do freeze-mark "40 40 $corner" >/dev/null; settle 0.3
check_json "a drag draws a box with its composer" "$(on_screen "return [document.querySelectorAll('.bridge-box').length, !!document.querySelector('.bridge-thread:popover-open')]")" 'map(tostring) | join(",")' "1,true"
check "each new pin shows its number at once" "$first $(on_screen "return [...document.querySelectorAll('.bridge-pin')].map((p) => p.dataset.n).join()")" '"1" "1,2"'
bridge --do freeze-note "Consectetur adipiscing elit" >/dev/null; settle 0.5
check_json "a box goes on the screenshot with its size" "$(bridge --state)" '.freeze.notes | [length, (.[1].anchor.w > 0)] | map(tostring) | join(",")' "2,true"

state=$(bridge --state)
check_json "the bar names the agents by their Claude Code title and project, then Draft" "$(on_screen "return [...document.querySelectorAll('.bridge-agents button')].map((b) => b.innerText.replace(/\\n/g, ' ')).join(' | ')")" '.' "1 Lorem draft pages | 2 Freeze review pages | Draft"
on_screen "document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))" >/dev/null; settle 0.3
check "started from another app, nothing is picked and Return does nothing" "$(bridge --state | jq -r '[.freeze != null, .freeze.picked] | map(tostring) | join(",")') $(on_screen "return document.querySelectorAll('[data-picked]').length")" "true,null 0"
bridge --do freeze-send 1 >/dev/null; settle 0.5
draft=$(jq -r '[.bridges[] | select(.location | contains("/drafts/"))][0].location' "$XDG_STATE_HOME/bridge-dev/list.json")
for i in $(seq 1 30); do read=$(cat "$(sidecar "$draft")" 2>/dev/null); [ "$(printf '%s' "$read" | jq -r .status)" = sent ] && break; settle 0.1; done
check "clicking the agent sends it straight away" "$(inbox "$agent" | grep -c '`screenshot` is their screen with their numbered notes') $(printf '%s' "$read" | jq -r .status)" "1 sent"
check_json "and you follow it into the agent's project, the draft still open" "$(bridge --state)" '.projects.scope as $s | [($s | startswith("project:") and (contains("/drafts") | not)), (.projects.rows | map(.key) | index($s) != null), (.selected == "'"$draft"'")] | map(tostring) | join(",")' "true,true,true"
crop=$(printf '%s' "$read" | jq -r '.comments[1].crop')
want=$(printf '%s' "$state" | jq -r --arg c "$corner" '(($c | split(" ")[0] | tonumber) - 40) * .backingScale | round')
check "--pins hands the agent the box's crop, as wide as the box" "$(bridge --pins "$draft" | jq -r '.[1].crop == "'"$crop"'"') $(sips -g pixelWidth "$crop" 2>/dev/null | awk -v w="$want" '/pixelWidth/ { d = $2 - w; print (d * d <= 4) ? "yes" : $2 }')" "true yes"
picture=$(printf '%s' "$read" | jq -r .answers.screenshot)
check "the marked screenshot is saved at the screen's pixel size" "$(sips -g pixelWidth "$picture" 2>/dev/null | awk '/pixelWidth/ {print $2}')" "$(printf '%s' "$state" | jq -r '(.freeze.screenFrame[2] * .backingScale) | floor')"
check_json "opened, the draft shows the marked screen and lists the notes, with no pins of its own" "$(bridge --js "$draft" "@bridge return [document.querySelector('#screen img').getAttribute('src').endsWith('.marked.png'), document.querySelector('#screen img').naturalWidth > 0, [...document.querySelectorAll('#notes li')].map((li) => li.textContent).join('|'), document.querySelectorAll('.bridge-pin').length]")" 'map(tostring) | join(",")' "true,true,Lorem ipsum dolor sit amet|Consectetur adipiscing elit,0"

before=$(listed)
bar=$(printf '%s' "$state" | jq -r '.freeze.screenFrame as $s | "\(.windowFrame.x - $s[0] + .windowFrame.width - 140) \(($s[1] + $s[3]) - (.windowFrame.y + .windowFrame.height) + 26)"')
bridge --do freeze >/dev/null; settle 1
check_json "a new freeze starts with no notes, the bar dimmed" "$(on_screen "return [document.querySelectorAll('.bridge-pin').length, document.querySelector('.bridge-agents').hasAttribute('data-empty')]")" 'map(tostring) | join(",")' "0,true"
bridge --do freeze-mark "$bar" >/dev/null; settle 0.3; bridge --do freeze-note "Lorem" >/dev/null; settle 0.5
check_json "a note on the window's toolbar names no URL" "$(bridge --state)" '.freeze.notes[0].target | test("http|file:") | not' "true"
bridge --do freeze-mark "300 300" >/dev/null; settle 0.3
on_screen "document.body.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true, clientX: 600, clientY: 600, button: 0, buttons: 1 }))" >/dev/null
on_screen "document.querySelector('.bridge-thread:popover-open')?.hidePopover(); document.body.dispatchEvent(new MouseEvent('click', { bubbles: true, clientX: 600, clientY: 600 }))" >/dev/null; settle 0.3
check_json "a click elsewhere closes an empty composer, dropping its pin, and places nothing" "$(on_screen "return [document.querySelectorAll('.bridge-pin').length, !!document.querySelector('.bridge-thread:popover-open')]")" 'map(tostring) | join(",")' "1,false"
bridge --do freeze-cancel >/dev/null; settle 0.3
bridge --do freeze >/dev/null; settle 1
bridge --do freeze-mark "100 100" >/dev/null; settle 0.3; bridge --do freeze-note "Lorem" >/dev/null
bridge --do freeze >/dev/null; settle 0.3
check "the shortcut again closes it, without making anything" "$(bridge --state | jq '.freeze == null') $(listed)" "true $before"
bridge --do freeze >/dev/null; settle 1
bridge --do freeze-send 0 >/dev/null; settle 0.3
open=$(bridge --state | jq '.freeze != null')
bridge --do freeze-cancel >/dev/null; settle 0.3
check "with no notes, an agent can't be picked and nothing is made" "$open $(listed)" "true $before"

bridge --do freeze >/dev/null; settle 1
bridge --do freeze-mark "2 300" >/dev/null; settle 0.3
check_json "by the left edge the composer stays inside the screen" "$(on_screen "const r = document.querySelector('.bridge-thread:popover-open').getBoundingClientRect(); return r.left >= 0 && r.right <= innerWidth")" '.' "true"
bridge --do freeze-note "Lorem" >/dev/null; settle 0.3
bridge --do freeze-cancel >/dev/null; settle 0.3

bridge --do select "$CASE_DIR/pages/cards.html" >/dev/null; settle 0.3
bridge --do freeze front >/dev/null; settle 1
check "started from Bridge, the agent of the selected page is chip 1, picked" "$(bridge --state | jq -r '.freeze.picked') $(on_screen "return [...document.querySelectorAll('.bridge-agents button')].map((b) => (b.hasAttribute('data-picked') ? '*' : '') + (b.querySelector('b') || b).textContent).join(' | ')")" "$agent \"*Freeze review | Lorem draft | Draft\""
check_json "and drawn like a hovered chip" "$(on_screen "const [picked, other] = document.querySelectorAll('.bridge-agents-list button'); return getComputedStyle(picked).backgroundColor !== getComputedStyle(other).backgroundColor")" '.' "true"
sent=$(inbox "$agent" | grep -c 'their numbered notes')
on_screen "document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))" >/dev/null; settle 0.5
check "with no notes, Return does nothing" "$(bridge --state | jq '.freeze != null') $(inbox "$agent" | grep -c 'their numbered notes')" "true $sent"
bridge --do freeze-mark "300 300" >/dev/null; settle 0.3; bridge --do freeze-note "Ut enim ad minim" >/dev/null; settle 0.5
on_screen "document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }))" >/dev/null; settle 1
check "Return sends it to the picked agent" "$(bridge --state | jq '.freeze == null') $(inbox "$agent" | grep -c 'their numbered notes') $(inbox "$other" 3 | grep -c 'their numbered notes')" "true $((sent + 1)) 0"

end_session "$agent"
end_session "$other"
bridge --do freeze >/dev/null; settle 1
bridge --do freeze-mark "40 $(bridge --state | jq -r '.freeze.screenFrame[3] - 36')" >/dev/null; settle 0.3
check_json "by the bottom edge the composer opens above its pin, inside the screen" "$(on_screen "const t = document.querySelector('.bridge-thread:popover-open').getBoundingClientRect(); const p = [...document.querySelectorAll('.bridge-pin')].pop().getBoundingClientRect(); return t.bottom <= p.top + 1 && t.top >= 0")" '.' "true"
bridge --do freeze-note "Sed do eiusmod" >/dev/null; settle 0.5
check_json "with no agent running, the bar offers only Draft" "$(on_screen "return [...document.querySelectorAll('.bridge-agents button')].map((b) => b.innerText).join()")" '.' "Draft"
bridge --do freeze-send 0 >/dev/null; wait_ready; settle 0.5
check_json "which opens the draft" "$(bridge --state)" '.title' "Sed do eiusmod"
bridge --do point >/dev/null; settle 1
check_json "the Point button starts the freeze" "$(bridge --state)" '.freeze != null' "true"
bridge --do freeze-cancel >/dev/null; settle 0.3
finish
