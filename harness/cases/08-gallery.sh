#!/bin/bash
# Closes the loop between the skill's cheat sheets and what actually renders:
# every documented component must be in the gallery, every gallery component
# must be documented, and both galleries are photographed on every run.
source "$(dirname "$0")/../lib.sh"
export BRIDGE_TOOLKIT="$ROOT/toolkit"
GALLERY="$OUT/gallery"; mkdir -p "$GALLERY"

# Plain: classes and selectors listed in pages.md under "What the base stylesheet gives you"
documented=$(sed -n '/^## What the base stylesheet gives you/,$p' "$ROOT/skills/bridge/pages.md" | grep -o '`[^`]*`' | tr -d '`' | tr ' ' '\n' | grep -E '^(\.|\[)' | sort -u)
missing=$(for sel in $documented; do grep -q -- "$(printf '%s' "$sel" | sed 's/^\.//; s/^\[data-send\]$/data-send/; s/\.options\.stack/options stack/; s/^language-\*$/language-/')" "$ROOT/harness/fixtures/gallery.html" || printf '%s ' "$sel"; done)
check "the gallery has everything pages.md documents" "$missing" ""
missing=$(for cls in $(grep -o 'class="[^"]*"' "$ROOT/harness/fixtures/gallery.html" | sed 's/class="//; s/"//' | tr ' ' '\n' | sort -u); do
  case "$cls" in (language-*) pattern='^\.language-\*$';; (*) pattern="^\.([a-z-]+\.)?$cls\$";; esac
  printf '%s\n' "$documented" | grep -q -E "$pattern" || printf '.%s ' "$cls"
done)
check "pages.md documents every class the gallery uses" "$missing" ""

# Mantine: component names in the mantine.md table must be imported by the gallery, and vice versa
table=$(sed -n '/^| Component/,/^$/p' "$ROOT/skills/bridge/mantine.md" | tail -n +3 | cut -d'|' -f2 | grep -o '`[A-Za-z.]*`' | tr -d '`' | sed 's/\..*//' | sort -u)
imported=$(head -1 "$ROOT/harness/fixtures/gallery.jsx" | sed 's/import {//; s/}.*//' | tr ',' '\n' | tr -d ' ' | sort -u)
check "the gallery imports every component mantine.md lists" "$(for c in $table; do printf '%s\n' "$imported" | grep -q "^$c\$" || printf '%s ' "$c"; done)" ""
layout="Title Text Stack Group SimpleGrid Table Badge Code Divider Image"
missing=$(for c in $imported; do
  case " $layout " in (*" $c "*) continue;; esac
  printf '%s\n' "$table" | grep -q "^$c\$" || printf '%s ' "$c"
done)
check "mantine.md lists every component the gallery imports" "$missing" ""

page=$(fixture gallery.html)
repo
(cd "$CASE_DIR/pages" && bridge gallery.html)
wait_ready
check_json "plain gallery renders every option card" "$(bridge --js "$page" "return document.querySelectorAll('[data-record][data-value]:not(.color)').length")" '.' "3"
check_json "images loaded" "$(bridge --js "$page" "return [...document.images].every(i => i.complete && i.naturalWidth > 0)")" '.' "true"
check_json "code is highlighted" "$(bridge --js "$page" "return document.querySelectorAll('.language-php .token').length > 3")" '.' "true"
check_json "diff lines are marked, one line each" "$(bridge --js "$page" "const pre = document.querySelector('.language-diff').parentElement; const lh = parseFloat(getComputedStyle(pre).lineHeight); const rows = [...document.querySelectorAll('.language-diff > .token.inserted, .language-diff > .token.deleted')].map(t => Math.round(t.getBoundingClientRect().height / lh)); return rows.join(',')")" '.' "1,1"
check_json "bars have length" "$(bridge --js "$page" "const b = document.querySelectorAll('.bar'); return getComputedStyle(b[0], '::after').width !== getComputedStyle(b[1], '::after').width")" '.' "true"
sed -i '' 's/listed();<\/code><\/pre>\n/listed();<\/code><\/pre>/' "$page"
python3 - "$page" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read(); open(p,'w').write(s.replace('+ $items = $page->children()->listed();', '+ $items = $page->children()->listed()->sortBy(\'date\');'))
PY
settle 0.4
check_json "highlighting survives a patch" "$(bridge --js "$page" "return document.querySelector('.language-diff .token.inserted')?.textContent.includes('sortBy')")" '.' "true"
bridge --snap "$GALLERY/plain.png" >/dev/null
snap plain "Plain gallery"
bridge --js "$page" "document.querySelector('#evidence').scrollIntoView(); return 1" >/dev/null
settle 0.3
bridge --snap "$GALLERY/plain-evidence.png" >/dev/null
snap plain-evidence "Plain gallery: evidence, screenshots, draft"
check_json "screenshots take the full width, one under another" "$(bridge --js "$page" "const [a, b] = [...document.querySelectorAll('.shots img')].map((i) => i.getBoundingClientRect()); const full = document.querySelector('#screenshots').getBoundingClientRect().width; return [Math.round(full - a.width), Math.round(full - b.width), b.top > a.bottom].join(',')")" '.' "0,0,true"
bridge --js "$page" "document.querySelector('#screenshots').scrollIntoView(); return 1" >/dev/null
settle 0.3
bridge --snap "$GALLERY/plain-screenshots.png" >/dev/null
snap plain-screenshots "Plain gallery: screenshots"

jsx=$(fixture gallery.jsx); fixture gallery.data.json >/dev/null
(cd "$CASE_DIR/pages" && bridge gallery.jsx)
wait_ready
bridge --snap "$GALLERY/mantine.png" >/dev/null
snap mantine "Mantine gallery"
echo "  galleries: $GALLERY/plain.png, $GALLERY/mantine.png"
finish
