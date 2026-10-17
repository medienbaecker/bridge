#!/bin/bash
source "$(dirname "$0")/../lib.sh"

mkdir -p "$CASE_DIR/other" "$CASE_DIR/transcripts/-other"
(cd "$CASE_DIR/other" && git init -q .)
export BRIDGE_TRANSCRIPTS="$CASE_DIR/transcripts"
printf '%s\n' '{"type":"mode"}' "{\"type\":\"user\",\"cwd\":\"$CASE_DIR/other\",\"message\":{\"role\":\"user\",\"content\":\"<command-name>/clear</command-name>\"}}" "{\"type\":\"user\",\"cwd\":\"$CASE_DIR/other\",\"message\":{\"role\":\"user\",\"content\":\"Fix the footer colour on mobile\\nand more\"}}" > "$CASE_DIR/transcripts/-other/other-agent.jsonl"
page=$(fixture decision.html)
repo
started() { printf '{"session_id":"%s","hook_event_name":"SessionStart","cwd":"%s"}' "$1" "$2" | bridge --hook session; }
started "test-$CASE_NAME" "$CASE_DIR/pages"
started other-agent "$CASE_DIR/other"
printf '{"session_id":"older-agent","hook_event_name":"SessionStart"}' | bridge --hook session
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready

agents() { bridge --state | jq -c '[.projects.rows[] | select(.key | startswith("agent:")) | "\(.name) \(.count)"]'; }
check "the sidebar lists every running agent by what it was asked, with its pages" "$(agents)" '["Fix the footer colour on… 0","pages 1","session olde 0"]'
check "and under that its folder and state" "$(bridge --state | jq -r '[.projects.people[] | select(.key == "agent:other-agent")][0].detail')" "other · idle"
snap agents "Agents in the sidebar"

bridge --do project "agent:test-$CASE_NAME" >/dev/null
check_json "selecting an agent lists its pages" "$(bridge --state)" '[.sidebar[].bridges[].title] | join(",")' "Card layout for the archive"

bridge --do drop "$page|other-agent" >/dev/null
check "dropping the page on another agent moves it there" "$(agents)" '["Fix the footer colour on… 1","pages 0","session olde 0"]'
bridge --do project all >/dev/null
bridge --do select "$page" >/dev/null
bridge --js "$page" "document.querySelector('[data-value=grid]').click(); return 1" >/dev/null
sleep 0.3
bridge --do send >/dev/null
hook() { printf '{"session_id":"%s"}' "$1" | bridge --hook stop --timeout 2 2>&1; }
check "the Send wakes the agent it was dropped on" "$(hook other-agent | grep -q 'Bridge: The user answered' && echo yes)" "yes"
check "not the one that presented it" "$(hook "test-$CASE_NAME" | grep -c answered)" "0"
finish
