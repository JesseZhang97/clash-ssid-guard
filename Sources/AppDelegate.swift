import AppKit
import Combine
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    let engine = GuardEngine()
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)
            return
        }
        buildMainMenu()
        if Notifier.available { UNUserNotificationCenter.current().delegate = self }
        Notifier.setup()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        engine.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }.store(in: &cancellables)
        engine.store.$config.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }.store(in: &cancellables)

        engine.start()
        updateIcon()
        // 第一次运行没有名单也没有定位授权，直接打开设置窗口引导。
        if engine.store.config.ssids.isEmpty || !engine.wifiMonitor.locationAuthorized {
            SettingsWindow.shared.show(engine: engine)
        }
    }

    // 没有 Edit 菜单时，设置窗口里的输入框不能用 ⌘V，所以补一个最小主菜单。
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 Clash SSID Guard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        NSApp.mainMenu = main
    }

    // MARK: 图标

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let cfg = engine.store.config
        let symbol: String
        var tint: NSColor? = nil
        var tip: String
        if !cfg.enabled {
            symbol = "shield.slash"; tip = "防护已暂停"
        } else if engine.alerting {
            symbol = "exclamationmark.shield.fill"; tint = .systemRed; tip = "当前网络命中名单，Clash 已开启"
        } else if engine.clash.active {
            symbol = "checkmark.shield.fill"; tip = "Clash 开启，当前网络正常"
        } else {
            symbol = "checkmark.shield"; tip = "Clash 未开启"
        }
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        img?.isTemplate = true
        button.image = img
        button.contentTintColor = tint
        button.toolTip = tip
    }

    // MARK: 菜单

    func menuWillOpen(_ menu: NSMenu) {
        engine.refreshAll()
        LoginItem.shared.reload()
        menu.removeAllItems()
        let cfg = engine.store.config

        let wifiText: String
        let w = engine.wifi
        if !w.powerOn { wifiText = "Wi-Fi：已关闭" }
        else if !w.connected { wifiText = "Wi-Fi：未连接" }
        else { wifiText = "Wi-Fi：\(w.ssid ?? "已连接（需要定位权限）")" }
        menu.addItem(info(wifiText))

        var clashText = "Clash：\(engine.clash.headline)"
        if let p = engine.clash.proxyDetail { clashText += "（\(p)）" }
        else if let t = engine.clash.tunDetail { clashText += "（TUN \(t)）" }
        menu.addItem(info(clashText))
        menu.addItem(info("名单：\(cfg.mode.title)，\(cfg.ssids.count) 个"))
        menu.addItem(.separator())

        let enable = NSMenuItem(title: "启用防护", action: #selector(toggleEnabled), keyEquivalent: "")
        enable.target = self
        enable.state = cfg.enabled ? .on : .off
        menu.addItem(enable)

        if let cur = w.ssid, !cfg.ssids.contains(cur) {
            let add = NSMenuItem(title: "把「\(cur)」加入名单", action: #selector(addCurrent), keyEquivalent: "")
            add.target = self
            menu.addItem(add)
        }

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let login = NSMenuItem(title: "开机自启", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.shared.isOn ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func info(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    @objc private func toggleEnabled() { engine.store.config.enabled.toggle() }
    @objc private func addCurrent() { engine.addCurrentSSID() }
    @objc private func openSettings() { SettingsWindow.shared.show(engine: engine) }

    @objc private func toggleLogin() {
        let login = LoginItem.shared
        login.set(!login.isOn)
        if let e = login.error {
            let a = NSAlert()
            a.messageText = "无法设置开机自启"
            a.informativeText = e
            a.runModal()
        }
    }

    // MARK: 通知

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
