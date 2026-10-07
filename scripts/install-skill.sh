#!/bin/sh
# Copies skills/bridge/*.md into a skill directory and removes files an earlier install
# placed there that this version no longer ships. Usage: install-skill.sh <dir>
#
# A manifest, not a sweep: the directory belongs to the user, and only files
# this installer placed may be removed. A stale file left behind would still
# read as authoritative to an agent.
set -e
export LC_ALL=C
dest="$1"
[ -n "$dest" ] || { echo "install-skill.sh <dir>" >&2; exit 1; }
here="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$dest"

# Copy before removing, so a failure never leaves a shipped file missing.
cp "$here"/skills/bridge/*.md "$dest/"

ships="$dest/.installed.new"
(cd "$here/skills/bridge" && ls *.md) | sort > "$ships"
if [ -f "$dest/.installed" ]; then
  sort "$dest/.installed" | comm -23 - "$ships" | while IFS= read -r gone; do
    [ -n "$gone" ] || continue
    [ -e "$dest/$gone" ] || continue
    rm -f "$dest/$gone"
    echo "  retired $gone: an earlier version installed it and this one does not ship it"
  done
fi
mv -f "$ships" "$dest/.installed"
