#!/bin/bash
source "$(dirname "$0")/../lib.sh"
title="Donaudampfschifffahrtsgesellschaftskapitänswitwenrentenantragsformular"
printf '<!doctype html><title>%s</title><p>Lorem ipsum dolor sit amet.</p>' "$title" > "$CASE_DIR/pages/page.html"
page="$CASE_DIR/pages/page.html"
repo
(cd "$CASE_DIR/pages" && bridge page.html); wait_ready; settle 0.3

strip_ink() {  # <shot name>
  local state scale x y
  state=$(bridge --state); scale=$(printf '%s' "$state" | jq -r .backingScale)
  x=$(printf '%s' "$state" | jq -r '.pageX'); y=$(printf '%s' "$state" | jq -r '.titlebarHeight + 14')
  python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/$1.png" "$(awk "BEGIN {print int($y * $scale)}")" 1 \
    | awk -v from="$(awk "BEGIN {print $x * $scale}")" '$1 > from && $3 + $4 + $5 < 300 {n += $2 - $1} END {if (n) print n}'
}

check_json "a page with nothing to say has no strip" "$(bridge --state)" '.bannerStrip' "null"
shot plain >/dev/null
check "and no ink where it would be" "$(strip_ink plain)" ""

short="Lorem Ipsum had ended, so your notes are kept here as a draft."
bridge --do undelivered "$short" >/dev/null; settle 0.4
s=$(bridge --state)
check_json "notes kept as a draft say why, in the strip" "$s" '.bannerStrip.text' "$short"
check_json "the strip runs the full width of the page pane" "$s" '.bannerStrip.width == .columnWidths[2]' "true"
check_json "it sits right under the toolbar" "$s" '.bannerStrip.top == .titlebarHeight' "true"
check_json "the page starts below it" "$s" '.bannerStrip.pageInset == .titlebarHeight + .bannerStrip.height' "true"
shot strip >/dev/null
n=$(ink "the strip's text" strip_ink strip)
check "the words are drawn ($n px of ink)" "$([ "$n" -gt 100 ] && echo drawn)" "drawn"

long="$title-$title had ended, so your notes are kept here as a draft. Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est."
bridge --do undelivered "$long" >/dev/null; settle 0.3
bridge --do resize "880 500" >/dev/null; settle 0.4
s=$(bridge --state)
check_json "a long one wraps to three lines at most in the narrowest window" "$s" '.bannerStrip.height > 40 and .bannerStrip.height < 70' "true"
check_json "and still spans the pane" "$s" '.bannerStrip.width == .columnWidths[2]' "true"
shot long >/dev/null
bridge --do resize "1180 720" >/dev/null; settle 0.3
bridge --do undelivered "$short" >/dev/null; settle 0.3

bridge --do window >/dev/null; settle 0.4
s=$(bridge --state)
check_json "in a window of its own the page says it in that window's subtitle" "$s" '.pageWindows[0].subtitle' "$short"
check_json "and the main window's strip goes with the page" "$s" '.bannerStrip' "null"
bridge --do closewindow "$page" >/dev/null; settle 0.3
check_json "back in the main window, the strip is back" "$(bridge --state)" '.bannerStrip.text' "$short"

bridge --quit >/dev/null 2>&1; sleep 0.5
export BRIDGE_APPEARANCE=dark
(cd "$CASE_DIR/pages" && bridge page.html); wait_ready; settle 0.3
bridge --do undelivered "$short" >/dev/null; settle 0.4
shot dark >/dev/null
finish
