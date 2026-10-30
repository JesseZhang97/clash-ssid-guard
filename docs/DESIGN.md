# 设计说明

## 目标

Clash 开启时，不允许 Mac 停留在名单里的 Wi-Fi 上。macOS 没有“连接前拦截”的公开接口，所以方案是连上后立刻断开。

## 模块

| 文件 | 作用 |
| --- | --- |
| `Sources/main.swift` | 入口；`--status` 调试输出；其余情况启动菜单栏应用（accessory 模式，没有 Dock 图标） |
| `Sources/AppDelegate.swift` | 菜单栏图标和菜单、四种托盘状态、主菜单（让输入框支持 ⌘V）、演示模式 |
| `Sources/GuardEngine.swift` | 把 Clash 状态、Wi-Fi 状态和配置合在一起判断，执行断开、通知、防重连循环，写日志 |
| `Sources/ClashMonitor.swift` | 检测 Clash：系统代理、TUN 接口、Clash 进程。用 `SCDynamicStore` 监听系统代理和网络变化 |
| `Sources/WiFiMonitor.swift` | 用 CoreWLAN 读 SSID、监听 Wi-Fi 事件、读已知网络、断开；管理定位授权 |
| `Sources/Config.swift` | 配置的读写（JSON）、旧版本配置迁移 |
| `Sources/SettingsView.swift` | SwiftUI 设置窗口和“选择 Wi-Fi 名单”窗口 |
| `Sources/LoginItem.swift` | 用 `SMAppService` 管理开机自启 |
| `Sources/Notifier.swift` | 系统通知 |
| `Sources/Demo.swift` | 截图用的示例数据 |

## 事件和判断流程

1. `ClashMonitor` 和 `WiFiMonitor` 在状态变化时回调 `GuardEngine`。它们都是事件驱动，不轮询。
2. `GuardEngine.evaluate()` 依次检查：防护已开启；Clash 开启；Wi-Fi 已连接；读得到 SSID；SSID 命中名单。任何一步不满足就清除告警并返回。
3. 命中后设置告警状态（图标变红）。
4. 开启“自动断开”时：先检查 60 秒内的断开次数。到 4 次就暂停处理 60 秒并通知，否则调用 `disassociate()`，再按设置决定是否忘记该网络，最后发通知。
5. 没开“自动断开”时只通知一次，同一个网络不重复通知。

同一次连接会触发多个事件，所以两次处理之间至少间隔 2 秒。

## Clash 开启的定义

- 系统代理（HTTP、HTTPS 或 SOCKS）指向 127.0.0.1 或 localhost。
- 存在 TUN 接口：名称以 `utun` 开头，且地址在 198.18.0.0/15。
- 进程名包含 `clash` 或 `mihomo`，只用来显示“已运行”，不算开启。应用自己的进程（名称含 `ClashGate`）会被排除。

## 托盘图标

图标在 `Resources/tray/`，每种状态一张 18 px 加一张 36 px（@2x）。

- 正常、开启、暂停是单色模板图片（`isTemplate = true`），跟随菜单栏的浅色或深色。
- 告警图标自带红色，不是模板图片。
- 四种状态的优先级：已暂停，告警，Clash 开启，Clash 未开启。

应用图标的源文件在 `Resources/AppIcon.iconset/`，构建时用系统自带的 `iconutil` 生成 `.icns`。

## 隐私

- 所有处理都在本机，没有网络请求，没有统计。
- 配置只有名单和几个开关，日志只记录状态变化和处理结果。
- 日志和配置里会有你的 Wi-Fi 名称，所以不要把它们发到公开的地方。

## 已知问题和后续想法

- ad-hoc 签名下，每次重新构建后定位授权可能失效。用固定的开发者证书可以避免。
- “忘记网络”需要管理员权限，普通用户下常会失败。
- 可以考虑加一个“Clash 开启时才阻止自动加入”的更细策略，目前不支持。
