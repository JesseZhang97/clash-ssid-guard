import AppKit

// 调试用：`ClashSSIDGuard --status` 打印当前 Clash 和 Wi-Fi 状态后退出。
if CommandLine.arguments.contains("--status") {
    let c = ClashMonitor.snapshot()
    let w = WiFiMonitor.readInfo()
    print("clash.active=\(c.active)")
    print("clash.proxy=\(c.proxyDetail ?? "-")")
    print("clash.tun=\(c.tunDetail ?? "-")")
    print("clash.process=\(c.processName ?? "-")")
    print("wifi.power=\(w.powerOn)")
    print("wifi.connected=\(w.connected)")
    print("wifi.ssid=\(w.ssid ?? "-")")
    print("wifi.needsLocation=\(w.needsLocation)")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
