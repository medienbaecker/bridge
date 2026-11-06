#!/bin/bash
source "$(dirname "$0")/../lib.sh"
# serial
printf '<!doctype html><title>Lorem</title><p>x</p>' > "$CASE_DIR/pages/page.html"
(cd "$CASE_DIR/pages" && bridge page.html); wait_ready; settle 0.3
bridge --do hide >/dev/null; settle 0.5
check_json "hidden with ⌘H, Bridge is hidden" "$(bridge --state)" '.appHidden' "true"
bridge --do freeze >/dev/null; settle 1
check_json "the glass over a hidden Bridge keeps its windows out of sight" "$(bridge --state)" '[.freeze.veiled > 0, .freeze.mainVisible] | map(tostring) | join(",")' "true,false"
bridge --do freeze-cancel >/dev/null; settle 0.6
check_json "and closing the glass leaves Bridge hidden" "$(bridge --state)" '.appHidden' "true"
finish
