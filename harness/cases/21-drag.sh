#!/bin/bash
# Moving a pin: drag it onto another element and it re-anchors there, thread,
# replies and state intact; the answer and version do not move; it survives a
# patch and a reload. A short press is still a click.
source "$(dirname "$0")/../lib.sh"
page=$(fixture decision.html)
repo
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready
js() { bridge --js "$page" "$1"; }
js "document.querySelector('[data-value=grid]').click(); return 1" >/dev/null
bridge --do point >/dev/null
js "const el = document.querySelector('[data-value=list] strong'); const r = el.getBoundingClientRect(); el.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true, clientX: r.left + 10, clientY: r.top + 5})); return 1" >/dev/null; settle
js "const t = document.querySelector('.bridge-thread textarea'); t.value = 'move me'; t.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', metaKey: true, bubbles: true})); return 1" >/dev/null; settle 0.3
id=$(bridge --pins "$page" | jq -r '.[0].id')
bridge --reply "$page" "$id" "on it"; settle 0.3
before=$(bridge --read "$page" | jq -c '{version, answers}')

drag() { js "const pin = document.querySelector('.bridge-pin'); const p = pin.getBoundingClientRect(); const to = document.querySelector('$1').getBoundingClientRect(); const at = (x, y) => ({bubbles: true, cancelable: true, clientX: x, clientY: y, pointerId: 1, button: 0, isPrimary: true}); pin.dispatchEvent(new PointerEvent('pointerdown', at(p.left + 11, p.top + 11))); for (const f of [0.25, 0.5, 0.75, 1]) pin.dispatchEvent(new PointerEvent('pointermove', at(p.left + 11 + (to.left + 12 - p.left - 11) * f, p.top + 11 + (to.top + 8 - p.top - 11) * f))); pin.dispatchEvent(new PointerEvent('pointerup', at(to.left + 12, to.top + 8))); return 1" >/dev/null; settle 0.4; }

drag "[data-value=grid] strong"
pins=$(bridge --pins "$page")
check_json "the pin re-anchored to the element it landed on" "$pins" '.[0].target' 'strong "Grid"'
check_json "same note, same id" "$pins" '.[0].id' "$id"
check_json "the thread came with it" "$pins" '.[0].said[0].text' "on it"
check_json "not lost" "$pins" '.[0].lost' "false"
check "answer and version did not move" "$(bridge --read "$page" | jq -c '{version, answers}')" "$before"
check_json "the anchor is finite" "$(cat "$(sidecar "$page")" | jq -c '[.comments[0].anchor.x, .comments[0].anchor.y] | map(type == "number" and . >= 0 and . <= 1) | all')" '.' "true"
check_json "the pin sits on Grid now" "$(js "return document.querySelector('[data-value=grid] strong').style.anchorName")" '.' "--bridge-at-$id"
check_json "a short press is still a click" "$(js "const pin = document.querySelector('.bridge-pin'); const p = pin.getBoundingClientRect(); const at = (x, y) => ({bubbles: true, cancelable: true, clientX: x, clientY: y, pointerId: 1, button: 0}); pin.dispatchEvent(new PointerEvent('pointerdown', at(p.left + 11, p.top + 11))); pin.dispatchEvent(new PointerEvent('pointermove', at(p.left + 12, p.top + 12))); pin.dispatchEvent(new PointerEvent('pointerup', at(p.left + 12, p.top + 12))); pin.click(); return document.querySelector('.bridge-thread:popover-open') !== null")" '.' "true"
snap moved "The pin moved onto Grid, thread along"

sed -i '' 's/140 entries/141 entries/' "$page"; settle 0.5
check_json "survives a patch" "$(bridge --pins "$page")" '.[0].target + " " + (.[0].lost | tostring)' 'strong "Grid" false'
bridge --quit; sleep 0.4
(cd "$CASE_DIR/pages" && bridge decision.html); wait_ready; settle 0.4
check_json "survives a reload, re-resolved" "$(js "return document.querySelector('[data-value=grid] strong').style.anchorName")" '.' "--bridge-at-$id"
finish
