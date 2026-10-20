#!/bin/bash
source "$(dirname "$0")/../lib.sh"

export AGENT=her-agent
with_b
claude_session her-agent
claude_session "test-$CASE_NAME"

page=$(fixture decision.html)
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready
id=$(bridge --share "$page" | jq -r '.share')
there="$CASE_DIR/state-b/bridge-dev/shared/$id/page.html"
for i in $(seq 1 80); do [ -f "$there" ] && break; sleep 0.25; done

check_json "her first agent to read the page gets its answers" "$(b --read "$there")" '.heldBy' "null"
check_json "a second agent of hers is told someone holds it" "$(AGENT=other-agent b --read "$there")" '.heldBy' "her-agent"

b --do select "$there" >/dev/null
for i in $(seq 1 60); do [ "$(b --state | jq -r '.ready')" = "true" ] && break; sleep 0.25; done
b --js "$there" "document.querySelector('[data-value=list]').click(); return 1" >/dev/null
sleep 0.3
b --do send >/dev/null
check "her Send wakes the agent holding it" "$(inbox her-agent | grep -q 'Bridge: The user answered' && echo yes)" "yes"
check "with her pick" "$(b --read "$there" | jq -r '.answers.layout')" "list"
settle 1
check "and his agent sleeps on" "$(inbox "test-$CASE_NAME" 1 | grep -c 'answered')" "0"
finish
