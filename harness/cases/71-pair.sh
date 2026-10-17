#!/bin/bash
source "$(dirname "$0")/../lib.sh"

mkdir -p "$CASE_DIR/state-b"
b() { XDG_STATE_HOME="$CASE_DIR/state-b" BRIDGE_SESSION="test-$CASE_NAME-b" bridge "$@"; }
trap 'bridge --quit >/dev/null 2>&1; b --quit >/dev/null 2>&1' EXIT
bridge --name thomas >/dev/null
b --name yoshie >/dev/null

check_json "a Mac starts with no peers" "$(bridge --peers)" '.peers | length' "0"
bridge --pair >/dev/null
b --pair >/dev/null

words() { "$@" --state | jq -c '.link.words'; }
for i in $(seq 1 160); do [ "$(words bridge)" != "null" ] && [ "$(words b)" != "null" ] && break; sleep 0.25; done
check "both Macs show four words" "$(words bridge | jq 'length')" "4"
check "and they are the same words" "$(words b)" "$(words bridge)"
check_json "each knows who it is pairing with" "$(bridge --state)" '.link.pairingWith' "yoshie"
check_json "from both sides" "$(b --state)" '.link.pairingWith' "thomas"

bridge --do pair-confirm >/dev/null
b --do pair-confirm >/dev/null
for i in $(seq 1 60); do [ "$(bridge --peers | jq -r '.connected[0] // empty')" = "yoshie" ] && break; sleep 0.25; done
check_json "after both confirm, each lists the other" "$(bridge --peers)" '.peers | join(",")' 'yoshie'
check_json "the other way round too" "$(b --peers)" '.peers | join(",")' 'thomas'
check_json "and they are connected" "$(bridge --peers)" '.connected | join(",")' 'yoshie'
check "the shared secret is readable by its owner only" "$(stat -f %Lp "$CASE_DIR/state/bridge-dev/peers.json")" "600"
check_json "pairing mode has ended" "$(bridge --peers)" '.pairing' "false"

b --quit >/dev/null; sleep 0.5
check_json "when the other Mac quits, it is no longer connected" "$(bridge --peers)" '.connected | length' '0'
b --peers >/dev/null
for i in $(seq 1 60); do [ "$(bridge --peers | jq -r '.connected[0] // empty')" = "yoshie" ] && break; sleep 0.25; done
check_json "when it comes back, they reconnect on their own" "$(bridge --peers)" '.connected | join(",")' 'yoshie'
finish
