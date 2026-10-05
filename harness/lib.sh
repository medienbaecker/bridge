# Shared harness for tests/cases/*.sh. Each case runs in its own subshell with
# its own state dir and its own copies of the fixtures it uses.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/harness/out"
CASE_NAME="${CASE_NAME:-$(basename "${BASH_SOURCE[1]}" .sh)}"
CASE_DIR="$OUT/$CASE_NAME"
rm -rf "$CASE_DIR"
mkdir -p "$CASE_DIR/state" "$CASE_DIR/pages" "$CASE_DIR/shots"
export XDG_STATE_HOME="$CASE_DIR/state"
export BRIDGE_TEST=1
export BRIDGE_DEV_APP="$ROOT/build.noindex/Bridge Dev.app"
export BRIDGE_SESSION="test-$CASE_NAME"
FAILS=0
CHECKS=0

bridge() { "$ROOT/build.noindex/bridge-dev" "$@"; }
# A page's record in the app's store; a sidecar beside the page is copied in on first touch.
sidecar() { bridge --sidecar "$1"; }

fixture() {
  local name="$1" as="${2:-$1}"
  cp "$ROOT/harness/fixtures/$name" "$CASE_DIR/pages/$as"
  echo "$CASE_DIR/pages/$as"
}

# A fresh repo around the pages so project grouping and ground have something real.
repo() {
  (cd "$CASE_DIR/pages" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm "fixtures" 2>/dev/null)
}

wait_ready() {
  local i
  for i in $(seq 1 100); do
    if [ "$(bridge --state 2>/dev/null | jq -r '.ready // false')" = "true" ]; then return 0; fi
    sleep 0.05
  done
  fault "timed out waiting for the page to be ready"
  return 1
}

settle() { sleep "${1:-0.2}"; }

# A fault found inside a command substitution, where an assignment to FAILS is
# made in a subshell and lost and a message on stdout is captured into the
# caller's variable instead of printed. The file survives both; finish() folds
# it in, so a measurement cannot fail quietly on its way to a comparison.
fault() {
  echo "  noted: $1" >&2
  echo "$1" >> "$CASE_DIR/faults"
}

# A real-window photograph (`--shot`), as opposed to the offscreen composite (`snap`).
# A frame that is not the window makes every measurement taken from it meaningless,
# whatever the measurement says: another display's scale, a window left out of the
# capture, a frame cut by the display's edge. None of it is the case's subject, so
# none of it is a verdict about the drawing.
shot() {
  local r; r=$(bridge --shot "$CASE_DIR/shots/$1.png") || { fault "shot $1 was refused"; return 1; }
  if [ "$(printf '%s' "$r" | jq -r '.scale')" != "$(bridge --state | jq -r '.backingScale')" ]; then
    fault "shot $1 came from a display at another scale: $(printf '%s' "$r" | jq -c '{scale, display}')"; return 1
  fi
  if [ "$(printf '%s' "$r" | jq -r '(.missing | length == 0) and (.clipped | not)')" != true ]; then
    fault "shot $1 is not the window: $(printf '%s' "$r" | jq -c '{windows, missing, clipped}')"; return 1
  fi
  printf '%s' "$r"
}

# "No ink here" is a fact about the frame, not a number. Compared as a number it
# can return the very verdict the drawing was meant to earn: "same" from 999,
# "plain" from an empty band, "level" from -1 against -1. So an ink measurement
# that comes back empty fails the case where it was taken, whether or not its
# caller remembers.
ink() {  # ink <what is being measured> <command…>
  local what="$1"; shift
  local v; v=$("$@")
  if [ -z "$v" ]; then fault "found no ink for $what, so nothing measured here is about the drawing"; printf 'NOINK'; return 1; fi
  printf '%s' "$v"
}
# Brings the app to the front for a shot of the active state. Takes focus from
# whoever is at the machine, so cases only do it when BRIDGE_FRONT=1.
front() { [ "${BRIDGE_FRONT:-0}" = 1 ] && bridge --do front >/dev/null && sleep 1.5; }

snap() {
  local name="$1"
  bridge --snap "$CASE_DIR/shots/$name.png" >/dev/null
  if [ -n "$SHEET" ]; then
    cp "$CASE_DIR/shots/$name.png" "$SHEET/$(printf '%02d' "$SHEET_N")-$name.png"
    echo "<figure><img src=\"$(printf '%02d' "$SHEET_N")-$name.png\"><figcaption>$SHEET_N. ${2:-$name}</figcaption></figure>" >> "$SHEET/index.html"
    SHEET_N=$((SHEET_N + 1))
  fi
}

# A new check is not finished until it has been watched to fail: revert the fix,
# run the case, confirm it goes red for the reason it names, then put the fix
# back. A check nobody has seen fail is a check nobody has tested.
#
# Before you write `expected [same]`, or [plain], [level], [gone], [one edge]:
# an absence or a sameness asserted from ink is indistinguishable from not
# having looked. Assert something positive, or put a positive control beside the
# absence: a measurement that found nothing must not produce a verdict.
#
# The tally is a file, not a shell variable. Cases run checks inside `( … )` and
# inside functions called as `$( … )`, where an increment happens in a subshell
# and is thrown away with it, so a check there could never fail the case. A file
# survives every subshell there is.
check() {
  local label="$1" actual="$2" expected="$3"
  # These labels carry the numbers they judged, so an unmeasured value shows up
  # here even when the arithmetic around it quietly resolved to the wanted verdict.
  case "$label$actual$expected" in
    *NOINK*) echo "  FAIL $label: judged a value that was never measured"; echo FAIL >> "$CASE_DIR/checks"; return;;
  esac
  if [ "$actual" = "$expected" ]; then
    echo "  ok   $label"
    echo ok >> "$CASE_DIR/checks"
  else
    echo "  FAIL $label: expected [$expected], got [$actual]"
    echo FAIL >> "$CASE_DIR/checks"
  fi
}

check_json() {
  local label="$1" json="$2" expr="$3" expected="$4"
  check "$label" "$(printf '%s' "$json" | jq -r "$expr")" "$expected"
}

finish() {
  bridge --quit >/dev/null 2>&1 || true
  sleep 0.2
  if [ -s "$CASE_DIR/faults" ]; then
    while IFS= read -r f; do echo "  FAIL $f"; echo FAIL >> "$CASE_DIR/checks"; done < "$CASE_DIR/faults"
  fi
  CHECKS=$(grep -c . "$CASE_DIR/checks" 2>/dev/null) || CHECKS=0
  FAILS=$(grep -c FAIL "$CASE_DIR/checks" 2>/dev/null) || FAILS=0
  if [ "$FAILS" = 0 ]; then echo "PASS $CASE_NAME ($CHECKS checks)"; else echo "FAIL $CASE_NAME ($FAILS of $CHECKS checks failed)"; fi
  exit "$FAILS"
}
trap 'bridge --quit >/dev/null 2>&1 || true' EXIT
