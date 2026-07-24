#!/bin/zsh

set -euo pipefail

archive_path="${1:-}"
expected_app_group="group.com.soraul2.easytask"
expected_cloud_container="iCloud.com.soraul2.easytask"

if [[ -z "$archive_path" ]]; then
  print -u2 "usage: $0 <PlanBase-iOS.xcarchive>"
  exit 64
fi

app_path="$archive_path/Products/Applications/PlanBase.app"
widget_path="$app_path/PlugIns/PlanBaseWidgetExtension.appex"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/PlanBaseEntitlements.XXXXXX")"

trap 'rm -rf -- "$temporary_directory"' EXIT

verify_bundle() {
  local bundle_path="$1"
  local entitlement_path="$2"

  if [[ ! -d "$bundle_path" ]]; then
    print -u2 "Missing signed bundle: $bundle_path"
    exit 1
  fi

  codesign --verify --strict "$bundle_path"
  codesign -d --entitlements :- "$bundle_path" >"$entitlement_path" 2>/dev/null
  plutil -lint "$entitlement_path" >/dev/null
}

entitlement_value() {
  local entitlement_path="$1"
  local key="$2"
  local index="${3:-0}"

  /usr/libexec/PlistBuddy \
    -c "Print :$key:$index" \
    "$entitlement_path" \
    2>/dev/null
}

app_entitlements="$temporary_directory/app.plist"
widget_entitlements="$temporary_directory/widget.plist"

verify_bundle "$app_path" "$app_entitlements"
verify_bundle "$widget_path" "$widget_entitlements"

app_group="$(entitlement_value \
  "$app_entitlements" \
  "com.apple.security.application-groups" || true)"
widget_app_group="$(entitlement_value \
  "$widget_entitlements" \
  "com.apple.security.application-groups" || true)"
cloud_container="$(entitlement_value \
  "$app_entitlements" \
  "com.apple.developer.icloud-container-identifiers" || true)"

if [[ "$app_group" != "$expected_app_group" ]]; then
  print -u2 "App Group entitlement mismatch for PlanBase.app: ${app_group:-missing}"
  exit 1
fi

if [[ "$widget_app_group" != "$expected_app_group" ]]; then
  print -u2 "App Group entitlement mismatch for widget: ${widget_app_group:-missing}"
  exit 1
fi

if [[ "$cloud_container" != "$expected_cloud_container" ]]; then
  print -u2 "CloudKit container entitlement mismatch: ${cloud_container:-missing}"
  exit 1
fi

print "Verified signed iOS archive entitlements:"
print "  app group: $app_group"
print "  widget app group: $widget_app_group"
print "  CloudKit container: $cloud_container"
