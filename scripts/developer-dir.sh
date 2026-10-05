if [ -z "$DEVELOPER_DIR" ]; then
  DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
  case "$DEVELOPER_DIR" in ""|/Library/Developer/CommandLineTools*)
    for x in /Applications/Xcode-beta.app /Applications/Xcode.app; do
      [ -d "$x" ] && { DEVELOPER_DIR="$x/Contents/Developer"; break; }
    done;;
  esac
  export DEVELOPER_DIR
fi
