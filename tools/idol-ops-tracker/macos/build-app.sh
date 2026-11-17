#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
TRACKER_ROOT=${SCRIPT_DIR:h}
APP_DIR="$TRACKER_ROOT/dist/IDOL Ops Control.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PYTHON_BIN=$(command -v python3)
BUILD_DIR="$SCRIPT_DIR/.build/release"
MODULE_CACHE="$SCRIPT_DIR/.build/module-cache"
BINARY_PATH="$BUILD_DIR/IDOLOpsWidget"

"$PYTHON_BIN" -c 'import yaml' >/dev/null
mkdir -p "$BUILD_DIR" "$MODULE_CACHE"
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" /usr/bin/clang \
  -fobjc-arc \
  -fmodules \
  -fmodules-cache-path="$MODULE_CACHE" \
  -mmacosx-version-min=13.0 \
  -O2 \
  "$SCRIPT_DIR/Sources/IDOLOpsWidget/main.m" \
  -framework AppKit \
  -framework WebKit \
  -o "$BINARY_PATH"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY_PATH" "$MACOS_DIR/IDOLOpsWidget"
cp "$SCRIPT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
printf '%s\n' "$TRACKER_ROOT" > "$RESOURCES_DIR/tracker-root.txt"
printf '%s\n' "$PYTHON_BIN" > "$RESOURCES_DIR/python-path.txt"
chmod 755 "$MACOS_DIR/IDOLOpsWidget"
/usr/bin/codesign --force --deep --sign - "$APP_DIR"

print -r -- "$APP_DIR"
