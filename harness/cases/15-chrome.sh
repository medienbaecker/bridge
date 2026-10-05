#!/bin/bash
source "$(dirname "$0")/../lib.sh"
page=$(fixture decision.html)
repo
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready
check_json "zoom starts at 1" "$(bridge --state)" '.zoom' "1"
before=$(bridge --js "$page" "return innerWidth")
check_json "zoom in" "$(bridge --do zoom-in)" '.zoom' "1.1"
check_json "zoom is applied to the page" "$(bridge --js "$page" "return innerWidth < $before")" '.' "true"
check_json "actual size" "$(bridge --do zoom-reset)" '.zoom' "1"
bridge --js "$page" "document.querySelector('[data-value=grid]').click(); const r = document.querySelector('[data-record=radius]'); r.value = 12; r.dispatchEvent(new Event('change', {bubbles: true}))" >/dev/null
state=$(bridge --do send)
check_json "after Send the strip says nothing; the toolbar carries sent" "$state" '.banner' "null"
snap sent "The sent line: when, and what"
finish
