#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

INFO_PLIST="Neon Vision Editor App Clip/Info.plist"
APP_CLIP_ENTITLEMENTS="Neon Vision Editor App Clip/Neon Vision Editor App Clip.entitlements"
PARENT_IOS_ENTITLEMENTS="Neon Vision Editor/Neon Vision Editor iOS.entitlements"
CARD_PNG="release/app-store/appclip/neon-vision-editor-app-clip-card.png"
CARD_JPG="release/app-store/appclip/neon-vision-editor-app-clip-card.jpg"
APP_CLIP_DOMAIN="${NVE_APP_CLIP_DOMAIN:-apps-h3p.com}"
APP_CLIP_BUNDLE_ID="${NVE_APP_CLIP_BUNDLE_ID:-h3p.Neon-Vision-Editor.Clip}"

echo "[appclip-preflight] checking App Clip metadata and card assets"

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "[appclip-preflight] missing required file: $path" >&2
    exit 1
  fi
}

require_plist_value() {
  local plist="$1"
  local key="$2"
  local expected="$3"
  local value
  value="$(plutil -extract "$key" raw -o - "$plist" 2>/dev/null || true)"
  if [[ "$value" != "$expected" ]]; then
    echo "[appclip-preflight] $plist must set $key to $expected; found '${value:-<missing>}'" >&2
    exit 1
  fi
}

require_sips_value() {
  local image="$1"
  local key="$2"
  local expected="$3"
  local value
  value="$(sips -g "$key" "$image" 2>/dev/null | awk -F ': ' -v key="$key" '$1 ~ key {print $2; exit}')"
  if [[ "$value" != "$expected" ]]; then
    echo "[appclip-preflight] $image must have $key=$expected; found '${value:-<missing>}'" >&2
    exit 1
  fi
}

check_card_asset() {
  local image="$1"
  require_file "$image"
  require_sips_value "$image" "pixelWidth" "1800"
  require_sips_value "$image" "pixelHeight" "1200"
  require_sips_value "$image" "space" "RGB"
  require_sips_value "$image" "hasAlpha" "no"
}

check_available_card_assets() {
  local checked=0
  if [[ -f "$CARD_PNG" ]]; then
    check_card_asset "$CARD_PNG"
    checked=1
  fi
  if [[ -f "$CARD_JPG" ]]; then
    check_card_asset "$CARD_JPG"
    checked=1
  fi
  if [[ "$checked" -eq 0 ]]; then
    echo "[appclip-preflight] missing App Clip card asset; expected ${CARD_PNG} or ${CARD_JPG}" >&2
    exit 1
  fi
}

require_file "$INFO_PLIST"
require_file "$APP_CLIP_ENTITLEMENTS"
require_file "$PARENT_IOS_ENTITLEMENTS"
require_plist_value "$INFO_PLIST" "CFBundleIconName" "AppIcon-iOS"

if ! plutil -p "$APP_CLIP_ENTITLEMENTS" | grep -q "appclips:${APP_CLIP_DOMAIN}"; then
  echo "[appclip-preflight] App Clip entitlements must include appclips:${APP_CLIP_DOMAIN}" >&2
  exit 1
fi

if ! plutil -p "$PARENT_IOS_ENTITLEMENTS" | grep -q "$APP_CLIP_BUNDLE_ID"; then
  echo "[appclip-preflight] parent iOS entitlements must include $APP_CLIP_BUNDLE_ID" >&2
  exit 1
fi

check_available_card_assets

echo "[appclip-preflight] OK"
