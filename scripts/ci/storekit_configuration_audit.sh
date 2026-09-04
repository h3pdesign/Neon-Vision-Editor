#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STOREKIT_FILE="$ROOT/Neon Vision Editor/SupportOptional.storekit"
SETTINGS_FILE="$ROOT/Neon Vision Editor/UI/NeonSettingsView.swift"
PURCHASE_MANAGER_FILE="$ROOT/Neon Vision Editor/Data/SupportPurchaseManager.swift"
EXPECTED_REFERENCE='identifier = "../../Neon Vision Editor/SupportOptional.storekit"'
EXPECTED_PRODUCT_ID="002420160"

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ -f "$STOREKIT_FILE" ]] || fail "Missing StoreKit configuration: $STOREKIT_FILE"
python3 -m json.tool "$STOREKIT_FILE" >/dev/null || fail "StoreKit configuration is not valid JSON."

product_id="$(plutil -extract products.0.productID raw "$STOREKIT_FILE")"
product_type="$(plutil -extract products.0.type raw "$STOREKIT_FILE")"
display_price="$(plutil -extract products.0.displayPrice raw "$STOREKIT_FILE")"

[[ "$product_id" == "$EXPECTED_PRODUCT_ID" ]] || fail "Unexpected support product ID: $product_id"
[[ "$product_type" == "Consumable" ]] || fail "Support product must remain consumable."
[[ -n "$display_price" ]] || fail "Support product is missing a local test price."
grep -Fq "static let supportProductID = \"$EXPECTED_PRODUCT_ID\"" "$PURCHASE_MANAGER_FILE" || \
  fail "SupportPurchaseManager product ID does not match the StoreKit configuration."

python3 - "$SETTINGS_FILE" "$PURCHASE_MANAGER_FILE" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
anchor = '.onChange(of: settingsActiveTab)'
if anchor not in source:
    raise SystemExit("error: Missing settings-tab change handler.")
handler = source.split(anchor, 1)[1].split('.onChange(of: moreSectionTab)', 1)[0]
ios_branch = handler.split('#elseif os(iOS)', 1)[1].split('#else', 1)[0]
if 'newValue == "support"' not in ios_branch or 'refreshSupportStoreStateIfNeeded()' not in ios_branch:
    raise SystemExit("error: Selecting Support on iOS must refresh StoreKit state.")
vision_branch = handler.split('#if os(visionOS)', 1)[1].split('#elseif', 1)[0]
if 'newValue == "support"' not in vision_branch or 'refreshSupportStoreStateIfNeeded()' not in vision_branch:
    raise SystemExit("error: Selecting Support on visionOS must refresh StoreKit state.")
manager = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
if 'Support purchase is currently unavailable on visionOS.' in manager:
    raise SystemExit("error: Support purchases must not be disabled on visionOS.")
PY

for scheme in \
  "$ROOT/Neon Vision Editor.xcodeproj/xcshareddata/xcschemes/Neon Vision Editor.xcscheme" \
  "$ROOT/Neon Vision Editor.xcodeproj/xcshareddata/xcschemes/Neon Vision Editor AppStore.xcscheme"; do
  [[ -f "$scheme" ]] || fail "Missing shared scheme: $scheme"
  grep -Fq "$EXPECTED_REFERENCE" "$scheme" || \
    fail "$(basename "$scheme") does not activate SupportOptional.storekit for Run."
done

echo "StoreKit configuration audit passed for product $EXPECTED_PRODUCT_ID."
