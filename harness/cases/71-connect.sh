#!/bin/bash
source "$(dirname "$0")/../lib.sh"

mkdir -p "$CASE_DIR/state-b"
trap 'bridge --quit >/dev/null 2>&1; b --quit >/dev/null 2>&1' EXIT
bridge --name thomas >/dev/null; b --name yoshie >/dev/null
bridge --peers >/dev/null; b --peers >/dev/null
connected() { "$@" --peers | jq -r '.connected | join(",")'; }
for i in $(seq 1 120); do [ "$(connected bridge)" = "yoshie" ] && [ "$(connected b)" = "thomas" ] && break; sleep 0.25; done
check "two Bridges on the same network connect with nothing to do" "$(connected bridge) $(connected b)" "yoshie thomas"
check "each remembers the other" "$(bridge --peers | jq -r '.peers | join(",")')" "yoshie"
check "its key file is readable by its owner only" "$(stat -f %Lp "$CASE_DIR/state/bridge-dev/identity.key")" "600"

b --quit >/dev/null; sleep 0.5
for i in $(seq 1 40); do [ -z "$(connected bridge)" ] && break; sleep 0.25; done
check "when the other Mac quits, it is no longer connected" "$(connected bridge)" ""
b --peers >/dev/null
for i in $(seq 1 120); do [ "$(connected bridge)" = "yoshie" ] && break; sleep 0.25; done
check "when it comes back, they reconnect on their own" "$(connected bridge)" "yoshie"

b --quit >/dev/null; sleep 0.5
rm "$CASE_DIR/state-b/bridge-dev/identity.key"
b --peers >/dev/null
for i in $(seq 1 60); do [ "$(bridge --peers | jq -r '.refused | join(",")')" = "yoshie" ] && break; sleep 0.25; done
check "a Mac that comes back under a known id with another key is refused" "$(bridge --peers | jq -r '.refused | join(",")')" "yoshie"
check "and not connected" "$(connected bridge)" ""
finish
