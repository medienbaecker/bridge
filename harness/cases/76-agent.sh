#!/bin/bash
# The toolbar's agent menu names the session a Send wakes, by Claude Code's own
# name, and hands the page to another live session or to none.
source "$(dirname "$0")/../lib.sh"

page=$(fixture decision.html)
repo
claude_session "$BRIDGE_SESSION"
claude_session other-agent
(cd "$CASE_DIR/pages" && bridge decision.html); wait_ready
settle 2.5
agent() { bridge --state | jq -r '[.toolbar[] | select(.id == "agent")][0] | "\(.label) \(.enabled)"'; }

check "the toolbar names the presenting session" "$(agent)" "$BRIDGE_SESSION true"
bridge --do agent other-agent >/dev/null; settle 0.3
check "handed over, it names the other one" "$(agent)" "other-agent true"
bridge --js "$page" "document.querySelector('[data-value=grid]').click(); document.querySelector('[data-send]').click()" >/dev/null
check "the Send wakes the session it was handed to" "$(inbox other-agent | grep -c "answered $page")" "1"
check "not the one that presented it" "$(inbox "$BRIDGE_SESSION" 5 | grep -c 'Bridge:')" "0"

bridge --do agent "$BRIDGE_SESSION" >/dev/null
check "an answered page handed back is delivered to its new holder at once" "$(inbox "$BRIDGE_SESSION" | grep -c "answered $page")" "1"

bridge --do agent none >/dev/null; settle 0.3
check "no agent" "$(agent)" "No agent true"
end_session other-agent
bridge --do agent other-agent >/dev/null; settle 0.3
check "a session that has gone says so" "$(agent)" "Session ended true"
finish
