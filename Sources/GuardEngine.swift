import Foundation
import Combine

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let text: String
    var line: String { "\(timeFormatter.string(from: date))  \(text)" }
}

final class GuardEngine: ObservableObject {
    @Published private(set) var wifi = WiFiMonitor.Info()
    @Published private(set) var clash = ClashStatus()
    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var alerting = false

    let store = ConfigStore.shared
    let wifiMonitor = WiFiMonitor()
    let clashMonitor = ClashMonitor()

    private var attempts: [Date] = []
    private var cooldownUntil = Date.distantPast
    private var lastActionAt = Date.distantPast
    private var alertedSSID: String?
    private var cancellables = Set<AnyCancellable>()
    private let logURL: URL

    init() {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logURL = dir.appendingPathComponent("ClashSSIDGuard.log")
    }

    func start() {
        clashMonitor.onChange = { [weak self] s in
            guard let self = self else { return }
            self.clash = s
            self.addLog("Clash：\(s.headline)\(s.proxyDetail.map { "，系统代理 \($0)" } ?? "")\(s.tunDetail.map { "，TUN \($0)" } ?? "")")
            self.evaluate()
        }
        wifiMonitor.onChange = { [weak self] i in
            guard let self = self else { return }
            self.wifi = i
            self.addLog("Wi-Fi：\(i.connected ? (i.ssid ?? "已连接（读不到名称）") : (i.powerOn ? "未连接" : "已关闭"))")
            self.evaluate()
        }
        clashMonitor.start()
        wifiMonitor.start()
        clash = clashMonitor.status
        wifi = wifiMonitor.info
        addLog("启动。Wi-Fi：\(wifi.ssid ?? "无")，Clash：\(clash.headline)")

        // 配置变化（例如把当前网络加进名单）立即重新判断。
        store.$config.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.evaluate() }
        }.store(in: &cancellables)

        evaluate()
    }

    func isHit(_ ssid: String, _ cfg: Config) -> Bool {
        let inList = cfg.ssids.contains(ssid)
        return cfg.mode == .blacklist ? inList : !inList
    }

    func evaluate() {
        let cfg = store.config
        guard cfg.enabled else { setAlerting(false); return }
        guard clash.active, wifi.connected else { alertedSSID = nil; setAlerting(false); return }
        guard let ssid = wifi.ssid else { return }   // 读不到 SSID：无法判断，界面会提示定位权限
        guard isHit(ssid, cfg) else { alertedSSID = nil; setAlerting(false); return }
        setAlerting(true)

        let now = Date()
        if now < cooldownUntil { return }
        if now.timeIntervalSince(lastActionAt) < 2 { return }   // 同一次连接会触发多个事件

        if cfg.autoDisconnect {
            attempts = attempts.filter { now.timeIntervalSince($0) < 60 }
            if attempts.count >= 4 {
                cooldownUntil = now.addingTimeInterval(60)
                addLog("「\(ssid)」60 秒内被重连 4 次，暂停处理 60 秒")
                notify("反复重连「\(ssid)」", "Clash 仍开着，系统一直在自动重连。已暂停处理 60 秒，请手动处理。", cfg)
                return
            }
            attempts.append(now)
            lastActionAt = now
            let result = wifiMonitor.disconnect(ssid: ssid, forget: cfg.forgetNetwork)
            addLog("命中「\(ssid)」且 Clash 开启：\(result)")
            notify("已断开「\(ssid)」", "Clash 开启时不允许连接这个网络。\(result)", cfg)
        } else if alertedSSID != ssid {
            alertedSSID = ssid
            addLog("命中「\(ssid)」且 Clash 开启：仅提醒")
            notify("当前网络「\(ssid)」在名单里", "Clash 正在开启。请关闭 Clash 或手动断开 Wi-Fi。", cfg)
        }
    }

    func addCurrentSSID() {
        if let s = wifi.ssid { store.add(s) }
    }

    func refreshAll() {
        clashMonitor.refresh()
        wifiMonitor.refresh()
    }

    private func setAlerting(_ v: Bool) { if alerting != v { alerting = v } }

    private func notify(_ title: String, _ body: String, _ cfg: Config) {
        if cfg.notify { Notifier.post(title: title, body: body) }
    }

    func addLog(_ text: String) {
        let e = LogEntry(text: text)
        log.append(e)
        if log.count > 60 { log.removeFirst(log.count - 60) }
        if let data = (e.line + "\n").data(using: .utf8) {
            if let h = try? FileHandle(forWritingTo: logURL) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: logURL)
            }
        }
    }
}
