#!/bin/bash
# Installing the skill takes back what an earlier install of ours left behind:
# a step that only copies and never deletes leaves stale files in the skill
# directory, where an agent still reads them. A manifest and not a sweep: the
# directory is the user's, and the installer may only take away what it put there.
source "$(dirname "$0")/../lib.sh"
dest="$CASE_DIR/skills"
skill() { "$ROOT/scripts/install-skill.sh" "$dest"; }
ships=$(cd "$ROOT/skills/bridge" && ls *.md | sort | tr '\n' ' ')

skill >/dev/null
check "a first install places what this version ships" "$(cd "$dest" && ls *.md | sort | tr '\n' ' ')" "$ships"

# An earlier version of ours shipped a file this one does not, and the user has left a
# note of their own beside it. One of those is the installer's to take back.
printf '# the old vocabulary\n.page {}\n' > "$dest/patterns.md"
printf '# my own notes\n' > "$dest/my-notes.md"
printf 'patterns.md\n' >> "$dest/.installed"
sort -o "$dest/.installed" "$dest/.installed"

skill >/dev/null
check "a file an earlier install left, and this one does not ship, is taken back" "$([ -e "$dest/patterns.md" ] && echo there || echo gone)" "gone"
check "a file of the user's own, which no manifest names, is left alone" "$(cat "$dest/my-notes.md")" "# my own notes"
check "everything this version ships is still there" "$(cd "$dest" && ls *.md | grep -v my-notes | sort | tr '\n' ' ')" "$ships"

# A downgrade: the manifest names what a newer version shipped. Removing those is
# right, and it can never reach a file this version ships, because the manifest
# it writes is exactly that list.
printf 'from-a-newer-version.md\n' >> "$dest/.installed"
sort -o "$dest/.installed" "$dest/.installed"
printf 'x\n' > "$dest/from-a-newer-version.md"
skill >/dev/null
check "downgrading takes back what only the newer version shipped" "$([ -e "$dest/from-a-newer-version.md" ] && echo there || echo gone)" "gone"
finish
