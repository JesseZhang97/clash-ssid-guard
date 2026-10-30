import Foundation
import CoreWLAN
import CoreLocation
import AppKit

final class WiFiMonitor: NSObject, CWEventDelegate, CLLocationManagerDelegate {
    struct Info: Equatable {
        var interfaceName: String? = nil
        var powerOn = false
        var connected = false
        var ssid: String? = nil
        /// 已连接但读不到 SSID，通常是没有定位授权。
        var needsLocation: Bool { connected && ssid == nil }
    }

    var onChange: ((Info) -> Void)?
    private(set) var info = Info()
    private let client = CWWiFiClient.shared()
    private let location = CLLocationManager()
    private var timer: Timer?

    // MARK: 采集

    static func readInfo(_ client: CWWiFiClient = CWWiFiClient.shared()) -> Info {
        var info = Info()
        guard let i = client.interface() else { return info }
        info.interfaceName = i.interfaceName
        info.powerOn = i.powerOn()
        guard info.powerOn else { return info }
        var ssid = i.ssid()
        if ssid?.isEmpty == true { ssid = nil }
        let associated = ssid != nil || i.rssiValue() != 0
        info.connected = associated
        if associated, ssid == nil, let name = i.interfaceName {
            ssid = ssidFromIpconfig(name)
        }
        info.ssid = ssid
        return info
    }

    /// 备用读取方式（尽力而为，新系统上可能被隐藏）。
    private static func ssidFromIpconfig(_ iface: String) -> String? {
        let r = runCommand("/usr/sbin/ipconfig", ["getsummary", iface])
        guard r.status == 0 else { return nil }
        for raw in r.output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("SSID : ") {
                let v = String(line.dropFirst("SSID : ".count))
                return (v.isEmpty || v == "<redacted>") ? nil : v
            }
        }
        return nil
    }

    // MARK: 监听

    func start() {
        client.delegate = self
        try? client.startMonitoringEvent(with: .ssidDidChange)
        try? client.startMonitoringEvent(with: .linkDidChange)
        try? client.startMonitoringEvent(with: .powerDidChange)
        location.delegate = self
        requestLocationIfNeeded()
        info = Self.readInfo(client)

        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func requestLocationIfNeeded() {
        if location.authorizationStatus == .notDetermined {
            NSApp.activate(ignoringOtherApps: true)
            location.requestWhenInUseAuthorization()
        }
    }

    var locationStatusText: String {
        switch location.authorizationStatus {
        case .notDetermined: return "尚未授权"
        case .denied: return "已拒绝"
        case .restricted: return "受限制"
        default: return "已授权"
        }
    }

    var locationAuthorized: Bool {
        switch location.authorizationStatus {
        case .notDetermined, .denied, .restricted: return false
        default: return true
        }
    }

    func refresh() {
        let new = Self.readInfo(client)
        if new != info {
            info = new
            onChange?(new)
        }
    }

    // MARK: CWEventDelegate（回调线程不固定，统一回到主线程）

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    // MARK: 断开

    /// 返回一行结果说明，用于日志。
    func disconnect(ssid: String, forget: Bool) -> String {
        guard let iface = client.interface(), let name = iface.interfaceName else { return "没有找到 Wi-Fi 接口" }
        var notes: [String] = []
        if forget {
            let r = runCommand("/usr/sbin/networksetup", ["-removepreferredwirelessnetwork", name, ssid])
            notes.append(r.status == 0 ? "已忘记网络" : "忘记网络失败（\(r.output.isEmpty ? "需要管理员权限" : r.output)）")
        }
        iface.disassociate()
        notes.append("已断开")
        return notes.joined(separator: "，")
    }
}
