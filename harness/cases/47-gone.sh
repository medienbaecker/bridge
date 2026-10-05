#!/bin/bash
# A crossed bridge can point at a page whose file is gone (its session deleted
# the folder). Opening it says so plainly under the title and in the page,
# keeps the record untouched, records nothing and makes no new version.
source "$(dirname "$0")/../lib.sh"
page=$(fixture decision.html gone.html); other=$(fixture decision.html other.html)
repo
(cd "$CASE_DIR/pages" && bridge gone.html 2>/dev/null); wait_ready; settle 0.4
bridge --js "$page" "document.querySelector('[data-value=grid]').click()" >/dev/null; settle 0.5
bridge --cross "$page" >/dev/null; settle 0.3
before=$(shasum "$(sidecar "$page")" | cut -d' ' -f1)
rm "$page"
bridge --quit >/dev/null 2>&1; sleep 0.5
# Relaunched by another present, the list still carries the crossed one; select it.
(cd "$CASE_DIR/pages" && bridge other.html 2>/dev/null); wait_ready; settle 0.3
bridge --do project all >/dev/null; settle 0.2
bridge --do select "$page" >/dev/null; wait_ready; settle 0.5
state=$(bridge --state)
check_json "the page says the file is gone, under the title" "$state" '.missing and (.subtitle | startswith("This page'"'"'s file is gone: "))' "true"
check_json "and in the page, plainly" "$(bridge --js "$page" "return document.body.innerText.trim()")" '.' "This page's file is gone. What was answered is kept in the record."
check "the record is untouched" "$(shasum "$(sidecar "$page")" | cut -d' ' -f1)" "$before"
check_json "what the user answered still reads, at the same version" "$(bridge --read "$page")" '"\(.version) \(.answers.layout)"' "1 grid"
finish
