#!/bin/sh
# Builds one flavour into build.noindex/: --beta (default), --stable or --dev,
# plus --release for a release build. The .noindex suffix keeps Spotlight and
# app launchers from indexing build output.
set -e
cd "$(dirname "$0")"
. scripts/developer-dir.sh
FLAVOR=beta; CONFIG=debug
for arg in "$@"; do case "$arg" in --stable) FLAVOR=stable;; --beta) FLAVOR=beta;; --dev) FLAVOR=dev;; --release) CONFIG=release;; esac; done
case "$FLAVOR" in
  stable) NAME="Bridge";      CLI=bridge;      ID=com.medienbaecker.bridge.app;  ICON=bridge;;
  beta)   NAME="Bridge Beta"; CLI=bridge-beta; ID=com.medienbaecker.bridge.beta; ICON=bridge-beta;;
  dev)    NAME="Bridge Dev"; CLI=bridge-dev; ID=com.medienbaecker.bridge-dev; ICON=bridge-beta;;
esac
VERSION="$(plutil -extract version raw -o - .claude-plugin/plugin.json)"
EXE="$(printf '%s' "$NAME" | tr -d ' ')"

swift build -c "$CONFIG" 2>&1 | grep -E "error:|Build complete" | sed 's/\x1b\[[0-9;]*m//g' || true
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
test -x "$BIN/Bridge" || { echo "build failed"; exit 1; }

APP="build.noindex/$NAME.app"; RES="$APP/Contents/Resources"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$RES"
cp "$BIN/Bridge" "$APP/Contents/MacOS/$EXE"
cp -R "$BIN/bridge_Bridge.bundle" "$RES/"
cp "$BIN/bridge-cli" "build.noindex/$CLI"

# Warnings go to stderr because run.sh discards this script's stdout.
if [ -d "assets/$ICON.icon" ]; then
  said="$(xcrun actool "assets/$ICON.icon" --compile "$RES" --platform macosx --minimum-deployment-target 13.0 \
    --app-icon "$ICON" --include-all-app-icons --output-partial-info-plist /dev/null 2>&1)" || echo "warning: actool failed for $ICON: $said" >&2
  test -s "$RES/Assets.car" || echo "warning: no Assets.car was produced for $ICON: $said" >&2
else
  echo "warning: no icon package at assets/$ICON.icon, so the bundle gets none" >&2
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$EXE</string>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIconFile</key><string>$ICON</string>
  <key>CFBundleIconName</key><string>$ICON</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key><true/>
    <key>NSExceptionDomains</key>
    <dict>
      <key>test</key><dict><key>NSIncludesSubdomains</key><true/><key>NSExceptionAllowsInsecureHTTPLoads</key><true/></dict>
      <key>localhost</key><dict><key>NSIncludesSubdomains</key><true/><key>NSExceptionAllowsInsecureHTTPLoads</key><true/></dict>
    </dict>
  </dict>
</dict>
</plist>
PLIST

# Prefer a real identity: macOS refuses notifications to an ad-hoc signed app.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')"
codesign --force --sign "${IDENTITY:--}" "$APP" >/dev/null 2>&1
echo "$APP  (cli: build.noindex/$CLI, signed: ${IDENTITY:-ad-hoc})"
