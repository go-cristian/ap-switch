#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ApSwitcher"
BUNDLE_ID="dev.cgomez.apswitcher"
APP_VERSION="${APSWITCHER_VERSION:-0.1.0}"
APP_BUILD_NUMBER="${APSWITCHER_BUILD_NUMBER:-1}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SIGN_IDENTITY="${APSWITCHER_SIGN_IDENTITY:-}"
EXPECTED_TEAM_ID="${APSWITCHER_EXPECTED_TEAM_ID:-3EUA8SZ453}"
ENABLE_HARDENED_RUNTIME="${APSWITCHER_ENABLE_HARDENED_RUNTIME:-0}"
ENABLE_TIMESTAMP="${APSWITCHER_ENABLE_TIMESTAMP:-0}"
PREFERRED_IDENTITIES=(
  "AC1D9AC4DE9FD9251DF14AC42742F3E68081D2A2"
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
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD_NUMBER}</string>
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
CODESIGN_EXTRA_ARGS=()

if [[ "$ENABLE_HARDENED_RUNTIME" == "1" ]]; then
  CODESIGN_EXTRA_ARGS+=(--options runtime)
fi

if [[ "$ENABLE_TIMESTAMP" == "1" ]]; then
  CODESIGN_EXTRA_ARGS+=(--timestamp)
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  SIGN_CANDIDATES+=("$SIGN_IDENTITY")
else
  for preferred_identity in "${PREFERRED_IDENTITIES[@]}"; do
    if grep -q "$preferred_identity" <<<"$AVAILABLE_IDENTITIES"; then
      SIGN_CANDIDATES+=("$preferred_identity")
    fi
  done
fi

SIGNED_APP=0
for candidate in "${SIGN_CANDIDATES[@]}"; do
  CODESIGN_CMD=(/usr/bin/codesign --force --deep --sign "$candidate" --identifier "$BUNDLE_ID")
  if [[ "${#CODESIGN_EXTRA_ARGS[@]}" -gt 0 ]]; then
    CODESIGN_CMD+=("${CODESIGN_EXTRA_ARGS[@]}")
  fi
  CODESIGN_CMD+=("$APP_DIR")

  if "${CODESIGN_CMD[@]}" >/dev/null 2>&1; then
    echo "Signed with $candidate"
    SIGNED_APP=1
    break
  fi
done

if [[ "$SIGNED_APP" -eq 0 ]]; then
  /usr/bin/codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_DIR" >/dev/null
  echo "Signed ad-hoc"
else
  TEAM_ID="$(
    /usr/bin/codesign -dv --verbose=4 "$APP_DIR" 2>&1 |
    awk -F= '/^TeamIdentifier=/ { print $2; exit }'
  )"

  if [[ "$TEAM_ID" != "$EXPECTED_TEAM_ID" ]]; then
    echo "Signed app team identifier '$TEAM_ID' does not match expected '$EXPECTED_TEAM_ID'." >&2
    exit 1
  fi
fi

echo "Built $APP_DIR"
