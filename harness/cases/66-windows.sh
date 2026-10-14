#!/bin/bash
# A bridge opens in a window of its own and comes back when that window closes:
# the web view lives in one place at a time, so the main window shows a
# placeholder while it is away and the page again afterwards. Closing the torn-off
# window is not an answer. Dragged out of the list, the window opens at the drop.
source "$(dirname "$0")/../lib.sh"
for i in 1 2; do printf '<!doctype html><title>Page %s</title><p>Page %s</p>' $i $i > "$CASE_DIR/pages/p$i.html"; done
p1="$CASE_DIR/pages/p1.html"; p2="$CASE_DIR/pages/p2.html"
(cd "$CASE_DIR/pages" && bridge p1.html p2.html); wait_ready; settle 0.3
bridge --do select "$p1" >/dev/null; settle 0.2
check_json "before: the main window shows the page" "$(bridge --state)" '.contentShowsPage' "true"

bridge --do window >/dev/null; settle 0.4
s=$(bridge --state)
check_json "the bridge has a window of its own" "$s" '[.pageWindows[] | select(.location | endswith("/p1.html"))] | length' "1"
check_json "that window shows the page, titled after it" "$s" '.pageWindows[0] | .showsPage and .visible and .title == "Page 1"' "true"
check_json "the main window shows the placeholder instead" "$s" '.contentShowsPage' "false"
check_json "Send in the main window is off while the page is away" "$s" '[.toolbar[] | select(.id == "send")][0].enabled' "false"

bridge --do window >/dev/null; settle 0.2
check_json "opening it again does not make a second window" "$(bridge --state)" '.pageWindows | length' "1"

bridge --do select "$p2" >/dev/null; settle 0.2
check_json "another bridge selected shows in the main window" "$(bridge --state)" '.contentShowsPage' "true"

bridge --do closewindow "$p1" >/dev/null; settle 0.3
check_json "closed, the window is gone" "$(bridge --state)" '.pageWindows | length' "0"
check "closing the window is not an answer" "$(bridge --read "$p1" | jq -r '.status')" "open"
bridge --do select "$p1" >/dev/null; settle 0.2
check_json "the page is back in the main window" "$(bridge --state)" '.contentShowsPage' "true"

bridge --do dragout "$p2 400 700" >/dev/null; settle 0.4
check_json "dragged out, it opens with its top left near the drop" "$(bridge --state)" \
  '.pageWindows[0].topLeft | (.[0] - 400 | fabs) < 2 and (.[1] - 700 | fabs) < 2' "true"
finish
