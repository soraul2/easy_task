#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_root="$(mktemp -d "${TMPDIR:-/tmp}/PlanBaseBuildVerification.XXXXXX")"

cleanup() {
  rm -rf -- "$derived_root"
}

verify_embedded_widget() {
  local widget_path="$1"
  local expected_bundle_identifier="$2"
  local bundle_contents="$widget_path"

  if [[ ! -d "$widget_path" ]]; then
    print -u2 "Missing embedded widget: $widget_path"
    exit 1
  fi

  if [[ -d "$widget_path/Contents" ]]; then
    bundle_contents="$widget_path/Contents"
  fi

  local info_plist="$bundle_contents/Info.plist"
  if [[ ! -f "$info_plist" ]]; then
    print -u2 "Missing embedded widget Info.plist: $info_plist"
    exit 1
  fi

  local actual_bundle_identifier
  actual_bundle_identifier="$(/usr/libexec/PlistBuddy \
    -c "Print :CFBundleIdentifier" \
    "$info_plist" 2>/dev/null || true)"
  if [[ "$actual_bundle_identifier" != "$expected_bundle_identifier" ]]; then
    print -u2 \
      "Unexpected embedded widget bundle ID: $actual_bundle_identifier (expected $expected_bundle_identifier)"
    exit 1
  fi

  local executable_name
  executable_name="$(/usr/libexec/PlistBuddy \
    -c "Print :CFBundleExecutable" \
    "$info_plist" 2>/dev/null || true)"
  local executable_path="$widget_path/$executable_name"
  if [[ -d "$bundle_contents/MacOS" ]]; then
    executable_path="$bundle_contents/MacOS/$executable_name"
  fi
  if [[ -z "$executable_name" || ! -f "$executable_path" ]]; then
    print -u2 "Missing embedded widget executable: $executable_path"
    exit 1
  fi
}

trap cleanup EXIT

cd "$repo_root"

git diff --check
swift test --scratch-path "$derived_root/SwiftPM"
swift test --scratch-path "$derived_root/SwiftPM" -c release

for configuration in Debug Release; do
  xcodebuild -quiet \
    -project PlanBase.xcodeproj \
    -scheme PlanBase-iOS \
    -configuration "$configuration" \
    -sdk iphonesimulator \
    -derivedDataPath "$derived_root/iOS-$configuration" \
    CODE_SIGNING_ALLOWED=NO \
    build

  ios_widget_path="$derived_root/iOS-$configuration/Build/Products/$configuration-iphonesimulator/PlanBase.app/PlugIns/PlanBaseWidgetExtension.appex"
  verify_embedded_widget "$ios_widget_path" "com.soraul2.easytask.widget"

  xcodebuild -quiet \
    -project PlanBase.xcodeproj \
    -scheme PlanBase-macOS \
    -configuration "$configuration" \
    -derivedDataPath "$derived_root/macOS-$configuration" \
    CODE_SIGNING_ALLOWED=NO \
    build

  macos_widget_path="$derived_root/macOS-$configuration/Build/Products/$configuration/PlanBase.app/Contents/PlugIns/PlanBaseWidgetExtension.appex"
  macos_widget_bundle_identifier="com.soraul2.easytask.widget"
  if [[ "$configuration" == "Debug" ]]; then
    macos_widget_bundle_identifier="com.soraul2.easytask.macos.widget"
  fi
  verify_embedded_widget "$macos_widget_path" "$macos_widget_bundle_identifier"
done
