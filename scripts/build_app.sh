#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ApSwitcher"
BUNDLE_ID="com.iyubinest.apswitcher"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SIGN_IDENTITY="${APSWITCHER_SIGN_IDENTITY:-}"
PREFERRED_IDENTITIES=(
  "AC1D9AC4DE9FD9251DF14AC42742F3E68081D2A2"
  "A10CC0F02D9D1B12E6014F7C8F2AA45CDE39F1F9"
)

cd "$ROOT_DIR"

swift build -c release --product "$APP_NAME" >/dev/null
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

/usr/bin/touch "$APP_DIR"

AVAILABLE_IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
SIGN_CANDIDATES=()

if [[ -n "$SIGN_IDENTITY" ]]; then
  SIGN_CANDIDATES+=("$SIGN_IDENTITY")
else
  for preferred_identity in "${PREFERRED_IDENTITIES[@]}"; do
    if grep -q "$preferred_identity" <<<"$AVAILABLE_IDENTITIES"; then
      SIGN_CANDIDATES+=("$preferred_identity")
    fi
  done

  FALLBACK_IDENTITY="$(awk -F'"' '/Apple Development:/ { print $2; exit }' <<<"$AVAILABLE_IDENTITIES")"
  if [[ -n "$FALLBACK_IDENTITY" ]]; then
    SIGN_CANDIDATES+=("$FALLBACK_IDENTITY")
  fi
fi

SIGNED_APP=0
for candidate in "${SIGN_CANDIDATES[@]}"; do
  if /usr/bin/codesign --force --deep --sign "$candidate" --identifier "$BUNDLE_ID" "$APP_DIR" >/dev/null 2>&1; then
    echo "Signed with $candidate"
    SIGNED_APP=1
    break
  fi
done

if [[ "$SIGNED_APP" -eq 0 ]]; then
  /usr/bin/codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_DIR" >/dev/null
  echo "Signed ad-hoc"
fi

echo "Built $APP_DIR"
