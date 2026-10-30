#!/bin/bash
# 打包发布用的 zip：通用二进制，ad-hoc 签名。只需要 Command Line Tools。
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
UNIVERSAL=1 ./build.sh

mkdir -p dist
ZIP="dist/ClashGate-${VERSION}.zip"
rm -f "$ZIP"
# ditto 会保留签名和扩展属性，不要用 zip 命令
ditto -c -k --keepParent build/ClashGate.app "$ZIP"
( cd dist && shasum -a 256 "ClashGate-${VERSION}.zip" > "ClashGate-${VERSION}.zip.sha256" )

echo "已生成：$(pwd)/$ZIP"
cat "dist/ClashGate-${VERSION}.zip.sha256"
