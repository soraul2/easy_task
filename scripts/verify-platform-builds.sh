#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_root="${TMPDIR:-/tmp}/PlanBaseBuildVerification"

cd "$repo_root"

git diff --check
swift test
swift test -c release

for configuration in Debug Release; do
  xcodebuild -quiet \
    -project PlanBase.xcodeproj \
    -scheme PlanBase-iOS \
    -configuration "$configuration" \
    -sdk iphonesimulator \
    -derivedDataPath "$derived_root/iOS-$configuration" \
    CODE_SIGNING_ALLOWED=NO \
    build

  xcodebuild -quiet \
    -project PlanBase.xcodeproj \
    -scheme PlanBase-macOS \
    -configuration "$configuration" \
    -derivedDataPath "$derived_root/macOS-$configuration" \
    CODE_SIGNING_ALLOWED=NO \
    build
done
