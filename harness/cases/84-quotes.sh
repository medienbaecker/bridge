#!/bin/bash
source "$(dirname "$0")/../lib.sh"

mkdir -p "$CASE_DIR/pages/src"
printf 'import x from "y";\n\nclass Card {\n    title() {\n        return "Archive";\n    }\n}\n' > "$CASE_DIR/pages/src/card.js"
cat > "$CASE_DIR/pages/code.html" <<'HTML'
<!doctype html><title>Code</title>
<h1>The title comes from here</h1>
<pre><code class="language-js" data-quote="src/card.js:4-6"></code></pre>
<pre><code class="language-js" data-quote="src/gone.swift:1-2"></code></pre>
HTML
page="$CASE_DIR/pages/code.html"
err=$( (cd "$CASE_DIR/pages" && bridge code.html) 2>&1 >/dev/null)
wait_ready
js() { bridge --js "$1" "$2"; }
check "the lines come from the file, without their indent" "$(js "$page" "return document.querySelector('code').textContent" | jq -r .)" $'title() {\n    return "Archive";\n}'
check "and are highlighted" "$(js "$page" "return document.querySelector('code .token') !== null")" "true"
check "a missing file is reported to the agent" "${err#*: }" "code.html threw: quote src/gone.swift:1-2: src/gone.swift is not a readable text file"
snap quote "Lines quoted from a file, with their path and range"

python3 - "$page" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace('<h1>The title comes from here</h1>', '<h1>The title comes from here</h1>\n<p>Moved down.</p>')
open(p,'w').write(s)
PY
for i in $(seq 1 30); do [ "$(js "$page" "return document.querySelectorAll('p').length")" = "1" ] && break; sleep 0.1; done
check "an edit to the page keeps the quote" "$(js "$page" "return document.querySelector('code').textContent.split('\n')[0]" | jq -r .)" "title() {"
check "without a reload" "$(bridge --state | jq -r '.banner')" "null"

printf '# Plan\n\n```js quote=src/card.js:3\n```\n' > "$CASE_DIR/pages/plan.md"
(cd "$CASE_DIR/pages" && bridge plan.md)
for i in $(seq 1 30); do [ -n "$(js "$CASE_DIR/pages/plan.md" "return document.querySelector('code')?.textContent" | jq -r '. // empty')" ] && break; sleep 0.1; done
check "a markdown fence quotes too" "$(js "$CASE_DIR/pages/plan.md" "return document.querySelector('code').textContent + ' | ' + document.querySelector('code').dataset.quote" | jq -r .)" "class Card { | src/card.js:3"
finish
