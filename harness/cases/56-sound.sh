#!/bin/bash
# An agent's sound demo failed with "Cross-origin script load denied". A page is a file:// document; an AudioWorklet module from a blob URL has another
# origin and some WebKit versions refuse it (others load it), while a module file beside the page always loads. The skill says
# so (pages.md, Sound) and the lint names the blob; this keeps both honest. Widening
# file access instead would let any page read any file on the user's Mac.
source "$(dirname "$0")/../lib.sh"
page=$(fixture sound.html)
fixture sound-processor.js >/dev/null
repo
(cd "$CASE_DIR/pages" && bridge sound.html) >/dev/null; wait_ready
r=$(bridge --js "$page" "return await window.probe()")
check_json "a blob worker, import and fetch work" "$r" '"\(.worker) \(.importBlob) \(.fetchBlob)"' "ok ok ok"
check_json "an AudioWorklet module from a blob either loads or is refused as cross-origin, never anything else" "$r" '.worklet == "ok" or (.worklet | test("Cross-origin"))' "true"
check_json "a module file beside the page loads, as the skill advises" "$(bridge --js "$page" "try { const c = new AudioContext(); await c.audioWorklet.addModule('sound-processor.js'); return 'ok' } catch (e) { return String(e) }")" '.' "ok"
check "the lint names the blob before the user sees the page" "$(bridge --lint "$page" | grep -c 'AudioWorklet module from a blob URL')" "1"
finish
