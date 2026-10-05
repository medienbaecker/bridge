#!/bin/bash
source "$(dirname "$0")/../lib.sh"
page=$(fixture umlaut.html)
repo
(cd "$CASE_DIR/pages" && bridge umlaut.html)
wait_ready
check_json "a page without meta charset is UTF-8" "$(bridge --js "$page" "return document.characterSet")" '.' "UTF-8"
check_json "umlauts, dashes and emoji survive" "$(bridge --js "$page" "return document.querySelector('p').textContent")" '.' "Schön, daß es geht: äöü ÄÖÜ ß € 🙂"
check_json "the title too" "$(bridge --state)" '.title' "Umlaute — Test"
sed -i '' 's/passt\./paßt — wirklich./' "$page"
settle 0.4
check_json "and a patch keeps them" "$(bridge --js "$page" "return document.querySelector('[data-value=ja]').textContent.trim()")" '.' "JaGröße stimmt — paßt — wirklich."
finish
