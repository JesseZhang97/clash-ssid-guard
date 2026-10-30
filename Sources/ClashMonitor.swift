import Foundation
import AppKit
import SystemConfiguration
import Darwin

struct ClashStatus: Equatable {
    var proxyDetail: String? = nil   // 本机系统代理，例如 "HTTP 127.0.0.1:7890"
    var tunDetail: String? = nil     // TUN 接口，例如 "utun1 198.18.0.1"
    var processName: String? = nil   // 正在运行的 Clash/Mihomo 进程

    var proxyOn: Bool { proxyDetail != nil }
    var tunOn: Bool { tunDetail != nil }
    var appRunning: Bool { processName != nil }
    /// "Clash 开启" = 系统代理指向本机，或者存在 Clash 的 TUN 接口。
    var active: Bool { proxyOn || tunOn }

    var headline: String {
        if active { return "开启" }
        if appRunning { return "已运行，未接管流量" }
        return "未开启"
    }
}

final class ClashMonitor {
    var onChange: ((ClashStatus) -> Void)?
    private(set) var status = ClashStatus()
    private var store: SCDynamicStore?
    private var timer: Timer?
    private var pending = false

    // MARK: 采集

    static func snapshot() -> ClashStatus {
        ClashStatus(proxyDetail: proxyInfo(), tunDetail: tunInfo(), processName: clashProcess())
    }

    private static func proxyInfo() -> String? {
        guard let d = SCDynamicStoreCopyProxies(nil) as? [String: Any] else { return nil }
        func isLocal(_ h: String) -> Bool { ["127.0.0.1", "localhost", "::1", "0.0.0.0"].contains(h) }
        let kinds: [(String, String, String, String)] = [
            ("HTTPEnable", "HTTPProxy", "HTTPPort", "HTTP"),
            ("HTTPSEnable", "HTTPSProxy", "HTTPSPort", "HTTPS"),
            ("SOCKSEnable", "SOCKSProxy", "SOCKSPort", "SOCKS"),
        ]
        var parts: [String] = []
        for (en, host, port, label) in kinds {
            if (d[en] as? Int ?? 0) == 1, let h = d[host] as? String, isLocal(h) {
                parts.append("\(label) \(h):\(d[port] as? Int ?? 0)")
            }
        }
        if (d["ProxyAutoConfigEnable"] as? Int ?? 0) == 1,
           let u = d["ProxyAutoConfigURLString"] as? String,
           u.contains("127.0.0.1") || u.contains("localhost") {
            parts.append("PAC")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Clash/Mihomo 的 TUN 默认地址在 198.18.0.0/15。
    private static func tunInfo() -> String? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
        defer { freeifaddrs(ifap) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        let base: UInt32 = (198 << 24) | (18 << 16)
        while let cur = p {
            let ifa = cur.pointee
            p = ifa.ifa_next
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("utun"),
                  (ifa.ifa_flags & UInt32(IFF_UP)) != 0,
                  let addr = ifa.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let sin = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            let ip = UInt32(bigEndian: sin.sin_addr.s_addr)
            if (ip >> 17) == (base >> 17) {
                return "\(name) \(ip >> 24).\((ip >> 16) & 255).\((ip >> 8) & 255).\(ip & 255)"
            }
        }
        return nil
    }

    private static func clashProcess() -> String? {
        let me = getpid()
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(n) + 64)
        let got = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        guard got > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: 256)
        for i in 0..<min(got, pids.count) {
            let pid = pids[i]
            if pid <= 0 || pid == me { continue }
            buf[0] = 0
            if proc_name(pid, &buf, UInt32(buf.count)) <= 0 { continue }
            let name = String(cString: buf)
            let low = name.lowercased()
            if low.contains("guard") || low.contains("clashgate") { continue }   // 排除自己（含旧名字）
            if low.contains("clash") || low.contains("mihomo") { return name }
        }
        return nil
    }

    // MARK: 监听

    func start() {
        status = Self.snapshot()

        var ctx = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                        retain: nil, release: nil, copyDescription: nil)
        store = SCDynamicStoreCreate(nil, "ClashGate" as CFString, { _, _, info in
            guard let info = info else { return }
            let me = Unmanaged<ClashMonitor>.fromOpaque(info).takeUnretainedValue()
            me.scheduleRefresh()
        }, &ctx)
        if let store = store {
            let keys = ["State:/Network/Global/Proxies", "State:/Network/Global/IPv4"] as CFArray
            let patterns = ["State:/Network/Interface/.*/IPv4", "Setup:/Network/Global/.*"] as CFArray
            SCDynamicStoreSetNotificationKeys(store, keys, patterns)
            SCDynamicStoreSetDispatchQueue(store, DispatchQueue.main)
        }

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.scheduleRefresh() }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.scheduleRefresh() }

        // 兜底：每 30 秒校验一次（进程检测和 TUN 变化不一定有事件）。
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 合并短时间内的多次事件。
    private func scheduleRefresh() {
        if pending { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.pending = false
            self?.refresh()
        }
    }

    func refresh() {
        let s = Self.snapshot()
        if s != status {
            status = s
            onChange?(s)
        }
    }
}
