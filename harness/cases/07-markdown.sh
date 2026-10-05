#!/bin/bash
source "$(dirname "$0")/../lib.sh"

page=$(fixture plan.md)
repo
(cd "$CASE_DIR/pages" && bridge plan.md)
wait_ready
js() { bridge --js "$page" "$1"; }

check_json "title is the first heading" "$(bridge --state)" '.title' "Move the archive to static pages"
check_json "markdown rendered" "$(js "return [...document.querySelectorAll('h2')].map(h => h.textContent).join('|')")" '.' "1. Export|2. Redirects"
check_json "tables render" "$(js "return document.querySelectorAll('table td').length")" '.' "6"
check_json "there is a Copy button" "$(js "return document.querySelector('[data-copy=\"#markdown-source\"]')?.textContent ?? null")" '.' "Copy"
check_json "and it yields the markdown as written, not the rendering" "$(js "return document.querySelector('#markdown-source').content.textContent.startsWith('# Move the archive to static pages')")" '.' "true"
snap markdown "A plan as markdown"
js "window.__marker = 'alive'; return 1" >/dev/null
sed -i '' 's/one afternoon/one morning/' "$page"
settle 0.5
check_json "rewrite patched without reload" "$(js "return window.__marker")" '.' "alive"
check_json "new text is on screen" "$(js "return document.querySelector('.bridge-md p').textContent")" '.' "Three steps, one morning. Nothing to answer; cross it when you have read it."
finish
