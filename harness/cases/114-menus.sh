#!/bin/bash
source "$(dirname "$0")/../lib.sh"
printf '<!doctype html><title>Lorem ipsum</title><p>Lorem ipsum</p>' > "$CASE_DIR/pages/page.html"
page="$CASE_DIR/pages/page.html"
repo
(cd "$CASE_DIR/pages" && bridge page.html); wait_ready; settle 0.3
item() { jq -c "[.menu[] | select(.command == \"$1\" or .title == \"$1\")][0]" <<< "$s"; }

s=$(bridge --state)
check_json "the first item is New Bridge" "$(item new)" '.title' "New Bridge"
check_json "and so is the toolbar's" "$s" '[.toolbar[] | select(.id == "new")][0].label' "New Bridge"
check_json "with crossed ones shown the item offers to hide them" "$(item crossed)" '.title' "Hide Crossed"
check_json "the standard items are there" "$s" '[.menu[].title] as $t | ["About Bridge", "Hide Others", "Show All", "Enter Full Screen", "Zoom", "Bring All to Front"] | map(select(. as $want | $t | index($want) == null)) | join(",")' ""
check_json "the View menu toggles the sidebar" "$s" '[.menu[] | select(.menu == "View") | .title] | join(",")' "Hide Sidebar,Enter Full Screen"
check_json "with a page selected Reveal is on" "$(item reveal)" '.enabled' "true"

bridge --do menu crossed >/dev/null; settle 0.3
s=$(bridge --state)
check_json "chosen, crossed ones are hidden and the item offers to show them" "$s" '[.crossedShown, ([.menu[] | select(.command == "crossed")][0].title)] | map(tostring) | join(",")' "false,Show Crossed"
bridge --do menu crossed >/dev/null; settle 0.3

bridge --remove "$page" >/dev/null; settle 0.3
s=$(bridge --state)
check_json "with nothing selected Reveal, Previous and Next are off" "$s" '[.selected, (.menu[] | select(.command == "reveal" or .command == "previous" or .command == "next") | .enabled)] | map(tostring) | join(",")' "null,false,false,false"
check_json "and so are Cross, Send and Open in New Window" "$s" '[.menu[] | select(.command == "cross" or .command == "send" or .command == "window") | .enabled] | map(tostring) | join(",")' "false,false,false"

(cd "$CASE_DIR/pages" && bridge page.html); wait_ready; settle 0.3
bridge --do close >/dev/null; settle 0.4
s=$(bridge --state)
check_json "with the main window closed the app answers the Bridge menu" "$s" '[.windowVisible, (.menu[] | select(.command == "new" or .command == "point" or .command == "crossed") | .target + ":" + (.enabled | tostring))] | map(tostring) | join(",")' "false,AppDelegate:true,AppDelegate:true,AppDelegate:true"
check_json "what needs a selected row in a window is off" "$(item cross)" '.enabled' "false"
bridge --do menu crossed >/dev/null; settle 0.4
s=$(bridge --state)
check_json "Hide Crossed from there reshows the window and hides them" "$s" '[.windowVisible, .crossedShown] | map(tostring) | join(",")' "true,false"
bridge --do menu crossed >/dev/null; settle 0.2
bridge --do close >/dev/null; settle 0.4
bridge --do menu new >/dev/null; wait_ready; settle 0.5
s=$(bridge --state)
check_json "New Bridge from there reshows the window on a draft" "$s" '[.windowVisible, .title, .pageFocused] | map(tostring) | join(",")' "true,New Bridge,true"

bridge --do window >/dev/null; settle 0.4
bridge --do close >/dev/null; settle 0.4
s=$(bridge --state)
check_json "with only a page window open New Bridge is still on" "$s" '[.windowVisible, ([.menu[] | select(.command == "new")][0].enabled)] | map(tostring) | join(",")' "false,true"
finish
