#!/bin/bash
# A page renamed while it is open says its file is gone instead of showing the
# content it last had, and comes back when the file does.
source "$(dirname "$0")/../lib.sh"
p="$CASE_DIR/pages"
printf '<!doctype html><title>Plan</title><p>first content</p>' > "$p/a.html"
printf '# Notes\n\nmarkdown content\n' > "$p/n.md"
repo
(cd "$p" && bridge n.md a.html); wait_ready; settle 0.5
mv "$p/a.html" "$p/b.html"; mv "$p/n.md" "$p/m.md"; settle 1
check_json "the open page says its file is gone" "$(bridge --state)" '"\(.missing) \(.subtitle | startswith("This page'"'"'s file is gone"))"' "true true"
check_json "instead of the content it last had" "$(bridge --js "$p/a.html" "return document.body.innerText.trim()")" '.' "This page's file is gone. What was answered is kept in the record."
check_json "so does a markdown page" "$(bridge --js "$p/n.md" "return document.body.innerText.trim()")" '.' "This page's file is gone. What was answered is kept in the record."
(cd "$p" && bridge b.html); wait_ready; settle 0.5
check_json "the new name is its own page" "$(bridge --js "$p/b.html" "return document.body.innerText.trim()")" '.' "first content"
mv "$p/b.html" "$p/a.html"; settle 1
bridge --do select "$p/a.html" >/dev/null; wait_ready; settle 0.5
check_json "moved back, the old page shows its file again" "$(bridge --js "$p/a.html" "return document.body.innerText.trim()")" '.' "first content"
check_json "and no longer says it is gone" "$(bridge --state)" '.missing' "false"
finish
