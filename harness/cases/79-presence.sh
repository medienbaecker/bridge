#!/bin/bash
source "$(dirname "$0")/../lib.sh"

pair_with_b
page=$(fixture decision.html)
other=$(fixture decision.html other.html)
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready
id=$(bridge --share "$page" | jq -r '.share')
there="$CASE_DIR/state-b/bridge-dev/shared/$id/page.html"
for i in $(seq 1 80); do [ -f "$there" ] && break; sleep 0.25; done
b --do select "$there" >/dev/null
for i in $(seq 1 60); do [ "$(b --state | jq -r '.ready')" = "true" ] && break; sleep 0.25; done

until_is() { for i in $(seq 1 120); do [ "$(eval "$1")" = "$2" ] && return; sleep 0.1; done; }
chip() { bridge --js "$page" "@bridge const c = document.querySelector('.bridge-here-person'); return c ? c.textContent : 'none'" | jq -r .; }

until_is chip "yoshieno agent"
check "her chip shows on his page: here, no agent yet" "$(chip)" "yoshieno agent"

mkdir -p "$CASE_DIR/her-project" && (cd "$CASE_DIR/her-project" && git init -q .)
printf '{"session_id":"her-agent","hook_event_name":"SessionStart","cwd":"%s"}' "$CASE_DIR/her-project" | b --hook session
b --do agent her-agent >/dev/null
until_is chip "yoshieagent idle in her-project"
check "handed to an agent, it says which and what it is doing" "$(chip)" "yoshieagent idle in her-project"
snap here "Her chip in the corner of his page"

sed -i '' 's|<h1>Card layout for the archive</h1>|<h1>Her take</h1>|' "$there"
until_is "bridge --js '$page' \"@bridge return document.querySelector('.bridge-toast')?.textContent || ''\" | jq -r ." "yoshie's agent rewrote the page"
check "her agent's rewrite is announced on his page" "$(bridge --js "$page" "@bridge return document.querySelector('.bridge-toast')?.textContent || ''" | jq -r .)" "yoshie's agent rewrote the page"

b "$other" >/dev/null
until_is "chip | grep -c elsewhere" 1
check "when she looks at something else, her chip says so" "$(chip | grep -o 'elsewhere')" "elsewhere"

b --quit >/dev/null
until_is chip none
check "when her Mac goes away, so does her chip" "$(chip)" "none"
finish
