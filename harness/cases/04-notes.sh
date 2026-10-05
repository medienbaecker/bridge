#!/bin/bash
source "$(dirname "$0")/../lib.sh"

page=$(fixture decision.html)
repo
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready
js() { bridge --js "$page" "$1"; }

state=$(bridge --do point)
check_json "point mode is on" "$state" '.pointing' "true"
check_json "the page shows it" "$(js "return document.documentElement.hasAttribute('data-bridge-pointing')")" '.' "true"
snap pointing "Point mode: crosshair"

# Click the List option's title, as a real click would arrive
js "const el = document.querySelector('[data-value=list] strong'); const r = el.getBoundingClientRect(); el.dispatchEvent(new MouseEvent('click', {bubbles: true, clientX: r.left + 10, clientY: r.top + 5}))" >/dev/null
settle
check_json "clicking leaves point mode" "$(bridge --state)" '.pointing' "false"
check_json "a composer opened" "$(js "return document.querySelector('.bridge-thread:popover-open') !== null")" '.' "true"
check_json "the composer shows no location line: the user is looking at the thing they pinned" "$(js "return document.querySelector('.bridge-thread .bridge-target') === null")" '.' "true"
snap composer "Composer open where the user clicked"

js "const t = document.querySelector('.bridge-thread textarea'); t.value = 'too heavy at phone width'; t.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', metaKey: true, bubbles: true}))" >/dev/null
settle 0.3
pins=$(bridge --pins "$page")
check_json "one open note" "$pins" 'length' "1"
check_json "note text" "$pins" '.[0].text' "too heavy at phone width"
check_json "note target" "$pins" '.[0].target' 'strong "List"'
id=$(printf '%s' "$pins" | jq -r '.[0].id')
check_json "a numbered pin is on the page" "$(js "return document.querySelector('.bridge-pin[data-n=\"1\"]') !== null")" '.' "true"
check_json "pin is anchored to the element" "$(js "return document.querySelector('[data-value=list] strong').style.anchorName")" '.' "--bridge-at-$id"
state=$(bridge --state)
check_json "notes toolbar item is enabled" "$state" '[.toolbar[] | select(.id=="notes") | .enabled][0]' "true"
check_json "state counts the note" "$state" '.notes' "1"
snap pinned "Pin 1 saved"

# Agent replies and marks it done
bridge --working "$page" "$id"
bridge --reply "$page" "$id" "Dropped the padding at phone width, have a look"
settle 0.3
check_json "thread carries the reply" "$(bridge --read "$page")" '.comments[0].said | map(.text) | join(" / ")' "working on it / Dropped the padding at phone width, have a look"
check_json "row is unread after an agent reply" "$(bridge --state)" '.sidebar[0].bridges[0].unread' "true"
bridge --do notes >/dev/null
settle
check_json "notes popover shows" "$(bridge --state)" '.notesPopoverShown' "true"
snap popover "Notes popover: one line per note"
bridge --do notes >/dev/null
js "document.querySelector('.bridge-pin[data-n=\"1\"]').click()" >/dev/null
settle
check_json "thread shows the agent reply" "$(js "return [...document.querySelectorAll('.bridge-thread:popover-open .bridge-say')].map(s => s.textContent).join(' | ')")" '.' "Youtoo heavy at phone width | working on it | AgentDropped the padding at phone width, have a look"
snap thread "Thread with the agent's reply"
bridge --done "$page" "$id"
settle 0.3
check_json "done notes leave --pins" "$(bridge --pins "$page")" 'length' "0"
check_json "pin turns grey" "$(js "return document.querySelector('.bridge-pin').dataset.state")" '.' "done"
bridge --reopen "$page" "$id"
settle 0.3
check_json "reopen brings it back" "$(bridge --pins "$page")" '.[0].state' "open"

# The element disappears: the pin goes grey and says so
python3 - "$page" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace('<strong>List</strong>', '<em>List view</em>')
open(p,'w').write(s)
PY
settle 0.5
check_json "pin is lost" "$(js "return document.querySelector('.bridge-pin').hasAttribute('data-lost')")" '.' "true"
check_json "--pins says so" "$(bridge --pins "$page")" '.[0].lost' "true"
check_json "--read says so" "$(bridge --read "$page")" '.comments[0].lost' "true"
js "@bridge __bridgeNotes.open('$id')" >/dev/null
settle
check_json "thread says it points at nothing, as its own line" "$(js "return document.querySelector('.bridge-thread:popover-open .bridge-lost')?.textContent")" '.' "Pointing at nothing now"
snap lost "Element gone: grey pin, pointing at nothing"
python3 - "$page" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace('<em>List view</em>', '<strong>List</strong>')
open(p,'w').write(s)
PY
settle 0.5
check_json "pin finds its element again" "$(js "return document.querySelector('.bridge-pin').hasAttribute('data-lost')")" '.' "false"
check_json "--pins recovers" "$(bridge --pins "$page")" '.[0].lost' "false"

# A patch under an open composer keeps the draft
bridge --do point >/dev/null
js "const el = document.querySelector('h1'); const r = el.getBoundingClientRect(); el.dispatchEvent(new MouseEvent('click', {bubbles: true, clientX: r.left + 20, clientY: r.top + 8}))" >/dev/null
settle
js "document.querySelector('.bridge-thread:popover-open textarea').value = 'half typed'" >/dev/null
sed -i '' 's/140 entries/141 entries/' "$page"
settle 0.5
check_json "composer survived the patch" "$(js "return document.querySelector('.bridge-thread:popover-open textarea')?.value")" '.' "half typed"
finish
