#!/bin/bash
# The middle column's header names the list (Waiting, All, or the project),
# and the document's title, with no icon, stands over the page column where
# the document is. The window's own title would have sat over the list.
source "$(dirname "$0")/../lib.sh"
mkdir -p "$CASE_DIR/pages/sample"
cp "$ROOT/harness/fixtures/editor-map.html" "$CASE_DIR/pages/sample/"
repo; (cd "$CASE_DIR/pages/sample" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm f)
(cd "$CASE_DIR/pages/sample" && bridge editor-map.html 2>/dev/null); wait_ready; settle 0.5
check_json "with nothing waiting at launch the column is All, and the header says so" "$(bridge --state)" '.listHeader' "All"
bridge --do project "project:$(cd "$CASE_DIR/pages/sample" && pwd -P)" >/dev/null; settle 0.4
state=$(bridge --state)
check_json "in a project the header is the project's name" "$state" '.listHeader' "sample"
check_json "the document over the page is the page's title alone, no icon before it" "$state" '.documentTitle' "Demo: script"
check_json "the header sits over the list column and the document over the page column" "$state" '(.listHeaderX > .columnWidths[0]) and (.listHeaderX < .columnWidths[0] + .columnWidths[1]) and (.documentTitleX >= .pageX)' "true"
printf '<!doctype html><title>Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore</title><p>Lorem ipsum</p>' > "$CASE_DIR/pages/sample/long.html"
(cd "$CASE_DIR/pages/sample" && bridge long.html 2>/dev/null); wait_ready; settle 0.5
check_json "a title too long for the toolbar is cut, and still starts over the page column" "$(bridge --state)" '.documentTitleX >= .pageX' "true"
bridge --do project waiting >/dev/null; settle 0.3
check_json "in Waiting the header says so" "$(bridge --state)" '.listHeader' "Waiting"
finish
