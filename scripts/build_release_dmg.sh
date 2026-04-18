#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ApSwitcher"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
VERSION="${APSWITCHER_VERSION:-}"
BUILD_NUMBER="${APSWITCHER_BUILD_NUMBER:-1}"
SIGN_IDENTITY="${APSWITCHER_SIGN_IDENTITY:-}"
EXPECTED_TEAM_ID="${APSWITCHER_EXPECTED_TEAM_ID:-3EUA8SZ453}"
NOTARY_KEY_ID="${APPLE_NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${APPLE_NOTARY_ISSUER_ID:-}"
NOTARY_API_KEY_PATH="${APPLE_NOTARY_API_KEY_PATH:-}"

if [[ -z "$VERSION" ]]; then
  if git -C "$ROOT_DIR" describe --tags --exact-match >/dev/null 2>&1; then
    VERSION="$(git -C "$ROOT_DIR" describe --tags --exact-match | sed 's/^v//')"
  else
    VERSION="0.1.0"
  fi
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "APSWITCHER_SIGN_IDENTITY is required for release dmg builds." >&2
  exit 1
fi

mkdir -p "$RELEASE_DIR"

APP_ZIP_PATH="$RELEASE_DIR/${APP_NAME}-${VERSION}.zip"
TMP_DMG_PATH="$RELEASE_DIR/${APP_NAME}-${VERSION}-temp.dmg"
FINAL_DMG_PATH="$RELEASE_DIR/${APP_NAME}-${VERSION}.dmg"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/apswitcher-release.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
  rm -f "$TMP_DMG_PATH" "$APP_ZIP_PATH"
}
trap cleanup EXIT

submit_for_notarization() {
  local artifact_path="$1"

  if [[ -z "$NOTARY_KEY_ID" || -z "$NOTARY_ISSUER_ID" || -z "$NOTARY_API_KEY_PATH" ]]; then
    echo "Skipping notarization for $artifact_path because notary credentials are incomplete."
    return 1
  fi

  xcrun notarytool submit \
    "$artifact_path" \
    --key "$NOTARY_API_KEY_PATH" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" \
    --wait
}

export APSWITCHER_VERSION="$VERSION"
export APSWITCHER_BUILD_NUMBER="$BUILD_NUMBER"
export APSWITCHER_SIGN_IDENTITY="$SIGN_IDENTITY"
export APSWITCHER_EXPECTED_TEAM_ID="$EXPECTED_TEAM_ID"
export APSWITCHER_ENABLE_HARDENED_RUNTIME=1
export APSWITCHER_ENABLE_TIMESTAMP=1

"$ROOT_DIR/scripts/build_app.sh"

if /usr/bin/codesign -dv "$APP_DIR" 2>&1 | grep -q "Signature=adhoc"; then
  echo "Release app build fell back to ad-hoc signing. Aborting." >&2
  exit 1
fi

ditto -c -k --keepParent "$APP_DIR" "$APP_ZIP_PATH"
if submit_for_notarization "$APP_ZIP_PATH"; then
  xcrun stapler staple -v "$APP_DIR"
fi

cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  "$TMP_DMG_PATH" >/dev/null

hdiutil convert \
  "$TMP_DMG_PATH" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$FINAL_DMG_PATH" >/dev/null

/usr/bin/codesign --force --sign "$SIGN_IDENTITY" --timestamp "$FINAL_DMG_PATH" >/dev/null 2>&1 || true

if submit_for_notarization "$FINAL_DMG_PATH"; then
  xcrun stapler staple -v "$FINAL_DMG_PATH"
fi

echo "Built release artifact $FINAL_DMG_PATH"
