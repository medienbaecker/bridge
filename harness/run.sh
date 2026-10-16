#!/bin/bash
# Runs every case in harness/cases (or the ones named on the command line) and
# prints one line per case. Builds and bundles first unless NOBUILD=1.
cd "$(dirname "$0")/.."
if [ -z "$NOBUILD" ]; then
  scripts/bundle.sh >/dev/null || { echo "build failed"; exit 1; }
  . scripts/developer-dir.sh
  tests=$(swift test 2>&1); ok=$?
  printf '%s\n' "$tests" | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Test run with|failed" | sed 's/^/  /'
  if [ $ok != 0 ]; then echo "unit tests failed"; exit 1; fi
fi
mkdir -p harness/out
export BRIDGE_SCREEN="${BRIDGE_SCREEN-Test Screen}"
if [ -n "$BRIDGE_SCREEN" ] && command -v betterdisplaycli >/dev/null && betterdisplaycli set -name="$BRIDGE_SCREEN" -connected=on >/dev/null 2>&1; then
  trap 'betterdisplaycli set -name="$BRIDGE_SCREEN" -connected=off >/dev/null 2>&1' EXIT
  sleep 2
fi
# A case by name ("01-spine") or by path.
if [ $# -gt 0 ]; then cases=$(for c in "$@"; do [ -f "$c" ] && echo "$c" || ls harness/cases/"$c"*.sh; done); else cases=$(ls harness/cases/*.sh); fi
logs=harness/out/.logs; rm -rf "$logs"; mkdir -p "$logs"
printf '%s\n' $cases | xargs -P "${JOBS:-4}" -I{} /bin/bash -c 'bash "$1" > "$2/$(basename "$1" .sh).log" 2>&1' _ {} "$logs"
total=0; failed=0
for c in $cases; do
  total=$((total + 1))
  echo "== $(basename "$c" .sh)"
  cat "$logs/$(basename "$c" .sh).log"
  grep -q "^PASS" "$logs/$(basename "$c" .sh).log" || failed=$((failed + 1))
done
echo
if [ "$failed" = 0 ]; then echo "All $total cases passed."; else echo "$failed of $total cases failed."; exit 1; fi
