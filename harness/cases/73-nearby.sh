#!/bin/bash
source "$(dirname "$0")/../lib.sh"

mkdir -p "$CASE_DIR/state-b"
b() { XDG_STATE_HOME="$CASE_DIR/state-b" BRIDGE_SESSION="test-$CASE_NAME-b" bridge "$@"; }
trap 'bridge --quit >/dev/null 2>&1; b --quit >/dev/null 2>&1' EXIT
bridge --name thomas >/dev/null
b --name yoshie >/dev/null
page=$(fixture decision.html)
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready
b --peers >/dev/null

for i in $(seq 1 60); do [ "$(bridge --peers | jq -r '.nearby | join(",")')" = "yoshie" ] && break; sleep 0.25; done
check_json "another Bridge on the wifi shows up as nearby" "$(bridge --peers)" '.nearby | join(",")' "yoshie"
button() { bridge --state | jq -c '[.toolbar[] | select(.id == "share")][0] | {label, enabled, hidden}'; }
check "the toolbar offers to pair with her" "$(button)" '{"label":"Pair with yoshie","enabled":true,"hidden":false}'

bridge --do share >/dev/null
words() { "$@" --state | jq -c '.link.words'; }
for i in $(seq 1 60); do [ "$(words bridge)" != "null" ] && [ "$(words b)" != "null" ] && break; sleep 0.25; done
check "one click shows the same four words on both Macs" "$(words b)" "$(words bridge)"
check_json "her Mac asks about him without her doing anything" "$(b --state)" '.link.pairingWith' "thomas"

bridge --do pair-confirm >/dev/null
b --do pair-confirm >/dev/null
for i in $(seq 1 60); do [ "$(bridge --peers | jq -r '.connected | join(",")')" = "yoshie" ] && break; sleep 0.25; done
check_json "they are paired and connected" "$(bridge --peers)" '.connected | join(",")' "yoshie"
check_json "she is no longer listed as nearby" "$(bridge --peers)" '.nearby | length' "0"
for i in $(seq 1 20); do [ "$(button | jq -r .label)" = "Share with yoshie" ] && break; sleep 0.1; done
check "the button now shares" "$(button)" '{"label":"Share with yoshie","enabled":true,"hidden":false}'
finish
