#!/bin/bash
# Search finds pages by title or project name across every project, crossed and
# Earlier ones included; every word must match, case and accents ignored. The
# projects column dims while it is on, and clearing it goes back to where you were.
source "$(dirname "$0")/../lib.sh"
mk() { mkdir -p "$CASE_DIR/$1"; printf '<!doctype html><title>%s</title><p>x</p>' "$2" > "$CASE_DIR/$1/$3.html"; [ -d "$CASE_DIR/$1/.git" ] || (cd "$CASE_DIR/$1" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm x); }
mk RepRisk "Footnote spacing" f1; mk Lizergy "Fußnoten-Verlinkungsübersicht für Datenschutzerklärung" f2; mk Agents "RepRisk: footnotes do not link" f3; mk Agents "Invoice for March" i1
for p in RepRisk/f1 Lizergy/f2 Agents/f3 Agents/i1; do (cd "$CASE_DIR/${p%/*}" && bridge "${p#*/}.html"); done; wait_ready; settle 0.4
bridge --cross "$CASE_DIR/RepRisk/f1.html" >/dev/null; settle 0.3
bridge --do project "project:$(cd "$CASE_DIR/Agents" && pwd -P)" >/dev/null; bridge --do select "$CASE_DIR/Agents/i1.html" >/dev/null; settle 0.3
titles() { bridge --state | jq -r '[.bridgesColumn[] | split("/") | last] | join(",")'; }
check_json "Earlier holds the crossed project" "$(bridge --state)" '[.projects.rows[].name] | index("Earlier") != null' "true"
bridge --do search "footnote" >/dev/null; settle 0.4
check "a word finds titles in every project, crossed last" "$(titles)" "f3.html,f1.html"
check_json "the projects column dims while searching" "$(bridge --state)" '.projectsDimmed' "true"
bridge --do search "REPRISK" >/dev/null; settle 0.3
check "the project name matches too, case ignored" "$(titles)" "f3.html,f1.html"
bridge --do search "reprisk spacing" >/dev/null; settle 0.3
check "every word must match" "$(titles)" "f1.html"
bridge --do search "fussnoten" >/dev/null; settle 0.3
check "ß matches ss" "$(titles)" "f2.html"
bridge --do search "verlinkungsubersicht" >/dev/null; settle 0.3
check "an umlaut matches its bare letter inside a long compound" "$(titles)" "f2.html"
bridge --do search "nothing like this" >/dev/null; settle 0.3
check_json "no match says so" "$(bridge --state)" '.listEmpty' "No pages match"
bridge --do search "" >/dev/null; settle 0.3
check_json "cleared, the list is the project you were in again, with your page selected" "$(bridge --state)" '(.projectsDimmed | not) and (.projects.scope | endswith("/Agents")) and (.selected | endswith("i1.html"))' "true"
bridge --do search "footnote" >/dev/null; settle 0.3
bridge --do sidebarwidth 180 >/dev/null; bridge --do resize "880 600" >/dev/null; settle 0.5
bridge --shot "$CASE_DIR/shots/search-narrow.png" >/dev/null
fits() { bridge --state | jq -r '(.columnWidths[0] + .columnWidths[1]) as $edge | .searchFrame | .shown and (.x + .width) <= $edge'; }
check "the open field stays over the list at the narrowest window" "$(fits)" "true"
bridge --do search "" >/dev/null; bridge --do find >/dev/null; settle 0.4
check_json "⌘F opens the field with the cursor in it" "$(bridge --state)" '.searchFocused' "true"
bridge --do resize "1400 800" >/dev/null; bridge --do sidebarwidth 280 >/dev/null; bridge --do search "footnote" >/dev/null; settle 0.5
check "and at a wide one" "$(fits)" "true"
bridge --shot "$CASE_DIR/shots/search-wide.png" >/dev/null
bridge --do search "" >/dev/null; settle 0.4
check "empty, the field is still open and fills the list's toolbar" "$(bridge --state | jq -r '.searchFrame.shown and .searchFrame.width >= .columnWidths[1] - 80')" "true"
gaps() {  # $1 shot -> "<column edge to field> <compose to column edge>" in points, from the drawn capsules
  local g; g=$(bridge --state); bridge --shot "$CASE_DIR/shots/$1.png" >/dev/null
  python3 -I - "$CASE_DIR/shots/$1.png" "$(printf '%s' "$g" | jq -r '.backingScale')" "$(printf '%s' "$g" | jq -r '.columnWidths[0]')" "$(printf '%s' "$g" | jq -r '.columnWidths[0] + .columnWidths[1]')" "$(printf '%s' "$g" | jq -r '.titlebarHeight / 2')" <<'PY'
import sys
from PIL import Image
path, scale, left, right, mid = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5])
im = Image.open(path).convert("RGB"); y = int(mid * scale)
xs = [x for x in range(int(left * scale) + 2, int(right * scale) - 2) if sum(im.getpixel((x, y))) < 735]
print(round((xs[0] / scale - left), 1), round((right - xs[-1] / scale), 1))
PY
}
even() { printf '%s' "$1" | awk '{print ($1 - $2 <= 1 && $2 - $1 <= 1) ? "yes" : "no"}'; }
g=$(gaps search-idle); check "the field and the compose button sit the same distance from the column's edges ($g pt)" "$(even "$g")" "yes"
bridge --do resize "880 600" >/dev/null; bridge --do sidebarwidth 180 >/dev/null; settle 0.5
g=$(gaps search-idle-narrow); check "and in the narrowest window ($g pt)" "$(even "$g")" "yes"
bridge --do search "" >/dev/null
finish
