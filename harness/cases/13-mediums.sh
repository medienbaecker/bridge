#!/bin/bash
# Text drafts, images, SVG, PDF, and several files in one command.
source "$(dirname "$0")/../lib.sh"

pages="$CASE_DIR/pages"
printf 'Hallo Alex,\n\nLorem ipsum für März sit da — "alle" drei.\n\tEingerückt.\nViele Grüße\n' > "$pages/reply.txt"
cp "/System/Library/Desktop Pictures/Solid Colors/Silver.png" "$pages/shot.png"
printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100"><rect class="box" x="10" y="10" width="80" height="80" fill="#4a90d9"/><circle class="dot" cx="150" cy="50" r="30" fill="#e8a33d"/></svg>' > "$pages/diagram.svg"
sips -s format pdf "$pages/shot.png" --out "$pages/spec.pdf" >/dev/null 2>&1
repo
(cd "$pages" && bridge reply.txt shot.png diagram.svg spec.pdf)
wait_ready
js() { bridge --js "$1" "$2"; }

state=$(bridge --state)
check_json "several files: all presented" "$state" '[.sidebar[].bridges[].title] | length' "4"
check_json "the first is selected" "$state" '.selected' "$pages/reply.txt"

# Plain html pages must still load the user's own images by absolute path (a load
# that grants no file access shows system images and silently drops the user's)
printf '<!doctype html><html><head><title>Bild</title></head><body><img src="%s"><img src="shot.png"></body></html>' "$pages/shot.png" > "$pages/pic.html"
(cd "$pages" && bridge pic.html); wait_ready
check_json "html loads user images, absolute and relative" "$(js "$pages/pic.html" "return [...document.images].map(i => i.naturalWidth).join(',')")" '.' "128,128"

# Text
t="$pages/reply.txt"
bridge --do select "$t" >/dev/null
check_json "text title is the file name" "$state" '.title' "reply.txt"
check_json "word count" "$(js "$t" "return document.querySelector('.doc-text-head .muted').textContent")" '.' "14 words · 81 characters"
check_json "the draft is rendered readably" "$(js "$t" "return getComputedStyle(document.querySelector('.doc-text')).whiteSpace")" '.' "pre-wrap"
check_json "Copy yields the source text, byte for byte" "$(js "$t" "return document.querySelector('#text-source').content.textContent === \`$(cat "$t" | sed 's/`/\\`/g')\` + '\\n'")" '.' "true"
check_json "there is a Copy button" "$(js "$t" "return document.querySelector('[data-copy=\"#text-source\"]').textContent")" '.' "Copy"
snap text "A text draft with a Copy button"
printf 'Hallo Alex,\n\nkurz.\n' > "$t"; settle 0.4
check_json "a rewrite patches the draft" "$(js "$t" "return document.querySelector('.doc-text-head .muted').textContent")" '.' "3 words · 19 characters"

# Image
i="$pages/shot.png"
bridge --do select "$i" >/dev/null; wait_ready
check_json "image loads" "$(js "$i" "const im = document.querySelector('.doc-image img'); return im.naturalWidth > 0 && im.getBoundingClientRect().width <= innerWidth")" '.' "true"
settle 0.3
check_json "title carries the dimensions" "$(bridge --state)" '.title | test("shot.png · [0-9]+×[0-9]+")' "true"
bridge --do point >/dev/null
js "$i" "const im = document.querySelector('.doc-image img'); const r = im.getBoundingClientRect(); im.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true, clientX: r.left + r.width * 0.25, clientY: r.top + r.height * 0.5}))" >/dev/null
settle
js "$i" "const t = document.querySelector('.bridge-thread textarea'); t.value = 'hier'; t.dispatchEvent(new KeyboardEvent('keydown', {key: 'Enter', metaKey: true, bubbles: true}))" >/dev/null
settle 0.3
check_json "a pin on an image is a coordinate" "$(bridge --pins "$i")" '.[0].target' 'img "shot.png" @ 25%, 50%'
snap image "An image with a pin at a coordinate"

# SVG
v="$pages/diagram.svg"
bridge --do select "$v" >/dev/null; wait_ready
check_json "svg is inline and scaled to the pane" "$(js "$v" "const s = document.querySelector('.doc-svg svg'); const w = s.getBoundingClientRect().width; return w > 400 && w <= innerWidth")" '.' "true"
check_json "svg elements can be pinned by class" "$(js "$v" "return document.querySelector('.doc-svg .dot') !== null")" '.' "true"
snap svg "An SVG as a document"

# PDF
p="$pages/spec.pdf"
bridge --do select "$p" >/dev/null; wait_ready
state=$(bridge --state)
check_json "pdf is selected and ready" "$state" '.ready' "true"
check_json "point is off for a pdf" "$state" '[.toolbar[] | select(.id=="point") | .enabled][0]' "false"
snap pdf "A PDF"
finish
