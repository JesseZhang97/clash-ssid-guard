# Clash Gate

(原名 Clash SSID Guard。)

macOS 菜单栏小工具：Clash 开启时，如果当前连接的 Wi-Fi 命中名单，就提醒并断开。

- 原生 Swift（AppKit 菜单栏加 SwiftUI 设置窗口），事件驱动，空闲时几乎不占 CPU。
- 黑名单（默认）：只处理名单里的网络。白名单：处理所有不在名单里的网络。
- 设置窗口可以管理名单、查看 Clash 状态、申请或取消开机自启、看最近记录。

## 构建和安装

只需要 Command Line Tools，不需要打开 Xcode：

```bash
xcode-select --install   # 已经装过就跳过
./install.sh             # 构建、安装到 ~/Applications 并启动
```

只构建：`./build.sh`。调试：`build/ClashGate.app/Contents/MacOS/ClashGate --status`。

## 判断逻辑

- **Clash 开启** = 系统代理指向本机（127.0.0.1 或 localhost），或存在 TUN 接口（utun，地址在 198.18.0.0/15）。只运行 Clash 但没有接管流量，只显示“已运行”，不触发。
- **命中** = 黑名单模式下 SSID 在名单里，或白名单模式下 SSID 不在名单里。
- **动作** = 系统通知；开启“自动断开”时调用 CoreWLAN 的 `disassociate()`。可选“同时忘记该网络”，调用 `networksetup -removepreferredwirelessnetwork`，可能需要管理员权限。
- 60 秒内同一网络被系统重连 4 次，会暂停处理 60 秒并通知。

## 限制

- 无法在连接前拦截，只能连上后立刻断开，断开前设备可能已经拿到 IP。
- 读取 SSID 需要定位权限（macOS 14 起）。首次启动会请求授权。授权被拒绝时，应用能看到“已连接”，但读不到名称，也就无法判断。
- 默认 ad-hoc 签名，重新构建后系统可能要求重新授权定位。可以用 `SIGN_ID` 指定开发者证书。
- 本机系统代理视为 Clash 开启，不区分是不是 Clash。
- 配置文件：`~/Library/Application Support/ClashGate/config.json`，日志：`~/Library/Logs/ClashGate.log`。
