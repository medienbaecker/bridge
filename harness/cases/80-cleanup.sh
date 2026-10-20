#!/bin/bash
source "$(dirname "$0")/../lib.sh"
export BRIDGE_ENDED_AFTER=1

alive=$(fixture decision.html alive.html)
ended=$(fixture decision.html ended.html)
repo
claude_session alive-agent
(cd "$CASE_DIR/pages" && BRIDGE_SESSION=alive-agent bridge alive.html && BRIDGE_SESSION=ended-agent bridge ended.html)
wait_ready

rows() { bridge --state | jq -c '.projects.rows'; }
check_json "Waiting counts only the page whose agent still runs" "$(bridge --state)" '[.projects.rows[] | select(.key == "waiting")][0].count' "1"
check_json "project rows show no number" "$(bridge --state)" '[.projects.rows[] | select(.key | startswith("project:")) | .countShown] | any' "false"

sleep 1.5
bridge --do cleanup >/dev/null
crossed() { bridge --state | jq -r --arg l "$1" '[.sidebar[].bridges[] | select(.location == $l)][0].crossed'; }
bridge --do crossed show >/dev/null
check "the ended agent's page crossed itself off" "$(crossed "$ended")" "true"
check "the running agent's page stays" "$(crossed "$alive")" "false"
finish
