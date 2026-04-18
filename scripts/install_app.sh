#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ApSwitcher"
BUNDLE_ID="dev.cgomez.apswitcher"
SOURCE_APP="$ROOT_DIR/dist/${APP_NAME}.app"
TARGET_APP="/Applications/${APP_NAME}.app"
OPEN_AFTER_INSTALL=1
RESET_PERMISSIONS=0
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

usage() {
  cat <<EOF
Usage: ./scripts/install_app.sh [--reset-permissions] [--no-open]

Options:
  --reset-permissions  Reset Accessibility and Screen Recording for ${BUNDLE_ID}
  --no-open            Install without opening the app afterwards
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reset-permissions)
      RESET_PERMISSIONS=1
      ;;
    --no-open)
      OPEN_AFTER_INSTALL=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Missing source app at $SOURCE_APP" >&2
  echo "Run ./scripts/build_app.sh first." >&2
  exit 1
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
rm -rf "$TARGET_APP"
/usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$TARGET_APP" >/dev/null 2>&1 || true
fi

if [[ "$RESET_PERMISSIONS" == "1" ]]; then
  tccutil reset Accessibility "$BUNDLE_ID" || true
  tccutil reset ScreenCapture "$BUNDLE_ID" || true
fi

if [[ "$OPEN_AFTER_INSTALL" == "1" ]]; then
  open -n "$TARGET_APP"
fi

echo "Installed $TARGET_APP"
