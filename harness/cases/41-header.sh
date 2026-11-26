#!/bin/bash
# The document's title, with no icon, stands over the page column where the
# document is. The window's own title would have sat over the list.
source "$(dirname "$0")/../lib.sh"
mkdir -p "$CASE_DIR/pages/sample"
cp "$ROOT/harness/fixtures/editor-map.html" "$CASE_DIR/pages/sample/"
repo; (cd "$CASE_DIR/pages/sample" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm f)
(cd "$CASE_DIR/pages/sample" && bridge editor-map.html 2>/dev/null); wait_ready; settle 0.5
bridge --do project "project:$(cd "$CASE_DIR/pages/sample" && pwd -P)" >/dev/null; settle 0.4
state=$(bridge --state)
check_json "the document over the page is the page's title alone, no icon before it" "$state" '.documentTitle' "Demo: script"
check_json "the document's title sits over the page column" "$state" '.documentTitleX >= .pageX' "true"
printf '<!doctype html><title>Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore</title><p>Lorem ipsum</p>' > "$CASE_DIR/pages/sample/long.html"
(cd "$CASE_DIR/pages/sample" && bridge long.html 2>/dev/null); wait_ready; settle 0.5
check_json "a title too long for the toolbar is cut, and still starts over the page column" "$(bridge --state)" '.documentTitleX >= .pageX' "true"
finish
