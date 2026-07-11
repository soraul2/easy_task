#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_root="${TMPDIR:-/tmp}/EasyTaskBuildVerification"

cd "$repo_root"

git diff --check
swift test
swift test -c release

for configuration in Debug Release; do
  xcodebuild -quiet \
    -project EasyTask.xcodeproj \
    -scheme EasyTask-iOS \
    -configuration "$configuration" \
    -sdk iphonesimulator \
    -derivedDataPath "$derived_root/iOS-$configuration" \
    CODE_SIGNING_ALLOWED=NO \
    build

  xcodebuild -quiet \
    -project EasyTask.xcodeproj \
    -scheme EasyTask-macOS \
    -configuration "$configuration" \
    -derivedDataPath "$derived_root/macOS-$configuration" \
    CODE_SIGNING_ALLOWED=NO \
    build
done
