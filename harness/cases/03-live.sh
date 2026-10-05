#!/bin/bash
source "$(dirname "$0")/../lib.sh"

page=$(fixture decision.html)
repo
(cd "$CASE_DIR/pages" && bridge decision.html)
wait_ready
js() { bridge --js "$page" "$1"; }

js "document.querySelector('[data-value=grid]').click()" >/dev/null
bridge --do send >/dev/null
js "window.__marker = 'alive'; document.querySelector('[data-record=note]').value = 'half a note'; document.querySelector('[data-record=note]').focus(); document.querySelector('[data-value=grid]').__same = true; return 1" >/dev/null

# 1. Prose changes patch in place and cost nothing
sed -i '' 's/Two layouts survive the content; pick one./Two layouts survive the content. Pick one./' "$page"
settle 0.4
check_json "prose rewrite does not reload" "$(js "return window.__marker")" '.' "alive"
check_json "prose rewrite patched the text" "$(js "return document.querySelector('.muted').textContent")" '.' "The archive page has 140 entries. Two layouts survive the content. Pick one."
check_json "one patch happened" "$(js "@bridge return __bridge.state.patches")" '.' "1"
check_json "the option node was kept, not replaced" "$(js "return document.querySelector('[data-value=grid]').__same === true")" '.' "true"
check_json "the chosen option is still chosen" "$(js "return document.querySelector('[data-value=grid]').hasAttribute('data-selected')")" '.' "true"
check_json "focus survived" "$(js "return document.activeElement === document.querySelector('[data-record=note]')")" '.' "true"
check_json "the unsent draft survived" "$(js "return document.querySelector('[data-record=note]').value")" '.' "half a note"
read=$(bridge --read "$page")
check_json "still sent" "$read" '.status' "sent"
check_json "still version 1" "$read" '.version' "1"
check_json "answer stands" "$read" '.answers.layout' "grid"
check_json "the strip says nothing after Send; the toolbar carries sent" "$(bridge --state)" '.banner' "null"

# 2. Recording an answer must not echo back as a patch
js "const r = document.querySelector('[data-record=radius]'); r.value = 20; r.dispatchEvent(new Event('change', {bubbles: true}))" >/dev/null
settle 0.4
check_json "own sidecar write did not patch" "$(js "@bridge return __bridge.state.patches")" '.' "1"

# 3. A new question makes a new version
python3 - "$page" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace('<h2>Corner radius</h2>', '<h2>Density</h2>\n<div class="options"><div data-record="density" data-value="cosy"><strong>Cosy</strong></div><div data-record="density" data-value="compact"><strong>Compact</strong></div></div>\n<h2>Corner radius</h2>')
open(p,'w').write(s)
PY
settle 0.5
read=$(bridge --read "$page")
check_json "version 2" "$read" '.version' "2"
check_json "send taken back" "$read" '.status' "open"
check_json "answers cleared" "$read" '.answers | length' "0"
check_json "history keeps version 1 answers" "$read" '.history[0].answers.layout' "grid"
state=$(bridge --state)
check_json "banner explains what changed" "$state" '.banner' "Changed since you answered: asks density. Version 2."
# The message lives under the title, and only while there is one: drawn in the
# lower half of the title band, where a title alone leaves nothing.
check_json "the window's subtitle carries it" "$state" '.subtitle' "Changed since you answered: asks density. Version 2."
band_glyphs() { python3 "$ROOT/harness/measure.py" "$1" columns 440 60 1900 104 200 | wc -w | tr -d ' '; }
bridge --shot "$CASE_DIR/shots/subtitle.png" >/dev/null
check "and it is drawn under the title ($(band_glyphs "$CASE_DIR/shots/subtitle.png") glyph clusters in the band's lower half)" "$([ "$(band_glyphs "$CASE_DIR/shots/subtitle.png")" -ge 10 ] && echo drawn)" "drawn"
check_json "unread again" "$state" '.sidebar[0].bridges[0].unread' "true"
check_json "send enabled again" "$state" '[.toolbar[] | select(.id=="send") | .enabled][0]' "true"
check_json "still no reload" "$(js "return window.__marker")" '.' "alive"
check_json "page shows what the user said last time" "$(js "return document.querySelector('.bridge-previous').textContent")" '.' "Grid"
check_json "the old choice is no longer marked" "$(js "return document.querySelector('[data-value=grid]').hasAttribute('data-selected')")" '.' "false"
snap changed "Version 2: changed-since-you-answered banner, last-time hints"

# 4. Walking back through versions
state=$(bridge --do previous)
check_json "previous shows version 1" "$state" '.viewingVersion' "1"
check_json "banner says which version" "$state" '.banner | startswith("Version 1 of 2")' "true"
check_json "the subtitle says so too" "$state" '.subtitle | startswith("Version 1 of 2")' "true"
wait_ready
check_json "old version has no density question" "$(js "return document.querySelectorAll('[data-record=density]').length")" '.' "0"
check_json "old version shows the old answer" "$(js "return document.querySelector('[data-value=grid]').hasAttribute('data-selected')")" '.' "true"
check_json "send disabled while looking back" "$state" '[.toolbar[] | select(.id=="send") | .enabled][0]' "false"
snap version1 "Looking back at version 1, read-only"
state=$(bridge --do next)
check_json "next returns to live" "$state" '.viewingVersion' "null"
wait_ready
check_json "live again has the density question" "$(js "return document.querySelectorAll('[data-record=density]').length")" '.' "2"

# 5. Same questions, reworded: no new version
sed -i '' 's/<strong>Cosy<\/strong>/<strong>Cosy (more air)<\/strong>/' "$page"
settle 0.4
check_json "rewording an option is not a new version" "$(bridge --read "$page")" '.version' "2"

# 6. A script change is an honest reload
js "window.__marker = 'alive'; return 1" >/dev/null
printf '<script>window.__added = 1</script>\n' >> "$page"
settle 0.6
wait_ready
check_json "script change reloads" "$(js "return window.__marker || 'gone'")" '.' "gone"
check_json "and says so" "$(bridge --state)" '.banner' "The page's scripts changed, so it was reloaded."
finish
