#!/bin/bash
# A dial the user was only playing with must not be sent unnoticed. At rest a
# dial that answers wears the accent and one that only drives a preview is grey;
# once a control holds the user's answer it
# is marked at the control, a dot at a dial's readout or at a field's label.
# A reopen marks what is the user's.
source "$(dirname "$0")/../lib.sh"
page=$(fixture tune-answers.html)
repo
(cd "$CASE_DIR/pages" && bridge tune-answers.html) >/dev/null; wait_ready
js() { bridge --js "$page" "$1"; }
fill='(s) => getComputedStyle(document.querySelector(s).closest(".dial"), "::before").backgroundColor'
dot='(s) => getComputedStyle(document.querySelector(s).closest(".dial").querySelector("output"), "::before").width'
check_json "at rest the two dials are filled differently, the one that answers in the accent" "$(js "const f = $fill; const a = f('[data-record=radius]'); return a !== f('[data-drive=\"--pad\"]') && (a.includes('color(srgb') || a.startsWith('rgba'))")" '.' "true"
check_json "nothing is marked before the user touches anything, no dot" "$(js "const d = $dot; return document.querySelectorAll('[data-answered]').length + ' ' + d('[data-record=radius]')")" '.' "0 auto"

js "const r=document.querySelector('[data-record=radius]'); r.value=14; r.dispatchEvent(new Event('input',{bubbles:true})); const p=document.querySelector('[data-drive=\"--pad\"]'); p.value=16; p.dispatchEvent(new Event('input',{bubbles:true})); const t=document.querySelector('[data-record=label]'); t.value='Jetzt anfragen'; t.dispatchEvent(new Event('input',{bubbles:true})); return 1" >/dev/null
settle 0.4
check_json "the dial the user dragged holds the answer and says so with a dot at its readout" "$(js "const d = $dot; return document.querySelector('[data-record=radius]').hasAttribute('data-answered') && d('[data-record=radius]') !== 'auto'")" '.' "true"
check_json "the preview-only dial moved and answers nothing" "$(js "const d = $dot; return d('[data-drive=\"--pad\"]')")" '.' "auto"
check_json "the field the user typed in has a dot at its label" "$(js "return getComputedStyle(document.querySelector('[data-record=label]').labels[0].querySelector('.bridge-answered-dot')).width")" '.' "6px"

bridge --quit; settle 0.5
(cd "$CASE_DIR/pages" && bridge tune-answers.html) >/dev/null; wait_ready
check_json "reopened, what is the user's is marked again" "$(js "return [...document.querySelectorAll('[data-answered]')].map(e => e.dataset.record).sort().join(',')")" '.' "label,radius"
snap answered "A dial that answers, one that previews, and the user's answers marked"
finish
