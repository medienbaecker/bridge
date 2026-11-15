#!/bin/bash
source "$(dirname "$0")/../lib.sh"
S="$BRIDGE_SESSION"

first=$(fixture decision.html first.html)
answered=$(fixture decision.html answered.html)
for i in 1 2 3 4 5 6; do fixture decision.html "other$i.html" >/dev/null; done
repo
present() { (cd "$CASE_DIR/pages" && bridge "$@") >/dev/null 2>&1; }
loaded() { bridge --state | jq -r --arg l "$1" 'if .loadedPages | index($l) then "loaded" else "closed" end'; }
record() { jq -r "$1" "$(sidecar "$answered")"; }

present first.html; wait_ready
present answered.html
bridge --js "$answered" "document.querySelector('[data-value=grid]').click(); document.querySelector('[data-send]').click()" >/dev/null; settle
check "the second page is answered while it is loaded" "$(record .status) $(loaded "$answered")" "sent loaded"
for i in 1 2 3 4 5 6; do present "other$i.html"; done
check "six presents later its web view is closed" "$(loaded "$answered")" "closed"
check "the page on show keeps its own" "$(loaded "$first")" "loaded"

jq '.comments += [{"id":"n1","text":"Lorem ipsum","target":"h1","state":"open","at":"2026-01-01T10:00:00Z","version":1,"anchor":null,"said":[]}]' "$(sidecar "$answered")" > "$CASE_DIR/record.json" && cp "$CASE_DIR/record.json" "$(sidecar "$answered")"
check "a note on the closed page is listed" "$(bridge --pins "$answered" | jq -r '.[].id')" "n1"
bridge --done "$answered" n1
check "and marked done in its record" "$(record '.comments[0].state') $(loaded "$answered")" "done closed"

check "reading the answer collects it for the session that asked" "$(bridge --read "$answered" | jq -r '.answers.layout') $(record .collectedBy) $(loaded "$answered")" "grid $S closed"

sed -i '' 's/data-record="layout"/data-record="arrangement"/g' "$answered"
(cd "$CASE_DIR/pages" && BRIDGE_SESSION=second bridge answered.html) >/dev/null 2>&1; settle 0.5
check "presenting the closed page again hands it to the new session" "$(record .presented.session)" "second"
check "the audit loads it, so the changed questions make version 2" "$(record .version) $(loaded "$answered")" "2 loaded"
check "and version 1 is kept as it was shown" "$(grep -c 'data-record="layout"' "$XDG_STATE_HOME"/bridge-dev/versions/*/1.html)" "2"
finish
