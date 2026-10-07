#!/bin/bash
# A page renamed away is still removed under either spelling of /tmp, and
# removing something that is not listed says so instead of succeeding quietly.
source "$(dirname "$0")/../lib.sh"
dir=$(mktemp -d /tmp/bridge-remove.XXXXXX)
printf '<!doctype html><title>Remove</title><p>x</p>' > "$dir/page.html"
(cd "$dir" && bridge page.html); wait_ready
mv "$dir/page.html" "$dir/renamed.html"
listed() { bridge --state | jq -r --arg l "$1" '[.. | strings | select(. == $l)] | length > 0'; }
check "the page is listed under /tmp" "$(listed "$dir/page.html")" "true"
bridge --remove "/private$dir/page.html"; settle 0.3
check "removed through /private/tmp after the file is gone" "$(listed "$dir/page.html")" "false"
bridge --remove "$dir/page.html" 2>/dev/null; code=$?
check "removing it again fails" "$code" "1"
check "and says why" "$(bridge --remove "$dir/page.html" 2>&1)" "not in the list: $dir/page.html"
rm -rf "$dir"
bridge --quit >/dev/null 2>&1; sleep 0.5
check "with the app not running, it fails the same way" "$(bridge --remove "$dir/page.html" 2>&1; echo " exit $?")" "not in the list: $dir/page.html
 exit 1"
finish
