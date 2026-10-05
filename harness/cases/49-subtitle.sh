#!/bin/bash
# The second column carries the project name as a subtitle, only in the lists
# that cross projects: in a project's own list it would be the same word on
# every row. The column's reading edge must survive a second line: title and
# subtitle start where the header starts, the dot and the time keep the trailing
# edge, the pill encloses both lines evenly, and the two lines truncate
# independently of each other.
source "$(dirname "$0")/../lib.sh"

make() {  # <project dir> <file> <title>
  local p="$CASE_DIR/$1"
  mkdir -p "$p"
  printf '<!doctype html><html><head><title>%s</title></head><body><h1>%s</h1></body></html>' "$3" "$3" > "$p/$2"
  (cd "$p" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm f 2>/dev/null)
  (cd "$p" && bridge "$2" >/dev/null 2>&1); wait_ready
}
# Both lines start with the same letter, so comparing their ink compares the
# layout and not the side bearing of two different glyphs at two sizes.
long="Cards-and-a-much-wider-name-than-the-column-can-ever-show"
title="Card layout for the archive, a title long enough to truncate in this column"
make "Cards" "archive.html" "$title"
make "$long" "estimate.html" "$title"
# An agent waiting on this session keeps the subtitle to the project's name: the
# rows measured here are about the name, and "no agent waiting" has descenders.
"$ROOT/build.noindex/bridge-dev" --wait "$CASE_DIR/Cards/archive.html" --timeout 120 >/dev/null & waiter=$!
settle 0.4
bridge --do resize "1179 800" >/dev/null; settle 0.5

# What the rows carry, per scope.
bridge --do project all >/dev/null; settle 0.4
check_json "in All every row names the project it came from" "$(bridge --state)" '[.sidebar[].bridges[].subtitle | split(" · ")[0]] | sort | join(",")' "Cards,$long"
one=$(bridge --state | jq -r '[.sidebar[] | select(.project == "Cards")][0] | "project:" + (.bridges[0].location | split("/")[:-1] | join("/"))')
bridge --do project "$one" >/dev/null; settle 0.4
check_json "in a project's own list it says nothing: the same word on every row is noise" "$(bridge --state)" '[.sidebar[].bridges[].subtitle | tostring] | unique | join(",")' "null"
# The nil path is the one-line row: no project to name behaves as a project's own list does.
check_json "and its rows are one line again" "$(bridge --state)" '.sidebarGeometry.rowInWindow.height' "30"
bridge --do project all >/dev/null; settle 0.4
# Select the short-named one so the measured row is known: the long-named one was
# presented later and sits above it, which is the row every offset below counts from.
bridge --do select "$CASE_DIR/Cards/archive.html" >/dev/null; settle 0.4
check_json "a row that names its project is taller" "$(bridge --state)" '.sidebarGeometry.rowInWindow.height' "44"

# From the ink of a real frame: the reading edge, the pill, the truncation.
for i in 1 2 3 4 5; do
  settle 0.4; r=$(shot rows) || true
  state=$(bridge --state); scale=$(printf '%s' "$state" | jq -r .backingScale)
  col=$(printf '%s' "$state" | jq -r '.sidebarGeometry.columnX'); tb=$(printf '%s' "$state" | jq -r .titlebarHeight)
  top=$(printf '%s' "$state" | jq -r '.sidebarGeometry.rowInWindow.top'); h=$(printf '%s' "$state" | jq -r '.sidebarGeometry.rowInWindow.height')
  first_ink=$(python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/rows.png" "$(awk "BEGIN {print int(($top + $h * 0.30) * $scale)}")" 1 | awk -v from="$(awk "BEGIN {print $col * $scale}")" '$1 > from && $3 + $4 + $5 < 500 {print $1; exit}')
  [ -n "$first_ink" ] && break
done
check_json "the frame holds the window and nothing else" "$r" '.windows | length == 1' "true"
# The leftmost ink of a whole line, not of one scanline: a C is widest at its
# middle and narrower at its cap, so slicing two lines at two heights compares
# the curve of a glyph rather than where the label starts.
edge() {  # <from fraction> <to fraction> -> points from the column's edge
  python3 -c '
import sys; sys.path.insert(0, "'"$ROOT"'/harness"); import measure
path, x0, y0, y1, col, scale = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5]), float(sys.argv[6])
left = None
for row, width, px in measure.rows(path, y1):
    if row < y0: continue
    for i, p in enumerate(px[x0:], start=x0):
        if sum(p) < 500:
            left = i if left is None else min(left, i)
            break
