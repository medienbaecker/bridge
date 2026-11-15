#!/bin/bash
source "$(dirname "$0")/../lib.sh"
# serial
agent="test-$CASE_NAME-agent"
printf '<!doctype html><title>Lorem ipsum</title><h2 style="margin:40px">Abschnitt IX</h2>' > "$CASE_DIR/pages/plan.html"
repo
(cd "$CASE_DIR/pages" && claude_session "$agent" idle)
(cd "$CASE_DIR/pages" && BRIDGE_SESSION="$agent" bridge plan.html); wait_ready; settle 0.3
screen="$XDG_STATE_HOME/bridge-dev/freeze/screen.html"
on_screen() { bridge --js "$screen" "@bridge $1"; }
note() { bridge --do freeze-mark "$1" >/dev/null; settle 0.3; bridge --do freeze-note "$2" >/dev/null; settle 0.5; }
type_in() { on_screen "const box = document.querySelector('.bridge-composer:popover-open textarea'); box.value = '$1'; box.dispatchEvent(new Event('input', { bubbles: true }))" >/dev/null; }
key() { on_screen "document.querySelector('$2').dispatchEvent(new KeyboardEvent('keydown', { key: '$1', bubbles: true, cancelable: true }))" >/dev/null; settle 0.3; }
pins() { on_screen "return [...document.querySelectorAll('.bridge-pin')].map((p) => p.dataset.n).join()" | jq -r .; }
open() { on_screen "return document.querySelectorAll('.bridge-composer:popover-open').length" | jq -r .; }
freezing() { bridge --state | jq '.freeze != null'; }
picture() { bridge --shot "$CASE_DIR/shots/$1.png" --screen >/dev/null; }

bridge --do freeze >/dev/null; settle 1
bridge --do freeze-mark "300 300" >/dev/null; settle 0.3
key Escape '.bridge-composer:popover-open textarea'
check "Escape on a new, empty pin drops it and stays in pin mode" "$(pins) $(open) $(freezing)" " 0 true"
bridge --do freeze-mark "300 300" >/dev/null; settle 0.3
type_in "Lorem ipsum dolor"
picture typed
key Escape '.bridge-composer:popover-open textarea'
picture escaped
check "Escape on a new pin with text typed drops the pin at once" "$(pins) $(open) $(freezing)" " 0 true"
bridge --do freeze-mark "300 300" >/dev/null; settle 0.3
check "and the text is gone with it: the next pin opens empty" "$(on_screen "return document.querySelector('.bridge-composer:popover-open textarea').value" | jq -r .)" ""
bridge --do freeze-note "Sit amet" >/dev/null; settle 0.5

on_screen "document.querySelector('.bridge-pin').click()" >/dev/null; settle 0.3
type_in "Sit amet, consectetur"
key Escape '.bridge-composer:popover-open textarea'
check "Escape while editing a saved note closes it and keeps the pin" "$(pins) $(open) $(bridge --state | jq -r '.freeze.notes[0].text')" "1 0 Sit amet"
on_screen "document.querySelector('.bridge-pin').click()" >/dev/null; settle 0.3
check "and the saved text is what opens again, as after Cancel" "$(on_screen "return document.querySelector('.bridge-composer:popover-open textarea').value" | jq -r .)" "Sit amet"
key Escape '.bridge-composer:popover-open textarea'

bridge --do freeze-cancel >/dev/null; settle 0.3
picture ask-one
check "Escape with a saved note asks first, and pin mode stays" "$(on_screen "return document.querySelector('.bridge-discard:popover-open p')?.textContent" | jq -r .) $(freezing)" "Discard 1 note? true"
check "the prompt offers Discard and Keep, Keep focused" "$(on_screen "return [...document.querySelectorAll('.bridge-discard button')].map((b) => b.dataset.act).join() + ' ' + document.activeElement.dataset.act" | jq -r .)" "discard,keep keep"
box=$(on_screen "const r = document.querySelector('.bridge-discard').getBoundingClientRect(); return [r.left, r.top, r.width, r.height].map(Math.round)" | jq -c .)
check "it sits on macOS's glass, as the composer does, in the middle of the screen" "$(bridge --state | jq -c '.freeze.glass | map(round)') $(on_screen "const r = document.querySelector('.bridge-discard').getBoundingClientRect(); return Math.abs(r.left + r.width / 2 - innerWidth / 2) < 1 && Math.abs(r.top + r.height / 2 - innerHeight / 2) < 1" | jq -r .)" "$box true"
key Enter '.bridge-discard [data-act=keep]'
check "Return keeps the notes and stays" "$(open) $(pins) $(freezing) $(bridge --state | jq -c '.freeze.glass')" "0 1 true null"
bridge --do freeze-cancel >/dev/null; settle 0.3
key Escape '.bridge-discard [data-act=keep]'
check "Escape on the prompt keeps them too" "$(open) $(pins) $(freezing)" "0 1 true"
note "500 300" "Dolor"
bridge --do freeze-cancel >/dev/null; settle 0.3
check "with two notes it counts them" "$(on_screen "return document.querySelector('.bridge-discard:popover-open p')?.textContent" | jq -r .)" "Discard 2 notes?"
picture ask-two
on_screen "document.querySelector('.bridge-discard [data-act=keep]').click()" >/dev/null; settle 0.3
check "Keep keeps" "$(open) $(pins) $(freezing)" "0 1,2 true"
bridge --do freeze-cancel >/dev/null; settle 0.3
on_screen "document.querySelector('.bridge-discard [data-act=discard]').click()" >/dev/null; settle 0.5
check "Discard ends pin mode and sends nothing" "$(freezing) $(inbox "$agent" 3 | grep -c 'sent you notes')" "false 0"

bridge --do freeze >/dev/null; settle 1
note "300 300" "Lorem"
bridge --do freeze-cancel >/dev/null; settle 0.3
bridge --do freeze >/dev/null; settle 0.5
check "the shortcut while the prompt is up ends pin mode" "$(freezing)" "false"
bridge --do freeze >/dev/null; settle 1
check "the next pin mode starts with no prompt and no pins" "$(on_screen "return document.querySelectorAll('.bridge-discard, .bridge-pin').length" | jq -r .)" "0"
bridge --do freeze-cancel >/dev/null; settle 0.3
check "with no saved notes, Escape ends pin mode at once" "$(freezing)" "false"
finish
