#!/bin/bash
# A crossed bridge can point at a page whose file is gone (its session deleted
# the folder). Opening it says so plainly under the title, keeps the record
# untouched, records nothing and makes no new version. A page renamed while it
# is open says the same instead of the content it last had, and comes back when
# the file does.
source "$(dirname "$0")/../lib.sh"
p="$CASE_DIR/pages"
page=$(fixture decision.html gone.html); other=$(fixture decision.html other.html)
repo
(cd "$p" && bridge gone.html 2>/dev/null); wait_ready; settle 0.4
bridge --js "$page" "document.querySelector('[data-value=grid]').click()" >/dev/null; settle 0.5
bridge --cross "$page" >/dev/null; settle 0.3
before=$(shasum "$(sidecar "$page")" | cut -d' ' -f1)
rm "$page"
bridge --quit >/dev/null 2>&1; sleep 0.5
# Relaunched by another present, the list still carries the crossed one; select it.
(cd "$p" && bridge other.html 2>/dev/null); wait_ready; settle 0.3
bridge --do project all >/dev/null; settle 0.2
bridge --do select "$page" >/dev/null; wait_ready; settle 0.5
check_json "the page says the file is gone, under the title" "$(bridge --state)" '.missing and (.subtitle | startswith("This page'"'"'s file is gone: "))' "true"
check "the record is untouched: what the user answered still reads, at the same version" "$(shasum "$(sidecar "$page")" | cut -d' ' -f1) $(bridge --read "$page" | jq -r '"\(.version) \(.answers.layout)"')" "$before 1 grid"

printf '<!doctype html><title>Plan</title><p>first content</p>' > "$p/a.html"
printf '# Notes\n\nmarkdown content\n' > "$p/n.md"
(cd "$p" && bridge n.md a.html); wait_ready; settle 0.5
mv "$p/a.html" "$p/b.html"; mv "$p/n.md" "$p/m.md"; settle 1
check_json "a page renamed while open says its file is gone instead of the content it last had" "$(bridge --js "$p/a.html" "return document.body.innerText.trim()")" '.' "This page's file is gone. What was answered is kept in the record."
check_json "so does a markdown page" "$(bridge --js "$p/n.md" "return document.body.innerText.trim()")" '.' "This page's file is gone. What was answered is kept in the record."
(cd "$p" && bridge b.html); wait_ready; settle 0.5
check_json "the new name is its own page" "$(bridge --js "$p/b.html" "return document.body.innerText.trim()")" '.' "first content"
mv "$p/b.html" "$p/a.html"; settle 1
bridge --do select "$p/a.html" >/dev/null; wait_ready; settle 0.5
check "moved back, the old page shows its file again and no longer says it is gone" "$(bridge --js "$p/a.html" "return document.body.innerText.trim()" | jq -r .) $(bridge --state | jq -r .missing)" "first content false"
finish
