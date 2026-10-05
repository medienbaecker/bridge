#!/bin/bash
# Starting the app: a long state directory is fine, and a refusal to start
# reaches the CLI with the real reason instead of a silent exit.
source "$(dirname "$0")/../lib.sh"
page=$(fixture decision.html)
repo

long="$CASE_DIR/$(printf 'a-very-long-state-directory-name-%.0s' 1 2 3 4)"
mkdir -p "$long"
( export XDG_STATE_HOME="$long"; (cd "$CASE_DIR/pages" && bridge decision.html) && wait_ready && check_json "a $(printf '%s' "$long" | wc -c | tr -d ' ')-character state dir still gets a socket" "$(bridge --state)" '.running' "true"; check "socket lives under the temp dir" "$(ls "$long/bridge-dev" | grep -c sock)" "0"; bridge --quit; sleep 0.3 )

start=$(date +%s)
err=$( export BRIDGE_SOCKET="/tmp/$(printf 'x%.0s' $(seq 1 120)).sock"; cd "$CASE_DIR/pages" && bridge decision.html 2>&1 >/dev/null; echo " exit=$?" )
check "a refused start reports the reason" "$(printf '%s' "$err" | grep -c 'the limit is 104')" "1"
check "and exits non-zero" "$(printf '%s' "$err" | grep -o 'exit=[0-9]*')" "exit=1"
check "without waiting five seconds" "$(( $(date +%s) - start < 3 ))" "1"

# A second instance on the same socket says so
(cd "$CASE_DIR/pages" && bridge decision.html); wait_ready
out=$("$BRIDGE_DEV_APP/Contents/MacOS/BridgeDev" 2>&1; echo " exit=$?")
check "a second instance on a live socket refuses with a reason" "$(printf '%s' "$out" | grep -c 'already answering')" "1"
check "and exits non-zero" "$(printf '%s' "$out" | grep -o 'exit=[0-9]*')" "exit=1"
# Flavours: the CLI switches on its basename; the bundle wears an icon
tmp="$CASE_DIR/flavour"; mkdir -p "$tmp"; cp "$ROOT/build.noindex/bridge-dev" "$tmp/bridge-beta"
( export XDG_STATE_HOME="$CASE_DIR/flavour-state"; unset BRIDGE_NAME; "$tmp/bridge-beta" --state >/dev/null; check "a CLI named bridge-beta uses the bridge-beta state dir" "$(ls "$CASE_DIR/flavour-state")" "bridge-beta" )
check "the bundle has a compiled icon" "$(test -s "$ROOT/build.noindex/Bridge Dev.app/Contents/Resources/Assets.car" && echo yes)" "yes"
check "and Info.plist names it" "$(grep -c 'CFBundleIconName' "$ROOT/build.noindex/Bridge Dev.app/Contents/Info.plist")" "1"
check "the bundle is signed with a real identity when one exists" "$(codesign -dv "$ROOT/build.noindex/Bridge Dev.app" 2>&1 | grep -c '^TeamIdentifier=[A-Z0-9]')" "1"
finish
