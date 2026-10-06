#!/bin/bash
# `--shot <page> <out.png>` renders a page off-screen the way the window would,
# so the writing agent can look before the user does. It presents nothing,
# lists nothing and records nothing, also for a page the user already answered.
source "$(dirname "$0")/../lib.sh"
page=$(fixture decision.html fresh.html); answered=$(fixture decision.html answered.html)
r=$(bridge --shot "$page" "$CASE_DIR/shots/fresh.png" --width 600)
check_json "it reports the size it rendered at" "$r" '"\(.width) \(.height > 200)"' "600 true"
check "at twice the points, like the window" "$(sips -g pixelWidth "$CASE_DIR/shots/fresh.png" | awk '/pixelWidth/ {print $2}')" "1200"
colours=$(ink "the rendered page" python3 - "$CASE_DIR/shots/fresh.png" <<'PY'
import struct, subprocess, sys, tempfile
bmp = tempfile.mktemp(suffix=".bmp")
subprocess.run(["sips", "-s", "format", "bmp", sys.argv[1], "--out", bmp], capture_output=True)
data = open(bmp, "rb").read()
off, w, h, bpp = struct.unpack_from("<I", data, 10)[0], *struct.unpack_from("<iiHH", data, 18)[:2], struct.unpack_from("<H", data, 28)[0]
step, row = bpp // 8, ((w * bpp + 31) // 32) * 4
seen = {data[off + y * row + x * step: off + y * row + x * step + 3] for y in range(0, abs(h), 8) for x in range(0, w, 8)}
print(len(seen) if len(seen) > 2 else "")
PY
)
check "the picture holds the page, not a blank" "$([ "$colours" != NOINK ] && [ "$colours" -gt 20 ] && echo drawn)" "drawn"
check_json "nothing joins the list" "$(bridge --state)" '.bridgesColumn | length' "0"
check "nothing is recorded for it" "$([ -e "$(sidecar "$page")" ] && echo recorded || echo none)" "none"
(cd "$CASE_DIR/pages" && bridge answered.html 2>/dev/null); wait_ready; settle 0.4
bridge --js "$answered" "document.querySelector('[data-value=grid]').click()" >/dev/null; settle 0.5
before=$(shasum "$(sidecar "$answered")" | cut -d' ' -f1)
bridge --shot "$answered" "$CASE_DIR/shots/answered.png" >/dev/null
check "an answered page's record is untouched" "$(shasum "$(sidecar "$answered")" | cut -d' ' -f1)" "$before"
check_json "and it is still version 1 with the answer" "$(bridge --read "$answered")" '"\(.version) \(.answers.layout)"' "1 grid"
finish
