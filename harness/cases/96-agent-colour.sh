#!/bin/bash
source "$(dirname "$0")/../lib.sh"
repo
printf '<!doctype html><title>Lorem</title><p>x</p>' > "$CASE_DIR/pages/a.html"
printf '<!doctype html><title>Ipsum</title><p>x</p>' > "$CASE_DIR/pages/b.html"
printf '<!doctype html><title>Dolor</title><p>x</p>' > "$CASE_DIR/pages/c.html"
for s in pills ogimage; do (cd "$CASE_DIR/pages" && claude_session "$s" idle); done
(cd "$CASE_DIR/pages" && BRIDGE_SESSION=pills bridge a.html); settle 0.3
(cd "$CASE_DIR/pages" && BRIDGE_SESSION=ogimage bridge b.html); settle 0.3
(cd "$CASE_DIR/pages" && BRIDGE_SESSION=pills bridge c.html); wait_ready; settle 0.5
bridge --do select "$CASE_DIR/pages/c.html" >/dev/null; settle 0.3
check_json "an unread bridge's dot takes its agent's colour, each agent its own" "$(bridge --state)" '[.sidebarGeometry.rows[] | select(.unread) | {(.title): .dot}] | add | [(.Lorem != .Ipsum), (.Lorem | startswith("rgb"))] | map(tostring) | join(",")' "true,true"
mkdir -p "$CASE_DIR/done" && git -C "$CASE_DIR/done" init -q
printf '<!doctype html><title>Done</title><p>x</p>' > "$CASE_DIR/done/d.html"
(cd "$CASE_DIR/done" && bridge d.html); wait_ready; settle 0.3
bridge --cross "$CASE_DIR/done/d.html"; settle 0.3
check_json "a project with nothing open is listed with the others, no more-projects row" "$(bridge --state)" '[.projects.rows[].key] | [(map(select(endswith("/done"))) | length), (map(select(. == "more")) | length)] | map(tostring) | join(",")' "1,0"
finish
