import Foundation

/// 截图和演示用：`CLASHGATE_DEMO=ok|alert` 启动时使用示例数据，
/// 不读也不写真实配置和日志，不读真实 Wi-Fi，也不会断开任何网络。
enum Demo {
    static let mode: String? = ProcessInfo.processInfo.environment["CLASHGATE_DEMO"]
    static var on: Bool { mode != nil }
    static var alert: Bool { mode == "alert" }

    static let blacklist = ["Airport-Free-WiFi", "Hotel-Guest", "Cafe-Public", "Library-Open", "Metro-WiFi", "Coworking-Guest", "Mall-Free"]
    static let known = ["Home-5G", "Office", "Airport-Free-WiFi", "Hotel-Guest", "Cafe-Public", "Library-Open",
                        "Metro-WiFi", "Coworking-Guest", "Mall-Free", "Phone-Hotspot", "Friends-House"]

    static var config: Config {
        var c = Config()
        c.ssids = blacklist
        return c
    }

    static var ssid: String { alert ? "Airport-Free-WiFi" : "Home-5G" }
    static var wifi: WiFiMonitor.Info {
        WiFiMonitor.Info(interfaceName: "en0", powerOn: true, connected: true, ssid: ssid)
    }
    static var clash: ClashStatus {
        ClashStatus(proxyDetail: nil, tunDetail: "utun5 198.18.0.1", processName: "Clash")
    }
}
