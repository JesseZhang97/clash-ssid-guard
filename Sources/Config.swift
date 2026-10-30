import Foundation
import Combine

enum ListMode: String, Codable, CaseIterable, Identifiable {
    case blacklist, whitelist
    var id: String { rawValue }
    var title: String { self == .blacklist ? "黑名单" : "白名单" }
    var explain: String {
        self == .blacklist
            ? "只处理名单里的网络：Clash 开启且连上名单里的 Wi-Fi 时，提醒并断开。"
            : "只放行名单里的网络：Clash 开启且连上不在名单里的 Wi-Fi 时，提醒并断开。"
    }
}

struct Config: Codable, Equatable {
    var mode: ListMode = .blacklist
    var ssids: [String] = []
    var enabled = true
    var autoDisconnect = true
    var forgetNetwork = false
    var notify = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(ListMode.self, forKey: .mode) ?? .blacklist
        ssids = try c.decodeIfPresent([String].self, forKey: .ssids) ?? []
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        autoDisconnect = try c.decodeIfPresent(Bool.self, forKey: .autoDisconnect) ?? true
        forgetNetwork = try c.decodeIfPresent(Bool.self, forKey: .forgetNetwork) ?? false
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? true
    }
}

final class ConfigStore: ObservableObject {
    static let shared = ConfigStore()

    @Published var config: Config {
        didSet { if config != oldValue { save() } }
    }

    let url: URL

    private init() {
        if Demo.on {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("clashgate-demo.json")
            config = Demo.config
            return
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ClashGate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("config.json")
        // 从旧名字（ClashSSIDGuard）迁移配置。
        let old = base.appendingPathComponent("ClashSSIDGuard/config.json")
        if !FileManager.default.fileExists(atPath: file.path), FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.copyItem(at: old, to: file)
        }
        url = file
        if let data = try? Data(contentsOf: file), let c = try? JSONDecoder().decode(Config.self, from: data) {
            config = c
        } else {
            config = Config()
        }
    }

    private func save() {
        if Demo.on { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(config) { try? data.write(to: url, options: .atomic) }
    }

    func add(_ ssid: String) {
        let s = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !config.ssids.contains(s) else { return }
        config.ssids.append(s)
    }

    func remove(_ ssid: String) {
        config.ssids.removeAll { $0 == ssid }
    }
}
