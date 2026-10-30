#!/bin/bash
# 构建并安装到 ~/Applications，然后启动。
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
mkdir -p "$HOME/Applications"
pkill -x ClashSSIDGuard 2>/dev/null || true
rm -rf "$HOME/Applications/ClashSSIDGuard.app"
cp -R build/ClashSSIDGuard.app "$HOME/Applications/"
open "$HOME/Applications/ClashSSIDGuard.app"
echo "已安装并启动：$HOME/Applications/ClashSSIDGuard.app"
