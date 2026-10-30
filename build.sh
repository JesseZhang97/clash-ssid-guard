#!/bin/bash
# 只需要 Command Line Tools（xcode-select --install），不需要打开 Xcode。
set -euo pipefail
cd "$(dirname "$0")"

APP="build/ClashGate.app"
ARCH="$(uname -m)"
SIGN_ID="${SIGN_ID:--}"   # 默认 ad-hoc 签名；有开发者证书时：SIGN_ID="Apple Development: xxx" ./build.sh

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target "${ARCH}-apple-macos13.0" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/ClashGate"

cp Resources/Info.plist "$APP/Contents/Info.plist"
# 应用图标（iconutil 是系统自带的，不需要 Xcode）和托盘图标
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/tray/*.png "$APP/Contents/Resources/"
codesign --force --deep --sign "$SIGN_ID" "$APP"

echo "构建完成：$(pwd)/$APP"
