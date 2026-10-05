#!/bin/sh
# Run by the plugin's SessionStart hook: installs the app, the CLI and the
# toolkit of the plugin's own version, so the skill and the app always match.
# Silent and quick when up to date, and never fails the session.
# BRIDGE_PREFIX replaces $HOME for every install path; BRIDGE_RELEASE_URL
# replaces the release zip (a URL or a file path).
root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(plutil -extract version raw -o - "$root/.claude-plugin/plugin.json" 2>/dev/null)" || exit 0
prefix="${BRIDGE_PREFIX:-$HOME}"
share="$prefix/.local/share/bridge"

has_node() { command -v node >/dev/null && command -v npm >/dev/null; }
if [ "$(cat "$share/VERSION" 2>/dev/null)" = "$version" ]; then
  # A Node installed after Bridge still gets its toolkit.
  ! has_node || [ -d "$share/toolkit/node_modules" ] && exit 0
fi

mkdir -p "$share" || exit 0
# Sessions that start together must not swap the same app at once. A lock
# older than ten minutes belongs to a run that was killed.
lock="$share/.ensure.lock"
find "$lock" -maxdepth 0 -mmin +10 -exec rmdir {} \; 2>/dev/null
mkdir "$lock" 2>/dev/null || exit 0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"; rmdir "$lock"' EXIT
trap 'exit 0' INT TERM HUP

update() {
  set -e
  url="${BRIDGE_RELEASE_URL:-https://github.com/medienbaecker/bridge/releases/download/v$version/bridge.zip}"
  echo "installing Bridge $version from $url"
  if [ -f "$url" ]; then cp "$url" "$tmp/bridge.zip"; else curl -fsSL -o "$tmp/bridge.zip" "$url"; fi
  ditto -x -k "$tmp/bridge.zip" "$tmp"
  new="$tmp/bridge"
  [ "$(cat "$new/VERSION")" = "$version" ] || { echo "the zip holds $(cat "$new/VERSION"), not $version"; exit 1; }
  codesign --verify "$new/Bridge.app"
  "$new/bridge" --help >/dev/null

  # Never write over a running Mach-O in place: the Stop hook keeps the old
  # CLI running for hours. Copy, then rename.
  mkdir -p "$prefix/Applications" "$prefix/.local/bin" "$share/toolkit"
  app="$prefix/Applications/Bridge.app"
  rm -rf "$app.new" "$app.old"
  cp -R "$new/Bridge.app" "$app.new"
  [ -d "$app" ] && mv "$app" "$app.old"
  mv "$app.new" "$app"
  rm -rf "$app.old"
  cp "$new/bridge" "$share/cli-stable.new"
  mv -f "$share/cli-stable.new" "$share/cli-stable"
  ln -sfn "$share/cli-stable" "$prefix/.local/bin/bridge"

  cp "$new"/toolkit/* "$share/toolkit/"
  if has_node; then
    (cd "$share/toolkit" && npm install --silent --no-audit --no-fund && node build.mjs vendor)
  fi
  echo "$version" > "$share/VERSION"
  echo "done"
}

( update ) > "$share/ensure.log" 2>&1
exit 0
