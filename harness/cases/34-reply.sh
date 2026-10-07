#!/bin/bash
# A reply on a note's thread: filed once, the box empties, the reply shows in
# the open thread, and pressing Reply again with nothing typed files nothing.
# On a done note, Reopen keeps what was typed, and a reply reopens it.
source "$(dirname "$0")/../lib.sh"
page="$CASE_DIR/pages/reply.html"
printf '<!doctype html><title>Reply</title><p id="para">A paragraph the user will pin and then reply on.</p>' > "$page"
repo
(cd "$CASE_DIR/pages" && bridge reply.html); wait_ready
js() { bridge --js "$page" "$1"; }
bridge --do point >/dev/null
js "const el = document.querySelector('#para'); const r = el.getBoundingClientRect(); el.dispatchEvent(new MouseEvent('click', {bubbles: true, clientX: r.left + 20, clientY: r.top + 8}))" >/dev/null; settle 0.3
js "const t = document.querySelector('.bridge-thread:popover-open textarea'); t.value = 'too heavy'; t.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', metaKey: true, bubbles: true}))" >/dev/null; settle 0.4
said() { jq -c '[.comments[0].said[] | select(.kind == "reply") | .text]' "$(sidecar "$page")"; }
check "a note, no replies yet" "$(said)" "[]"
js "document.querySelector('.bridge-pin[data-n=\"1\"]').click(); return 1" >/dev/null; settle 0.3
check_json "its thread is open" "$(js "return document.querySelector('.bridge-thread:popover-open') !== null")" '.' "true"
js "document.querySelector('.bridge-thread:popover-open textarea').value = 'eine Antwort'; document.querySelector('.bridge-thread:popover-open [data-act=reply]').click(); return 1" >/dev/null; settle 0.5
check "Reply files it once" "$(said)" '["eine Antwort"]'
check_json "and empties the box" "$(js "return document.querySelector('.bridge-thread:popover-open textarea').value")" '.' ""
check_json "and the reply is in the open thread" "$(js "return [...document.querySelectorAll('.bridge-thread:popover-open .bridge-say')].map(e => e.textContent).join('|')")" '. | contains("eine Antwort")' "true"
js "document.querySelector('.bridge-thread:popover-open [data-act=reply]').click(); return 1" >/dev/null; settle 0.5
check "Reply again with nothing typed files nothing" "$(said)" '["eine Antwort"]'
js "document.querySelector('.bridge-thread:popover-open textarea').dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', metaKey: true, bubbles: true})); return 1" >/dev/null; settle 0.4
check "and so does ⌘⏎ on an empty box" "$(said)" '["eine Antwort"]'
id=$(jq -r '.comments[0].id' "$(sidecar "$page")")
state() { jq -r '.comments[0].state' "$(sidecar "$page")"; }
bridge --done "$page" "$id"; settle 0.4
js "document.querySelector('.bridge-thread:popover-open textarea').value = 'noch eine Frage'; document.querySelector('.bridge-thread:popover-open [data-act=reopen]').click(); return 1" >/dev/null; settle 0.5
check "Reopen on a done note reopens it" "$(state)" "open"
check_json "and keeps what was typed" "$(js "return document.querySelector('.bridge-thread:popover-open textarea').value")" '.' "noch eine Frage"
bridge --done "$page" "$id"; settle 0.4
js "document.querySelector('.bridge-thread:popover-open [data-act=reply]').click(); return 1" >/dev/null; settle 0.5
check "a reply on a done note files it" "$(said)" '["eine Antwort","noch eine Frage"]'
check "and reopens the note" "$(state)" "open"
finish
