#!/bin/bash
source "$(dirname "$0")/../lib.sh"
export BRIDGE_TOOLKIT="$ROOT/toolkit"
page=$(fixture pick.jsx)
fixture pick.data.json >/dev/null
repo

out=$(cd "$CASE_DIR/pages" && bridge pick.jsx 2>&1); code=$?
check "a page that builds is presented without a word" "$code [$out]" "0 []"

sed -i '' 's/<Group>/<Group/' "$page"
line=$(grep -n '<Group$' "$page" | head -1 | cut -d: -f1)
out=$(cd "$CASE_DIR/pages" && bridge pick.jsx 2>&1 >/dev/null); code=$?
check "a page that does not build exits 1" "$code" "1"
check "and stderr carries the compiler's message with the file and line" "$(printf '%s\n' "$out" | grep -c "pick.jsx did not build: .* (pick.jsx:[0-9]*)")" "1"
check "the line it names is at or after the broken tag (line $line)" "$(printf '%s\n' "$out" | sed -n 's/.*(pick.jsx:\([0-9]*\)).*/\1/p' | head -1 | awk -v at="$line" '{ print ($1 >= at) }')" "1"
check_json "the window shows the failure" "$(bridge --state)" '.banner | startswith("Build failed")' "true"

sed -i '' 's/<Group$/<Group>/' "$page"
out=$(cd "$CASE_DIR/pages" && bridge pick.jsx 2>&1); code=$?
check "fixed, it presents quietly again" "$code [$out]" "0 []"
finish
