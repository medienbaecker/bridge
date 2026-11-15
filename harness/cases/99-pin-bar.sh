#!/bin/bash
source "$(dirname "$0")/../lib.sh"
# serial
long="Donaudampfschifffahrtsgesellschaftskapitaenswitwenrentenantragsformular"
for n in 01 02 03 04 05 06 07 08 09 10 11 12; do
  project="$CASE_DIR/consectetur-adipiscing-$n"
  [ "$n" = 01 ] && project="$CASE_DIR/lorem"
  [ "$n" = 02 ] && project="$CASE_DIR/$long-$n"
  mkdir -p "$project"; git -C "$project" init -q
  transcript="$(dirname "$BRIDGE_CLAUDE_SESSIONS")/projects/$(cd "$project" && pwd | sed 's/[^A-Za-z0-9]/-/g')"
  mkdir -p "$transcript"
  title="Lorem ipsum dolor sit amet $n"
  [ "$n" = 01 ] && title="Kurz"
  [ "$n" = 02 ] && title="$long ueberarbeiten"
  printf '{"type":"ai-title","aiTitle":"%s"}\n' "$title" > "$transcript/test-$CASE_NAME-$n.jsonl"
  (cd "$project" && claude_session "test-$CASE_NAME-$n" idle)
done
first="$CASE_DIR/lorem"
printf '<!doctype html><title>Lorem ipsum</title><p>Lorem ipsum</p>' > "$first/plan.html"
(cd "$first" && BRIDGE_SESSION="test-$CASE_NAME-01" bridge plan.html); wait_ready; settle 0.3
screen="$XDG_STATE_HOME/bridge-dev/freeze/screen.html"
on_screen() { bridge --js "$screen" "@bridge $1"; }
note() { bridge --do freeze-mark "$1" >/dev/null; settle 0.3; bridge --do freeze-note "$2" >/dev/null; settle 0.5; }
picture() { bridge --shot "$CASE_DIR/shots/$1.png" --screen >/dev/null; }

bridge --do freeze >/dev/null; settle 1.5
picture empty
check "twelve agents are on the bar" "$(on_screen "return document.querySelectorAll('.bridge-agents-list button').length" | jq -r .)" "12"
check_json "before the first note the bar is dimmed and its buttons take no pointer" "$(on_screen "const bar = document.querySelector('.bridge-agents'); const chip = bar.querySelector('button'); const r = chip.getBoundingClientRect(); return [bar.hasAttribute('data-empty'), getComputedStyle(bar.querySelector('.bridge-agents-list')).opacity < 0.6, getComputedStyle(bar.querySelector('.bridge-agents-draft')).opacity < 0.6, document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2).tagName]")" 'map(tostring) | join(",")' "true,true,true,DIV"
check_json "a chip is never wider than 280, a long name and a long project each end in an ellipsis" "$(on_screen "const chips = [...document.querySelectorAll('.bridge-agents-list button')]; const cut = (el) => el.scrollWidth > el.clientWidth && getComputedStyle(el).textOverflow === 'ellipsis'; return [Math.max(...chips.map((c) => Math.round(c.getBoundingClientRect().width))), cut(chips[1].querySelector('b')), cut(chips[1].querySelector('small')), chips[0].querySelector('b').scrollWidth > chips[0].querySelector('b').clientWidth]")" 'map(tostring) | join(",")' "280,true,true,false"
check_json "keys 1 to 9 are labelled, the tenth chip on shows no key" "$(on_screen "return [...document.querySelectorAll('.bridge-agents-list button')].map((c) => c.querySelector('kbd').offsetWidth > 0 ? c.querySelector('kbd').textContent : '-').join('')")" '.' "123456789---"
check_json "the list overflows, so its far edge fades and its near edge does not" "$(on_screen "const list = document.querySelector('.bridge-agents-list'); return [list.scrollWidth > list.clientWidth, list.hasAttribute('data-before'), list.hasAttribute('data-after'), getComputedStyle(list).maskImage.includes('32px')]")" 'map(tostring) | join(",")' "true,false,true,true"
bottom=$(bridge --state | jq -r '.freeze.screenFrame[3] - 12')
bridge --do freeze-scroll "400 $bottom 200 0" >/dev/null; settle 0.3
check_json "scrolled into the middle, both edges fade" "$(on_screen "const list = document.querySelector('.bridge-agents-list'); return [list.scrollLeft > 0, list.hasAttribute('data-before'), list.hasAttribute('data-after')]")" 'map(tostring) | join(",")' "true,true,true"
picture scrolled
bridge --do freeze-scroll "400 $bottom 5000 0" >/dev/null; settle 0.3
check_json "at the end, only the near edge fades" "$(on_screen "const list = document.querySelector('.bridge-agents-list'); return [list.hasAttribute('data-before'), list.hasAttribute('data-after')]")" 'map(tostring) | join(",")' "true,false"
bridge --do freeze-scroll "400 $bottom -5000 0" >/dev/null; settle 0.3

note "200 200" "Lorem ipsum"
picture noted
check_json "with a note the bar is lit and its buttons take the pointer" "$(on_screen "const bar = document.querySelector('.bridge-agents'); const chip = bar.querySelector('button'); const r = chip.getBoundingClientRect(); return [getComputedStyle(bar.querySelector('.bridge-agents-list')).opacity, document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2).closest('button') === chip]")" 'map(tostring) | join(",")' "1,true"
check "nobody is picked" "$(bridge --state | jq -r '.freeze.picked')" "null"
on_screen "document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }))" >/dev/null; settle 0.1
check "Return with notes and nobody picked shakes the agents and stays" "$(on_screen "return document.querySelector('.bridge-agents-list').getAnimations().length > 0" | jq -r .) $(bridge --state | jq '.freeze != null')" "true true"
on_screen "document.dispatchEvent(new KeyboardEvent('keydown', { key: '9', bubbles: true, cancelable: true }))" >/dev/null
for i in $(seq 1 30); do [ "$(inbox "test-$CASE_NAME-09" 1 | grep -c 'sent you notes')" = 1 ] && break; settle 0.1; done
check "9 sends to the ninth agent" "$(inbox "test-$CASE_NAME-09" | grep -c 'sent you notes')" "1"
finish
