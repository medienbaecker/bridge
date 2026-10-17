#!/bin/bash
source "$(dirname "$0")/../lib.sh"

mkdir -p "$CASE_DIR/her-project" "$CASE_DIR/transcripts/-her"
(cd "$CASE_DIR/her-project" && git init -q .)
export BRIDGE_TRANSCRIPTS="$CASE_DIR/transcripts"
printf '%s\n' "{\"type\":\"user\",\"cwd\":\"$CASE_DIR/her-project\",\"message\":{\"role\":\"user\",\"content\":\"Plan the footer\"}}" > "$CASE_DIR/transcripts/-her/her-agent.jsonl"
with_b
printf '{"session_id":"her-agent","hook_event_name":"SessionStart","cwd":"%s"}' "$CASE_DIR/her-project" | b --hook session

page=$(fixture decision.html)
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready

printf '{"session_id":"her-private","hook_event_name":"SessionStart","cwd":"%s"}' "$CASE_DIR/her-project" | b --hook session
people() { bridge --state | jq -c '[.projects.people[] | .key + (if .connected == null then "" else (if .connected then " ●" else " ○" end) end) + (if .detail then " " + .name + " / " + .detail else "" end)]'; }
sleep 4
check "her agents stay private until one holds a shared page" "$(people)" '["me","person:yoshie ●"]'

bridge --do dropon "$page|person:yoshie" >/dev/null
there=""
for i in $(seq 1 80); do there=$(ls "$CASE_DIR"/state-b/bridge-dev/shared/*/page.html 2>/dev/null | head -1); [ -n "$there" ] && break; sleep 0.25; done
check "dropping a page on her shares it" "$([ -n "$there" ] && echo yes)" "yes"
b --do drop "$there|her-agent" >/dev/null
for i in $(seq 1 60); do people | grep -q 'remote:yoshie:her-agent' && break; sleep 0.25; done
check "once she hands it to an agent, that agent shows under her, and only that one" "$(people)" '["me","person:yoshie ●","remote:yoshie:her-agent Plan the footer / her-project · idle"]'
snap people "Her agent shows once it holds a shared page"

other=$(fixture decision.html second.html)
(cd "$CASE_DIR/pages" && bridge second.html)
wait_ready
bridge --do dropon "$other|remote:yoshie:her-agent" >/dev/null
for i in $(seq 1 80); do [ "$(ls "$CASE_DIR"/state-b/bridge-dev/shared/*/page.html | wc -l | tr -d ' ')" = "2" ] && break; sleep 0.25; done
second=$(ls -t "$CASE_DIR"/state-b/bridge-dev/shared/*/page.html | head -1)
for i in $(seq 1 40); do [ "$(AGENT=someone-else b --read "$second" | jq -r '.heldBy')" = "her-agent" ] && break; sleep 0.25; done
check "dropping another page on her agent shares it and hands it to that agent" "$(AGENT=someone-else b --read "$second" | jq -r '.heldBy')" "her-agent"
finish
