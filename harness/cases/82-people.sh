#!/bin/bash
source "$(dirname "$0")/../lib.sh"

with_b
page=$(fixture decision.html)
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready

people() { bridge --state | jq -c '[.projects.people[] | .key + (if .connected == null then "" else (if .connected then " ●" else " ○" end) end)]'; }
check "the sidebar names you and her, with whether she is connected" "$(people)" '["me","person:yoshie ●"]'
snap people "People in the sidebar"

bridge --do dropon "$page|person:yoshie" >/dev/null
there=""
for i in $(seq 1 80); do there=$(ls "$CASE_DIR"/state-b/bridge-dev/shared/*/page.html 2>/dev/null | head -1); [ -n "$there" ] && break; sleep 0.25; done
check "dropping a page on her shares it" "$([ -n "$there" ] && echo yes)" "yes"
for i in $(seq 1 40); do b --state | jq -e '[.projects.rows[] | select(.name == "Shared with you")] | length > 0' >/dev/null && break; sleep 0.25; done
check "on her Mac it sits under him as Shared with you" "$(b --state | jq -r '[.projects.rows[] | select(.name == "Shared with you")][0].name')" "Shared with you"
finish
