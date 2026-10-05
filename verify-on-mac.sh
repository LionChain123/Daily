#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "需要 macOS 和完整 Xcode；Windows Swift 无法编译 SwiftUI / UIKit。" >&2
  exit 1
fi
if ! xcrun --find xcodebuild >/dev/null 2>&1; then
  echo "未找到 Xcode，请先安装并选择完整 Xcode 开发目录。" >&2
  exit 1
fi
mkdir -p verification
swiftc DailyGrowth/Models.swift tests/ModelTests.swift -o verification/ModelTests
verification/ModelTests 2>&1 | tee verification/model-tests.log
xcodebuild -version | tee verification/xcode-version.txt
xcodebuild -project DailyGrowth.xcodeproj -scheme DailyGrowth \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -configuration Debug -derivedDataPath verification/DerivedData \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee verification/build.log
echo "模型测试和模拟器目标编译成功。请在 Xcode 中启动模拟器检查交互与布局。"
