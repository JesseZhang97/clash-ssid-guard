import AppKit
import Combine
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    let engine = GuardEngine()
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !Demo.on, let id = Bundle.main.bundleIdentifier,
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
        if Demo.on { runDemo(); return }
        // 第一次运行没有名单也没有定位授权，直接打开设置窗口引导。
        if engine.store.config.ssids.isEmpty {
            KnownNetworksWindow.shared.show(engine: engine)   // 直接弹出已知网络列表
        }
        if !engine.wifiMonitor.locationAuthorized {
            SettingsWindow.shared.show(engine: engine)
        }
    }

    /// 截图用：打开设置窗口和已知网络窗口，把窗口编号写到 CLASHGATE_DEMO_OUT，然后点开菜单栏菜单。
    private func runDemo() {
        let out = ProcessInfo.processInfo.environment["CLASHGATE_DEMO_OUT"] ?? NSTemporaryDirectory()
        SettingsWindow.shared.show(engine: engine)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            SettingsWindow.shared.window?.setContentSize(NSSize(width: 500, height: 1060))
            SettingsWindow.shared.window?.setFrameTopLeftPoint(NSPoint(x: 60, y: NSScreen.main!.visibleFrame.maxY - 20))
            KnownNetworksWindow.shared.show(engine: self.engine)
            KnownNetworksWindow.shared.window?.setFrameTopLeftPoint(NSPoint(x: 640, y: NSScreen.main!.visibleFrame.maxY - 20))
        }
        // 用应用自己的绘制结果存成 PNG，不需要“屏幕录制”权限。
        func snap(_ w: NSWindow?, _ name: String) {
            guard let w = w, let v = w.contentView?.superview,
                  let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
        }
        func findScroll(_ v: NSView) -> NSScrollView? {
            if let s = v as? NSScrollView { return s }
            for c in v.subviews { if let s = findScroll(c) { return s } }
            return nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            snap(SettingsWindow.shared.window, "settings-\(Demo.mode ?? "x")-top")
            snap(KnownNetworksWindow.shared.window, "known-networks")
            // 窗口比屏幕高时，滚到底再拍一张，文档里拼接。
            if let sv = SettingsWindow.shared.window?.contentView.flatMap(findScroll), let doc = sv.documentView {
                doc.scroll(NSPoint(x: 0, y: doc.bounds.height))
                if doc.isFlipped == false { doc.scroll(NSPoint(x: 0, y: 0)) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            snap(SettingsWindow.shared.window, "settings-\(Demo.mode ?? "x")-bottom")
            NSApp.terminate(nil)
        }
    }

    // 没有 Edit 菜单时，设置窗口里的输入框不能用 ⌘V，所以补一个最小主菜单。
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 Clash Gate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        let name: String
        let tip: String
        if !cfg.enabled {
            name = "tray-paused"; tip = "防护已暂停"
        } else if engine.alerting {
            name = "tray-alert"; tip = "当前网络命中名单，Clash 已开启"
        } else if engine.clash.active {
            name = "tray-active"; tip = "Clash 开启，当前网络正常"
        } else {
            name = "tray-normal"; tip = "Clash 未开启"
        }
        let img = NSImage(named: name)
        img?.size = NSSize(width: 18, height: 18)
        img?.isTemplate = (name != "tray-alert")   // 告警图标自带红色，其余跟随菜单栏深浅色
        img?.accessibilityDescription = tip
        button.image = img
        button.contentTintColor = nil
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

        let addItem = NSMenuItem(title: "加入名单", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        if let cur = w.ssid, !cfg.ssids.contains(cur) {
            let c = NSMenuItem(title: "加入当前网络「\(cur)」", action: #selector(addNamed(_:)), keyEquivalent: "")
            c.target = self
            c.representedObject = cur
            sub.addItem(c)
            sub.addItem(.separator())
        }
        let candidates = WiFiMonitor.knownNetworks().filter { !cfg.ssids.contains($0) }
        if candidates.isEmpty {
            sub.addItem(info("没有可选的已知网络"))
        } else {
            let head = NSMenuItem(title: "已知网络", action: nil, keyEquivalent: "")
            head.isEnabled = false
            sub.addItem(head)
            for s in candidates {
                let it = NSMenuItem(title: s == w.ssid ? "\(s)（当前）" : s, action: #selector(addNamed(_:)), keyEquivalent: "")
                it.target = self
                it.representedObject = s
                sub.addItem(it)
            }
        }
        sub.addItem(.separator())
        let multi = NSMenuItem(title: "多选…", action: #selector(openKnown), keyEquivalent: "")
        multi.target = self
        sub.addItem(multi)
        addItem.submenu = sub
        menu.addItem(addItem)

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
    @objc private func addNamed(_ sender: NSMenuItem) { if let s = sender.representedObject as? String { engine.store.add(s) } }
    @objc private func openKnown() { KnownNetworksWindow.shared.show(engine: engine) }
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
