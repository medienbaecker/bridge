#!/bin/bash
source "$(dirname "$0")/../lib.sh"

mkdir -p "$CASE_DIR/other"
(cd "$CASE_DIR/other" && git init -q .)
page=$(fixture decision.html)
repo
started() { printf '{"session_id":"%s","hook_event_name":"SessionStart","cwd":"%s"}' "$1" "$2" | bridge --hook session; }
started "test-$CASE_NAME" "$CASE_DIR/pages"
started other-agent "$CASE_DIR/other"
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready

agent() { bridge --state | jq -r '[.toolbar[] | select(.id == "agent")][0].label'; }
check "the toolbar names the agent that presented the page" "$(agent)" "pages"
check_json "the menu would list both running sessions" "$(bridge --state)" '[.agents[].project] | sort | join(",")' "other,pages"

bridge --do agent other-agent >/dev/null
check "picking another session hands it the page" "$(agent)" "other"
bridge --shot "$CASE_DIR/shots/toolbar.png" >/dev/null
bridge --js "$page" "document.querySelector('[data-value=grid]').click(); return 1" >/dev/null
sleep 0.3
bridge --do send >/dev/null
hook() { printf '{"session_id":"%s"}' "$1" | bridge --hook stop --timeout 2 2>&1; }
check "the Send wakes the session picked" "$(hook other-agent | grep -q 'Bridge: The user answered' && echo yes)" "yes"
check "not the one that presented it" "$(hook "test-$CASE_NAME" | grep -c answered)" "0"

bridge --do agent none >/dev/null
check "No agent is a choice too" "$(agent)" "No agent"
bridge --js "$page" "document.querySelector('[data-value=list]').click(); return 1" >/dev/null
sleep 0.3
bridge --do send >/dev/null
check "and then a Send wakes nobody" "$(hook other-agent | grep -c answered)" "0"
check_json "while the answer is still recorded" "$(bridge --read "$page")" '.answers.layout' "list"
finish
