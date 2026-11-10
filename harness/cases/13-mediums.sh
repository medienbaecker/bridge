#!/bin/bash
# Text drafts, markdown, images, SVG, PDF, and several files in one command.
source "$(dirname "$0")/../lib.sh"
# serial

pages="$CASE_DIR/pages"
printf 'Hallo Alex,\n\nLorem ipsum für März sit da — "alle" drei.\n\tEingerückt.\nViele Grüße\n' > "$pages/reply.txt"
cp "/System/Library/Desktop Pictures/Solid Colors/Silver.png" "$pages/shot.png"
printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100"><rect class="box" x="10" y="10" width="80" height="80" fill="#4a90d9"/><circle class="dot" cx="150" cy="50" r="30" fill="#e8a33d"/></svg>' > "$pages/diagram.svg"
sips -s format pdf "$pages/shot.png" --out "$pages/spec.pdf" >/dev/null 2>&1
fixture plan.md >/dev/null
repo
(cd "$pages" && bridge reply.txt shot.png diagram.svg spec.pdf)
wait_ready
js() { bridge --js "$1" "$2"; }

state=$(bridge --state)
check_json "several files: all presented" "$state" '[.sidebar[].bridges[].title] | length' "4"

# Plain html pages must still load the user's own images by absolute path (a load
# that grants no file access shows system images and silently drops the user's)
printf '<!doctype html><html><head><title>Bild</title></head><body><img src="%s"><img src="shot.png"></body></html>' "$pages/shot.png" > "$pages/pic.html"
(cd "$pages" && bridge pic.html); wait_ready
check_json "html loads user images, absolute and relative" "$(js "$pages/pic.html" "return [...document.images].map(i => i.naturalWidth).join(',')")" '.' "128,128"

# Text
t="$pages/reply.txt"
check_json "text title is the file name" "$(bridge --do select "$t")" '.title' "reply.txt"
check_json "word count" "$(js "$t" "return document.querySelector('.doc-text-head .muted').textContent")" '.' "14 words · 81 characters"
check_json "the draft is rendered readably" "$(js "$t" "return getComputedStyle(document.querySelector('.doc-text')).whiteSpace")" '.' "pre-wrap"
check_json "Copy yields the source text, byte for byte" "$(js "$t" "return document.querySelector('#text-source').content.textContent === \`$(cat "$t" | sed 's/`/\\`/g')\` + '\\n'")" '.' "true"
snap text "A text draft with a Copy button"
printf 'Hallo Alex,\n\nkurz.\n' > "$t"; settle 0.4
check_json "a rewrite patches the draft" "$(js "$t" "return document.querySelector('.doc-text-head .muted').textContent")" '.' "3 words · 19 characters"

# Markdown
m="$pages/plan.md"
(cd "$pages" && bridge plan.md); bridge --do select "$m" >/dev/null; wait_ready
check_json "markdown title is the first heading" "$(bridge --state)" '.title' "Move the archive to static pages"
check_json "markdown rendered, tables too" "$(js "$m" "return [...document.querySelectorAll('h2')].map(h => h.textContent).join('|') + ' ' + document.querySelectorAll('table td').length")" '.' "1. Export|2. Redirects 6"
check_json "its Copy button yields the markdown as written, not the rendering" "$(js "$m" "return document.querySelector('[data-copy=\"#markdown-source\"]')?.textContent === 'Copy' && document.querySelector('#markdown-source').content.textContent.startsWith('# Move the archive to static pages')")" '.' "true"
snap markdown "A plan as markdown"
js "$m" "window.__marker = 'alive'; return 1" >/dev/null
sed -i '' 's/one afternoon/one morning/' "$m"
settle 0.5
check_json "a markdown rewrite patches without reload" "$(js "$m" "return window.__marker")" '.' "alive"
check_json "and the new text is on screen" "$(js "$m" "return document.querySelector('.bridge-md p').textContent")" '.' "Three steps, one morning. Nothing to answer; cross it when you have read it."

# Image
i="$pages/shot.png"
bridge --do select "$i" >/dev/null; wait_ready
check_json "image loads" "$(js "$i" "const im = document.querySelector('.doc-image img'); return im.naturalWidth > 0 && im.getBoundingClientRect().width <= innerWidth")" '.' "true"
snap image "An image"

# SVG
v="$pages/diagram.svg"
bridge --do select "$v" >/dev/null; wait_ready
check_json "svg is inline and scaled to the pane" "$(js "$v" "const s = document.querySelector('.doc-svg svg'); const w = s.getBoundingClientRect().width; return w > 400 && w <= innerWidth")" '.' "true"
snap svg "An SVG as a document"

# PDF
p="$pages/spec.pdf"
bridge --do select "$p" >/dev/null; wait_ready
state=$(bridge --state)
check_json "pdf is selected and ready" "$state" '.ready' "true"
snap pdf "A PDF"
finish
