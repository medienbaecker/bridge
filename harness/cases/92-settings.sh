#!/bin/bash
source "$(dirname "$0")/../lib.sh"
printf '<!doctype html><title>Lorem ipsum</title><p>Lorem ipsum dolor sit amet.</p>' > "$CASE_DIR/pages/page.html"
repo
(cd "$CASE_DIR/pages" && bridge page.html); wait_ready; settle 0.3
bridge --do settings >/dev/null; settle 0.3
check_json "Settings opens with today's behaviour as its values" "$(bridge --state)" '.settings | [.visible, .ended, .sound, .updates, .appearance] | @tsv' "true	24 hours	true	true	System"
finish
