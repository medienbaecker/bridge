#!/bin/bash
source "$(dirname "$0")/../lib.sh"
printf '<!doctype html><title>Lorem ipsum</title><p>Lorem ipsum dolor sit amet.</p>' > "$CASE_DIR/pages/page.html"
repo
(cd "$CASE_DIR/pages" && bridge page.html); wait_ready; settle 0.3
bridge --do settings >/dev/null; settle 0.4
s=$(bridge --state)
check_json "Settings opens on the main window's screen" "$s" '.settings | [.visible, .screen] | map(tostring) | join(",")' "true,$BRIDGE_SCREEN"
check_json "with nothing wrong it says nothing" "$s" '.settings | [.loginError, .notificationsDenied] | map(tostring) | join(",")' ",false"
shot quiet >/dev/null
bridge --do settings-login >/dev/null; settle 0.4
check_json "Open at Login that cannot be registered says so in the window" "$(bridge --state)" '.settings.loginError | startswith("Open at Login could not be changed: ")' "true"
shot login >/dev/null

bridge --quit >/dev/null 2>&1; sleep 0.5
export BRIDGE_NOTIFICATIONS=denied BRIDGE_APPEARANCE=dark
(cd "$CASE_DIR/pages" && bridge page.html); wait_ready; settle 0.3
bridge --do settings >/dev/null; settle 0.4
check_json "notifications denied in System Settings show a hint under the checkboxes" "$(bridge --state)" '.settings.notificationsDenied' "true"
bridge --do settings-login >/dev/null; settle 0.4
shot denied >/dev/null
finish
