#!/bin/sh
# Builds the stable release and zips what plugin-ensure.sh installs.
# Usage: package.sh <out.zip>
set -e
[ -n "$1" ] || { echo "package.sh <out.zip>" >&2; exit 1; }
out="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$(dirname "$0")/.."
./build.sh --stable --release
(cd toolkit && npm ci --silent --no-audit --no-fund && node build.mjs vendor)
stage="build.noindex/release/bridge"
rm -rf "$stage"; mkdir -p "$stage/toolkit/bin"
ditto build.noindex/Bridge.app "$stage/Bridge.app"
cp build.noindex/bridge "$stage/bridge"
cp toolkit/scaffold.jsx toolkit/bridge.js toolkit/theme.css "$stage/toolkit/"
cp toolkit/bin/esbuild "$stage/toolkit/bin/"
ditto toolkit/dist "$stage/toolkit/dist"
plutil -extract version raw -o - .claude-plugin/plugin.json > "$stage/VERSION"
rm -f "$out"
ditto -c -k --norsrc --noextattr --keepParent "$stage" "$out"
echo "$out"
