#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PRODUCT_NAME="${PRODUCT_NAME:-Swooshy}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_NAME="${APP_NAME:-$PRODUCT_NAME.app}"
APP_DIR="$DIST_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ZIP_NAME="${ZIP_NAME:-${PRODUCT_NAME}-macOS.zip}"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUNDLE_ID="${BUNDLE_ID:-com.xiamiyu123.swooshy}"
APP_ICON_SOURCE_PATH="${APP_ICON_SOURCE_PATH:-$ROOT_DIR/artwork/app-icon/source.png}"
APP_ICON_PATH="${APP_ICON_PATH:-$ROOT_DIR/artwork/app-icon/AppIcon.icns}"
APP_ICON_BUILD_SCRIPT="${APP_ICON_BUILD_SCRIPT:-$ROOT_DIR/scripts/build-app-icon.sh}"
REQUIRE_APP_ICON="${REQUIRE_APP_ICON:-1}"

echo "[package] Building $PRODUCT_NAME ($BUILD_CONFIGURATION)"
swift build -c "$BUILD_CONFIGURATION" --product "$PRODUCT_NAME"

BIN_DIR="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/$PRODUCT_NAME"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "[package] ERROR: executable not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

RESOURCE_BUNDLE_PATH="$BIN_DIR/${PRODUCT_NAME}_${PRODUCT_NAME}.bundle"
if [[ ! -d "$RESOURCE_BUNDLE_PATH" ]]; then
  RESOURCE_BUNDLE_PATH="$(find "$BIN_DIR" -maxdepth 1 -type d -name "${PRODUCT_NAME}_*.bundle" | head -n 1 || true)"
fi

if [[ -z "$RESOURCE_BUNDLE_PATH" || ! -d "$RESOURCE_BUNDLE_PATH" ]]; then
  echo "[package] ERROR: resource bundle not found in $BIN_DIR" >&2
  exit 1
fi

echo "[package] Creating app bundle at $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$PRODUCT_NAME"
chmod +x "$MACOS_DIR/$PRODUCT_NAME"
cp -R "$RESOURCE_BUNDLE_PATH" "$RESOURCES_DIR/"

ICON_PLIST_SNIPPET=""
if [[ -f "$APP_ICON_SOURCE_PATH" ]]; then
  if [[ -x "$APP_ICON_BUILD_SCRIPT" ]]; then
    echo "[package] Building app icon from $APP_ICON_SOURCE_PATH"
    "$APP_ICON_BUILD_SCRIPT" "$APP_ICON_SOURCE_PATH" "$APP_ICON_PATH"
  elif [[ "$REQUIRE_APP_ICON" == "1" ]]; then
    echo "[package] ERROR: app icon build script is not executable at $APP_ICON_BUILD_SCRIPT" >&2
    exit 1
  else
    echo "[package] WARN: app icon build script is not executable at $APP_ICON_BUILD_SCRIPT" >&2
  fi
fi

if [[ -f "$APP_ICON_PATH" ]]; then
  APP_ICON_FILE_NAME="$(basename "$APP_ICON_PATH")"
  cp "$APP_ICON_PATH" "$RESOURCES_DIR/$APP_ICON_FILE_NAME"
  ICON_PLIST_SNIPPET=$'  <key>CFBundleIconFile</key>\n  <string>'"${APP_ICON_FILE_NAME%.icns}"$'</string>'
elif [[ "$REQUIRE_APP_ICON" == "1" ]]; then
  echo "[package] ERROR: app icon missing. Expected $APP_ICON_PATH" >&2
  echo "[package] ERROR: provide APP_ICON_PATH or APP_ICON_SOURCE_PATH for icon generation" >&2
  exit 1
else
  echo "[package] WARN: app icon missing, packaging without CFBundleIconFile" >&2
fi

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${PRODUCT_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${PRODUCT_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${APP_VERSION}</string>
${ICON_PLIST_SNIPPET}
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

if [[ "${SKIP_CODESIGN:-0}" != "1" ]] && command -v codesign >/dev/null 2>&1; then
  echo "[package] Applying ad-hoc code signature"
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "[package] Creating zip artifact at $ZIP_PATH"
rm -f "$ZIP_PATH"
(
  cd "$DIST_DIR"
  ditto -c -k --keepParent "$APP_NAME" "$ZIP_NAME"
)

echo "[package] Done"
echo "[package] App: $APP_DIR"
echo "[package] Zip: $ZIP_PATH"
