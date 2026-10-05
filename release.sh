#!/bin/sh
# Publishes the version in .claude-plugin/plugin.json as a GitHub release,
# which is where the plugin's SessionStart hook downloads the app from.
set -e
cd "$(dirname "$0")"
version="$(plutil -extract version raw -o - .claude-plugin/plugin.json)"
tag="v$version"

[ -z "$(git status --porcelain)" ] || { echo "the tree is not clean" >&2; exit 1; }
git fetch -q --tags origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "HEAD is not origin/main: commit and push first" >&2; exit 1; }
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null || [ -n "$(git ls-remote --tags origin "refs/tags/$tag")" ]; then
  echo "$tag exists: bump the version in .claude-plugin/plugin.json, commit and push" >&2; exit 1
fi

# The plugin's hooks and install/stop-hook.json must stay the same list.
normalize='.hooks |= (with_entries(.value |= (map(.hooks |= map(select(.command | contains("plugin-ensure") | not) | .command |= sub(".*/bin/bridge"; "bridge"))) | map(select(.hooks | length > 0)))))'
[ "$(jq -S "$normalize" hooks/hooks.json)" = "$(jq -S . install/stop-hook.json)" ] || { echo "hooks/hooks.json and install/stop-hook.json differ" >&2; exit 1; }

zip=build.noindex/bridge.zip
./scripts/package.sh "$zip"
previous="$(git describe --tags --abbrev=0 2>/dev/null || true)"
if [ -n "$previous" ]; then notes="$(git log --format='- %s' "$previous..HEAD")"; else notes="First release"; fi
gh release create "$tag" "$zip" --target "$(git rev-parse HEAD)" --title "$tag" --notes "$notes"
git fetch -q --tags origin
