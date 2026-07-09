#!/bin/zsh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_root="${TMPDIR:-/tmp}/EasyTaskBuildVerification"

cd "$repo_root"

git diff --check
swift test

xcodebuild -quiet \
  -project EasyTask.xcodeproj \
  -scheme EasyTask-iOS \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath "$derived_root/iOS" \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild -quiet \
  -project EasyTask.xcodeproj \
  -scheme EasyTask-macOS \
  -configuration Debug \
  -derivedDataPath "$derived_root/macOS" \
  CODE_SIGNING_ALLOWED=NO \
  build
