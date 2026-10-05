#!/bin/sh
# Installs one flavour: --beta (default) or --stable. Nothing another flavour
# owns is touched.
set -e
cd "$(dirname "$0")"
FLAVOR=beta
for arg in "$@"; do case "$arg" in --stable) FLAVOR=stable;; --beta) FLAVOR=beta;; --dev) FLAVOR=dev;; esac; done
case "$FLAVOR" in
  # Stable and beta share the toolkit but not the CLI binary, so each CLI
  # stays in step with its own app.
  stable) NAME="Bridge";      CLI=bridge;      SHARE="$HOME/.local/share/bridge";;
  beta)   NAME="Bridge Beta"; CLI=bridge-beta; SHARE="$HOME/.local/share/bridge";;
  # An installed CLI or skill without its app would win an agent's match and
  # then fail; the harness runs dev from build.noindex/.
  dev)    echo "the dev flavour is not installed: scripts/bundle.sh builds it into build.noindex/ for the harness" >&2; exit 1;;
esac

echo "building $NAME"
./build.sh "--$FLAVOR" --release >/dev/null

echo "installing the toolkit"
# Copy, never delete: stable and beta share the toolkit, so a file this version
# no longer ships may still be loaded by the other flavour's app. The skill
# directory is per flavour, which is why only it has a manifest.
mkdir -p "$SHARE/toolkit"
cp toolkit/package.json toolkit/build.mjs toolkit/scaffold.jsx toolkit/bridge.js toolkit/theme.css "$SHARE/toolkit/"
(cd "$SHARE/toolkit" && npm install --silent --no-audit --no-fund && node build.mjs vendor)

echo "installing the app and the CLI"
mkdir -p "$HOME/Applications" "$HOME/.local/bin" "$SHARE"
# Never write over a running Mach-O in place: the process is killed on its next
# exec, and the Stop hook keeps the old one running for hours. Copy, then rename.
APP="$HOME/Applications/$NAME.app"
rm -rf "$APP.new" "$APP.old"
cp -R "build.noindex/$NAME.app" "$APP.new"
[ -d "$APP" ] && mv "$APP" "$APP.old"
mv "$APP.new" "$APP"
rm -rf "$APP.old"
codesign --verify "$APP" || { echo "install failed: $APP does not verify" >&2; exit 1; }
# The smoke test runs this file, not whatever `$CLI` on PATH resolves to.
BIN="$SHARE/cli-$FLAVOR"
cp "build.noindex/$CLI" "$BIN.new"
mv -f "$BIN.new" "$BIN"
cmp -s "build.noindex/$CLI" "$BIN" || { echo "install failed: $BIN differs from build.noindex/$CLI" >&2; exit 1; }
"$BIN" --help >/dev/null 2>&1 || { echo "install failed: $BIN does not run (exit $?)" >&2; exit 1; }
ln -sfn "$BIN" "$HOME/.local/bin/$CLI"
# Earlier versions installed one CLI shared by both flavours; remove it once nothing points at it.
if [ -f "$SHARE/cli" ] && [ "$(readlink "$HOME/.local/bin/bridge")" != "$SHARE/cli" ] && [ "$(readlink "$HOME/.local/bin/bridge-beta")" != "$SHARE/cli" ]; then rm -f "$SHARE/cli"; fi

# Only stable installs the skill: a beta skill would compete with it for
# every agent that says "bridge".
if [ "$FLAVOR" != beta ]; then
  echo "installing the skill"
  ./scripts/install-skill.sh "$HOME/.claude/skills/$CLI"
  echo "done: ~/Applications/$NAME.app, ~/.local/bin/$CLI, ~/.claude/skills/$CLI"
else
  echo "done: ~/Applications/$NAME.app, ~/.local/bin/$CLI (no skill for beta; the skill is bridge)"
fi
echo
echo "Not done for you: the Claude Code hooks (Stop, PostToolUse and the session hooks). Merge install/stop-hook.json into"
echo "~/.claude/settings.json; any flavour's CLI serves it, and it watches every flavour's state dir."
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "note: ~/.local/bin is not on your PATH" ;; esac
