#!/bin/bash
# Runs every case in harness/cases (or the ones named on the command line) and
# prints one line per case. Builds and bundles first unless NOBUILD=1.
cd "$(dirname "$0")/.."
if [ -z "$NOBUILD" ]; then
  scripts/bundle.sh >/dev/null || { echo "build failed"; exit 1; }
  . scripts/developer-dir.sh
  swift test 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Test run with|failed" | sed 's/^/  /'
  if ! swift test >/dev/null 2>&1; then echo "unit tests failed"; exit 1; fi
fi
mkdir -p harness/out
# A case by name ("01-spine") or by path.
if [ $# -gt 0 ]; then cases=$(for c in "$@"; do [ -f "$c" ] && echo "$c" || ls harness/cases/"$c"*.sh; done); else cases=$(ls harness/cases/*.sh); fi
total=0; failed=0
for c in $cases; do
  total=$((total + 1))
  echo "== $(basename "$c" .sh)"
  if ! bash "$c"; then failed=$((failed + 1)); fi
done
echo
if [ "$failed" = 0 ]; then echo "All $total cases passed."; else echo "$failed of $total cases failed."; exit 1; fi
