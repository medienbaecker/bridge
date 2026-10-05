#!/bin/bash
# The skill and the kit agree both ways: every class the skill's examples or
# its vocabulary list name is defined in page.css, and every class page.css
# defines for pages is in the vocabulary list. The runtime's own bridge-* and
# doc-* classes, the highlighter's token names and the language-* hook are the
# kit's business, not a page's, so they are not part of the vocabulary.
. "$(dirname "$0")/../lib.sh"

report=$(python3 - "$ROOT" <<'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
css = (root / 'Sources/Bridge/web/page.css').read_text()
skill = (root / 'skills/bridge/pages.md').read_text()
css_classes = set(re.findall(r'\.(-?[_a-zA-Z][\w-]*)', re.sub(r'/\*.*?\*/', '', css, flags=re.S)))
tokens = set(re.findall(r'\.token\.([\w-]+)', css)) | {'token'}
internal = {c for c in css_classes if c.startswith(('bridge-', 'doc-', 'language-')) or c in tokens}
public = css_classes - internal
vocab_section = skill.split('## What the base stylesheet gives you', 1)[1]
vocab = set(c for span in re.findall(r'`([^`]*)`', vocab_section) for c in re.findall(r'\.(-?[_a-zA-Z][\w-]*)', span))
taught = set()
for m in re.findall(r'class="([^"]*)"', skill): taught |= set(m.split())
taught -= {c for c in taught if c.startswith('language-')}
# Classes an example defines in its own <style> are the page's, not the kit's.
own = set(re.findall(r'<style>[^<]*?\.(-?[_a-zA-Z][\w-]*)', skill))
print('taught-not-defined', ' '.join(sorted(taught - css_classes - own)))
print('defined-not-listed', ' '.join(sorted(public - vocab)))
print('listed-not-defined', ' '.join(sorted(vocab - css_classes - {'language-'})))
PY
)
check "every class the skill's examples use is in page.css" "$(printf '%s' "$report" | awk '/^taught-not-defined/ {$1=""; print substr($0, 2)}')" ""
check "every class page.css gives pages is in the vocabulary list" "$(printf '%s' "$report" | awk '/^defined-not-listed/ {$1=""; print substr($0, 2)}')" ""
check "every class the vocabulary lists is in page.css" "$(printf '%s' "$report" | awk '/^listed-not-defined/ {$1=""; print substr($0, 2)}')" ""
finish
