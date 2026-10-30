import Foundation
import ServiceManagement

final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    @Published private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    @Published private(set) var error: String?

    var isOn: Bool { status == .enabled || status == .requiresApproval }

    var note: String {
        if Demo.on { return "已开启" }
        switch status {
        case .enabled: return "已开启"
        case .requiresApproval: return "需要在 系统设置 → 通用 → 登录项 里允许"
        case .notRegistered: return "未开启"
        case .notFound: return "找不到应用，请先把应用放进 ~/Applications 再试"
        @unknown default: return "未知状态"
        }
    }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }

    func reload() { status = SMAppService.mainApp.status }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