if left is None: sys.exit(1)
print(round(left / scale - col))' "$CASE_DIR/shots/rows.png" "$(awk "BEGIN {print int($col * $scale)}")" \
    "$(awk "BEGIN {print int(($top + $h * $1) * $scale)}")" "$(awk "BEGIN {print int(($top + $h * $2) * $scale)}")" "$col" "$scale"
}
t=$(ink "the title's leftmost ink" edge 0.18 0.55); p=$(ink "the subtitle's leftmost ink" edge 0.62 0.92)
check "title and subtitle start on one edge ($t and $p pt in)" "$(awk "BEGIN {print ($t == $p) ? \"one edge\" : \"two\"}")" "one edge"
# Case 42 owns the header-to-title edge and measures it from the titlebar's ink;
# what a second line must not do is push the title back toward the gutter, so the
# edge it established is asserted here rather than measured again.
check "and the title still starts on the reading edge, 25 pt in, not pushed back ($t pt)" "$(awk "BEGIN {print ($t >= 23 && $t <= 27) ? \"held\" : \"moved\"}")" "held"

# The pill around two lines: the air above the title equals the air below the subtitle.
band() {  # first and last row of dark ink inside the selected row, and the pill's extent
  python3 -c '
import sys; sys.path.insert(0, "'"$ROOT"'/harness"); import measure
path, x0, x1, y0, y1, pillx = sys.argv[1], *map(int, sys.argv[2:7])
ink_first = ink_last = pill_first = pill_last = None
for row, width, px in measure.rows(path, y1):
    if row < y0: continue
    if any(sum(p) < 500 for p in px[x0:x1]):
        if ink_first is None: ink_first = row
        ink_last = row
    if sum(px[pillx]) < 760:
        if pill_first is None: pill_first = row
        pill_last = row
if None in (ink_first, pill_first): sys.exit(1)
print(ink_first - pill_first, pill_last - ink_last)' "$CASE_DIR/shots/rows.png" \
    "$(awk "BEGIN {print int(($col + 25) * $scale)}")" "$(awk "BEGIN {print int(($col + 150) * $scale)}")" \
    "$(awk "BEGIN {print int($top * $scale)}")" "$(awk "BEGIN {print int(($top + $h) * $scale)}")" \
    "$(awk "BEGIN {print int(($col + 15) * $scale)}")"; }
pad=$(ink "the selected row's pill" band)
check "the pill holds both lines with the same air above and below ($pad)" "$(printf '%s' "$pad" | awk '{print ($1 - $2 <= 2 && $2 - $1 <= 2) ? "even" : "lopsided"}')" "even"

# A long project name must not shorten the title above it: same title, two projects.
ends() {  # the last dark ink of a title line; 0.30 is the selected row, -0.70 the one above
  python3 "$ROOT/harness/measure.py" "$CASE_DIR/shots/rows.png" "$(awk "BEGIN {print int(($top + $h * $1) * $scale)}")" 1 \
    | awk -v from="$(awk "BEGIN {print ($col + 25) * $scale}")" -v to="$(awk "BEGIN {print ($col + 230) * $scale}")" '$1 > from && $1 < to && $3 + $4 + $5 < 500 {last = $2} END {if (last) print last}'; }
short_end=$(ink "the title above the short project name" ends 0.30)
long_end=$(ink "the title above the long project name" ends -0.70)
check "the same title truncates at the same x whatever the project is called ($short_end vs $long_end)" "$(awk "BEGIN {d = $short_end - $long_end; print (d <= 2 && d >= -2) ? \"same\" : \"moved\"}")" "same"
snap subtitle "The project as a subtitle, in All"
kill "$waiter" 2>/dev/null
finish
