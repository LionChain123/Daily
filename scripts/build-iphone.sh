#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p artifacts build
xcodebuild -version | tee artifacts/xcode-version.log
swiftc DailyGrowth/Models.swift tests/ModelTests.swift -o build/ModelTests
build/ModelTests 2>&1 | tee artifacts/model-tests.log
xcodebuild -project DailyGrowth.xcodeproj -scheme DailyGrowth \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build 2>&1 | tee artifacts/xcode-build.log
app="$PWD/build/DerivedData/Build/Products/Release-iphoneos/DailyGrowth.app"
test -f "$app/DailyGrowth"
test -f "$app/Assets.car"
lipo -archs "$app/DailyGrowth" | grep -q arm64
stage=$(mktemp -d "$PWD/build/ipa-stage.XXXXXX")
mkdir -p "$stage/Payload"
ditto "$app" "$stage/Payload/DailyGrowth.app"
ipa="$PWD/artifacts/DailyGrowth-unsigned.ipa"
(cd "$stage" && zip -qry "$ipa" Payload)
unzip -t "$ipa"
echo "IPA created: $ipa (unsigned; requires local signing before installation)"
