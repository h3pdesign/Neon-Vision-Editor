#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
if [[ -z "$APP_PATH" || ! -d "$APP_PATH" ]]; then
  echo "Usage: scripts/ci/verify_icon_payload.sh <path-to-.app>" >&2
  exit 1
fi

INFO="$APP_PATH/Contents/Info.plist"
CAR="$APP_PATH/Contents/Resources/Assets.car"

if [[ ! -f "$INFO" ]]; then
  echo "Missing Info.plist at $INFO" >&2
  exit 1
fi

if [[ ! -f "$CAR" ]]; then
  echo "Missing Assets.car at $CAR" >&2
  exit 1
fi

ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$INFO" 2>/dev/null || true)"
if [[ -z "$ICON_NAME" ]]; then
  echo "Missing CFBundleIconName in $INFO." >&2
  exit 1
fi

REQUIRE_ICONSTACK="${REQUIRE_ICONSTACK:-0}"
TMP_JSON="$(mktemp)"
xcrun --sdk macosx assetutil --info "$CAR" > "$TMP_JSON"

if ! grep -Fq "\"Name\" : \"$ICON_NAME\"" "$TMP_JSON"; then
  echo "Missing $ICON_NAME image renditions in Assets.car." >&2
  rm -f "$TMP_JSON"
  exit 1
fi

if ! grep -Fq "\"RenditionName\" : \"$ICON_NAME.iconstack\"" "$TMP_JSON"; then
  if [[ "$REQUIRE_ICONSTACK" == "1" ]]; then
    echo "Missing $ICON_NAME.iconstack rendition in Assets.car (strict mode)." >&2
    rm -f "$TMP_JSON"
    exit 1
  fi
  echo "Warning: $ICON_NAME.iconstack rendition not found; accepting $ICON_NAME image renditions fallback." >&2
fi

rm -f "$TMP_JSON"
echo "Icon payload preflight passed."
