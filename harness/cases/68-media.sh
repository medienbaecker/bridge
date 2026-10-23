#!/bin/bash
source "$(dirname "$0")/../lib.sh"

mkdir -p "$CASE_DIR/elsewhere"
pixel() { python3 - "$1" "$2" <<'PY'
import sys, struct, zlib
w = int(sys.argv[2])
raw = b''.join(b'\0' + b'\xff\0\0' * w for _ in range(1))
chunk = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d))
open(sys.argv[1], 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, 1, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
PY
}
pixel "$CASE_DIR/pages/near.png" 1
pixel "$CASE_DIR/elsewhere/far.png" 1
page="$CASE_DIR/pages/media.html"
cat > "$page" <<HTML
<!doctype html><html><head><title>Media</title></head><body>
<p>Two images</p>
<img id="near" src="near.png">
<img id="far" src="$CASE_DIR/elsewhere/far.png">
</body></html>
HTML
(cd "$CASE_DIR/pages" && bridge media.html)
wait_ready
js() { bridge --js "$page" "$1"; }
width() { js "const i = document.getElementById('$1'); await new Promise(r => i.complete ? r() : i.addEventListener('load', r, { once: true })); return i.naturalWidth"; }
js "window.__marker = 'alive'; return 1" >/dev/null

check_json "near image starts 1px wide" "$(width near)" '.' "1"
check_json "far image starts 1px wide" "$(width far)" '.' "1"

pixel "$CASE_DIR/pages/near.png" 2
settle 0.4
check_json "an image beside the page is re-fetched when rewritten" "$(width near)" '.' "2"

pixel "$CASE_DIR/elsewhere/far.tmp" 3 && mv "$CASE_DIR/elsewhere/far.tmp" "$CASE_DIR/elsewhere/far.png"
settle 0.4
check_json "an image in another folder is re-fetched when replaced" "$(width far)" '.' "3"
check_json "the page was not reloaded" "$(js "return window.__marker")" '.' "alive"

sed -i '' 's/Two images/Still two images/' "$page"
settle 0.4
check_json "a later patch keeps the fresh image" "$(width far)" '.' "3"

pixel "$CASE_DIR/elsewhere/far.png" 4
settle 0.4
check_json "and it is still watched after the patch" "$(width far)" '.' "4"

sed -i '' "s|</body>|<img id=\"soon\" src=\"soon.png\"><img id=\"deep\" src=\"$CASE_DIR/later/sub/deep.png\"></body>|" "$page"
settle 0.4
check_json "images that do not exist yet show broken" "$(js "return [soon.naturalWidth, deep.naturalWidth].join(' ')")" '.' "0 0"
pixel "$CASE_DIR/pages/soon.png" 5
mkdir -p "$CASE_DIR/later"; settle 0.3; mkdir "$CASE_DIR/later/sub"; settle 0.3
pixel "$CASE_DIR/later/sub/deep.png" 6
settle 0.4
check_json "an image created beside the page after it loaded appears" "$(width soon)" '.' "5"
check_json "so does one created in a folder that did not exist yet" "$(width deep)" '.' "6"
rm "$CASE_DIR/pages/soon.png"
settle 0.4
check_json "a deleted image shows broken" "$(js "return soon.naturalWidth")" '.' "0"
pixel "$CASE_DIR/pages/soon.png" 7
settle 0.4
check_json "and appears again when it comes back" "$(width soon)" '.' "7"
check_json "none of this reloaded the page" "$(js "return window.__marker")" '.' "alive"
finish
