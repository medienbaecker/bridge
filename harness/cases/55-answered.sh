#!/bin/bash
# A dial the user was only playing with must not be sent unnoticed. At rest a
# dial that answers wears the accent and one that only drives a preview is grey;
# once a control holds the user's answer it
# is marked at the control, a dot at a dial's readout, an accent edge on a field.
# The page's own proposal is never marked, and a reopen marks what is the user's.
source "$(dirname "$0")/../lib.sh"
page=$(fixture tune-answers.html)
repo
(cd "$CASE_DIR/pages" && bridge tune-answers.html) >/dev/null; wait_ready
js() { bridge --js "$page" "$1"; }
fill='(s) => getComputedStyle(document.querySelector(s).closest(".dial"), "::before").backgroundColor'
dot='(s) => getComputedStyle(document.querySelector(s).closest(".dial").querySelector("output"), "::before").width'
check_json "at rest the two dials are filled differently" "$(js "const f = $fill; return f('[data-record=radius]') !== f('[data-drive=\"--pad\"]')")" '.' "true"
check_json "and the one that answers wears the accent" "$(js "const f = $fill; return f('[data-record=radius]').includes('color(srgb') || f('[data-record=radius]').startsWith('rgba')")" '.' "true"
check_json "nothing is marked before the user touches anything" "$(js "return document.querySelectorAll('[data-answered]').length")" '.' "0"
check_json "no dot at rest" "$(js "const d = $dot; return d('[data-record=radius]')")" '.' "auto"

js "const r=document.querySelector('[data-record=radius]'); r.value=14; r.dispatchEvent(new Event('input',{bubbles:true})); const p=document.querySelector('[data-drive=\"--pad\"]'); p.value=16; p.dispatchEvent(new Event('input',{bubbles:true})); const t=document.querySelector('[data-record=label]'); t.value='Jetzt anfragen'; t.dispatchEvent(new Event('input',{bubbles:true})); return 1" >/dev/null
settle 0.4
check_json "the dial the user dragged holds the answer" "$(js "return document.querySelector('[data-record=radius]').hasAttribute('data-answered')")" '.' "true"
check_json "and says so at its readout, a 6 px dot" "$(js "const d = $dot; return d('[data-record=radius]')")" '.' "6px"
check_json "the preview-only dial moved and answers nothing" "$(js "const d = $dot; return d('[data-drive=\"--pad\"]')")" '.' "auto"
check_json "the field the user typed in is edged" "$(js "return getComputedStyle(document.querySelector('[data-record=label]')).boxShadow.includes('inset')")" '.' "true"
check_json "the page's proposal is not the user's" "$(js "return document.querySelector('[data-record=weight]').hasAttribute('data-answered')")" '.' "false"
check_json "the record agrees" "$(bridge --read "$page")" '"\(.answers.radius) \(.answers.label) \(.defaults | keys | join(","))"' "14 Jetzt anfragen weight"

bridge --quit; settle 0.5
(cd "$CASE_DIR/pages" && bridge tune-answers.html) >/dev/null; wait_ready
check_json "reopened, what is the user's is marked again" "$(js "return [...document.querySelectorAll('[data-answered]')].map(e => e.dataset.record).sort().join(',')")" '.' "label,radius"
snap answered "A dial that answers, one that previews, and the user's answers marked"
finish
