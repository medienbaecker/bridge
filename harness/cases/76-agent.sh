#!/bin/bash
source "$(dirname "$0")/../lib.sh"

mkdir -p "$CASE_DIR/other" "$CASE_DIR/transcripts/-other"
export BRIDGE_TRANSCRIPTS="$CASE_DIR/transcripts"
printf '%s\n' '{"type":"mode"}' "{\"type\":\"user\",\"cwd\":\"$CASE_DIR/other\",\"message\":{\"role\":\"user\",\"content\":\"<command-name>/clear</command-name>\"}}" "{\"type\":\"user\",\"cwd\":\"$CASE_DIR/other\",\"message\":{\"role\":\"user\",\"content\":\"Fix the footer colour on mobile\\nand more\"}}" > "$CASE_DIR/transcripts/-other/other-agent.jsonl"
(cd "$CASE_DIR/other" && git init -q .)
page=$(fixture decision.html)
repo
started() { printf '{"session_id":"%s","hook_event_name":"SessionStart","cwd":"%s"}' "$1" "$2" | bridge --hook session; }
started "test-$CASE_NAME" "$CASE_DIR/pages"
started other-agent "$CASE_DIR/other"
printf '{"session_id":"older-agent","hook_event_name":"SessionStart"}' | bridge --hook session
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready

agent() { bridge --state | jq -r '[.toolbar[] | select(.id == "agent")][0].label'; }
check "the toolbar names the agent that presented the page" "$(agent)" "pages"
check_json "the menu lists every running session, one without a folder by its id" "$(bridge --state)" '[.agents[].project] | sort | join(",")' "other,pages,session olde"

bridge --do agent other-agent >/dev/null
check "picking another session hands it the page" "$(agent)" "other"
menu=$(bridge --state | jq -c '[.agentMenu[] | "\(if .on then "✓ " else "" end)\(.title)"]')
check "the menu marks the session the Send wakes and names sessions by what they were asked" "$(echo "$menu" | jq -r '.[] | select(startswith("✓"))')" "✓ other · “Fix the footer colour on mobile”"
check "and ends with No agent, saying what that means" "$(bridge --state | jq -r '.agentMenu[-1] | "\(.title): \(.detail)"')" "No agent: Send only saves your answer"
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
