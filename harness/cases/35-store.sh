#!/bin/bash
# Records live in the app's store, not beside the pages. A record from
# beside a page is copied in on first touch and left where it was; a fresh
# page's answers land in the store and nothing is written beside the page.
source "$(dirname "$0")/../lib.sh"
old="$CASE_DIR/pages/old.html"; fresh="$CASE_DIR/pages/fresh.html"
for p in "$old" "$fresh"; do printf '<!doctype html><title>%s</title><div data-record="name"><span>Name</span> <input type="text" value=""></div>' "$(basename "$p" .html)" > "$p"; done
printf '%s' '{"status":"sent","version":1,"questions":["name"],"answers":{"name":"Ada"},"comments":[],"history":[]}' > "$old.bridge.json"
sum=$(shasum "$old.bridge.json" | cut -d' ' -f1)
repo
(cd "$CASE_DIR/pages" && bridge old.html); wait_ready; settle 0.4
store=$(sidecar "$old")
in_store=no; case "$store" in "$XDG_STATE_HOME"/*/answers/old.html-*.bridge.json) in_store=yes;; esac
check "the record is in the store, under the state dir ($store)" "$in_store" "yes"
check_json "with the user's answer" "$(cat "$store")" '.answers.name + " " + .status' "Ada sent"
check_json "restored into the page" "$(bridge --js "$old" "return document.querySelector('input').value")" '.' "Ada"
check "beside the page the old file is renamed .migrated, its bytes intact, and nothing reads it as the record" "$([ ! -e "$old.bridge.json" ] && shasum "$old.bridge.json.migrated" | cut -d' ' -f1)" "$sum"
check_json "--read finds it" "$(bridge --read "$old")" '.answers.name' "Ada"
(cd "$CASE_DIR/pages" && bridge fresh.html); wait_ready
bridge --js "$fresh" "const i = document.querySelector('input'); i.value = 'Grace'; i.dispatchEvent(new Event('input', {bubbles: true})); return 1" >/dev/null; settle 0.5
check_json "a fresh page's answer lands in the store" "$(cat "$(sidecar "$fresh")")" '.answers.name' "Grace"
check "and nothing is written beside the page" "$(ls "$CASE_DIR/pages" | grep -c 'fresh.html.bridge.json')" "0"
finish
