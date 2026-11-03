#!/bin/bash
source "$(dirname "$0")/../lib.sh"
dir=$(mktemp -d /tmp/bridge-reset-shown.XXXXXX)
printf '<!doctype html><title>First</title><p>first</p>' > "$dir/first.html"
printf '<!doctype html><title>Second</title><p>second</p>' > "$dir/second.html"
(cd "$dir" && bridge first.html); wait_ready
bridge --reset "$dir/first.html" >/dev/null; settle 0.3
(cd "$dir" && bridge second.html); wait_ready
check "one web view in the window" "$(bridge --state | jq '.webViews')" "1"
rm -rf "$dir"
finish
