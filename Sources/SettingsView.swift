import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var engine: GuardEngine
    @ObservedObject var store: ConfigStore
    @ObservedObject var login = LoginItem.shared
    @State private var newSSID = ""
    @State private var listExpanded = false
    private let collapsedCount = 5

    var body: some View {
        Form {
            masterSection
            behaviorSection
            listSection
            locationSection
            logSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 620)
        .onAppear { login.reload(); engine.refreshAll() }
    }

    // MARK: 状态

    private var masterSection: some View {
        Section {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("防护").font(.system(size: 22, weight: .semibold))
                    Text(store.config.enabled ? "已开启" : "已暂停")
                        .font(.callout)
                        .foregroundStyle(store.config.enabled ? Color.green : Color.secondary)
                }
                Spacer()
                Toggle("", isOn: $store.config.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .scaleEffect(1.4, anchor: .trailing)
                    .padding(.trailing, 4)
            }
            .padding(.vertical, 8)

            row("Wi-Fi", dot: engine.wifi.connected ? (engine.alerting ? .red : .green) : .gray,
                text: wifiText)
            row("Clash", dot: engine.clash.active ? .green : (engine.clash.appRunning ? .orange : .gray),
                text: engine.clash.headline)
            if let p = engine.clash.proxyDetail { detail("系统代理", p) }
            if let t = engine.clash.tunDetail { detail("TUN 接口", t) }
            if let n = engine.clash.processName { detail("进程", n) }
            if engine.alerting {
                Text("当前网络命中名单且 Clash 开启。").foregroundStyle(.red).font(.callout)
            }
        }
    }

    private var wifiText: String {
        let i = engine.wifi
        if !i.powerOn { return "已关闭" }
        if !i.connected { return "未连接" }
        return i.ssid ?? "已连接，读不到名称（需要定位权限）"
    }

    private func row(_ title: String, dot: Color, text: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func detail(_ title: String, _ text: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary).font(.callout)
            Spacer()
            Text(text).foregroundStyle(.secondary).font(.system(.callout, design: .monospaced))
        }
    }

    // MARK: 名单

    private var listSection: some View {
        Section("Wi-Fi 名单（\(store.config.ssids.count)）") {
            Picker("模式", selection: $store.config.mode) {
                ForEach(ListMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(store.config.mode.explain).font(.callout).foregroundStyle(.secondary)

            if store.config.ssids.isEmpty {
                Text("名单是空的").foregroundStyle(.secondary)
            }
            let all = store.config.ssids
            let visible = (listExpanded || all.count <= collapsedCount) ? all : Array(all.prefix(collapsedCount))
            ForEach(visible, id: \.self) { s in
                HStack {
                    Text(s)
                    if s == engine.wifi.ssid { Text("当前").font(.caption).foregroundStyle(.blue) }
                    Spacer()
                    Button { store.remove(s) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("从名单删除")
                }
            }
            if all.count > collapsedCount {
                Button(listExpanded ? "收起" : "显示全部 \(all.count) 个") {
                    withAnimation { listExpanded.toggle() }
                }
                .buttonStyle(.link)
            }
            HStack {
                TextField("输入 Wi-Fi 名称（SSID）", text: $newSSID)
                    .onSubmit(add)
                Button("添加", action: add).disabled(newSSID.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("选择…") { KnownNetworksWindow.shared.show(engine: engine) }
            }
        }
    }

    private func add() {
        store.add(newSSID)
        newSSID = ""
    }

    // MARK: 行为

    private var behaviorSection: some View {
        Section("行为") {
            Toggle("命中后自动断开", isOn: $store.config.autoDisconnect)
            Toggle("同时忘记该网络（需要管理员权限，可能失败）", isOn: $store.config.forgetNetwork)
                .disabled(!store.config.autoDisconnect)
            Toggle("发送系统通知", isOn: $store.config.notify)
            Toggle("开机自启", isOn: Binding(get: { login.isOn }, set: { login.set($0) }))
            HStack {
                Text(login.note).font(.callout).foregroundStyle(.secondary)
                if login.status == .requiresApproval {
                    Button("打开登录项设置") { login.openSystemSettings() }
                }
            }
            if let e = login.error {
                Text(e).font(.callout).foregroundStyle(.red)
            }
        }
    }

    // MARK: 定位权限

    private var locationSection: some View {
        Section("定位权限（读取 Wi-Fi 名称必需）") {
            HStack {
                Text("状态")
                Spacer()
                Text(engine.wifiMonitor.locationStatusText).foregroundStyle(.secondary)
            }
            HStack {
                Button("请求授权") { engine.wifiMonitor.requestLocationIfNeeded() }
                Button("打开定位服务设置") {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                        NSWorkspace.shared.open(u)
                    }
                }
            }
        }
    }

    // MARK: 日志

    private var logSection: some View {
        Section("最近记录") {
            ScrollView {
                Text(engine.log.suffix(20).reversed().map { $0.line }.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 110)
        }
    }
}

final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show(engine: GuardEngine) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(engine: engine, store: engine.store))
            let w = NSWindow(contentViewController: host)
            w.title = "Clash Gate"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 500, height: 680))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}


// MARK: 已知网络选择

struct KnownNetworksView: View {
    @ObservedObject var engine: GuardEngine
    @ObservedObject var store: ConfigStore
    @State private var networks: [String] = WiFiMonitor.knownNetworks()
    @State private var query = ""

    private var shown: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? networks : networks.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("系统已保存的 Wi-Fi（\(networks.count) 个）").font(.headline)
            Text(store.config.mode == .blacklist
                 ? "勾选的网络会进入黑名单：Clash 开启时连上它们会被断开。"
                 : "勾选的网络会进入白名单：Clash 开启时只放行它们，其他网络会被断开。")
                .font(.callout).foregroundStyle(.secondary)
            TextField("搜索", text: $query).textFieldStyle(.roundedBorder)
            List(shown, id: \.self) { s in
                Toggle(isOn: Binding(
                    get: { store.config.ssids.contains(s) },
                    set: { $0 ? store.add(s) : store.remove(s) })) {
                    HStack {
                        Text(s)
                        if s == engine.wifi.ssid {
                            Text("当前网络").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
            HStack {
                Text("已选 \(store.config.ssids.count) 个").foregroundStyle(.secondary)
                Spacer()
                Button("重新读取") { networks = WiFiMonitor.knownNetworks() }
            }
        }
        .padding(16)
        .frame(minWidth: 380, minHeight: 460)
    }
}

final class KnownNetworksWindow {
    static let shared = KnownNetworksWindow()
    private var window: NSWindow?

    func show(engine: GuardEngine) {
        if window == nil {
            let host = NSHostingController(rootView: KnownNetworksView(engine: engine, store: engine.store))
            let w = NSWindow(contentViewController: host)
            w.title = "选择 Wi-Fi 名单"
            w.styleMask = [.titled, .closable, .resizable]
            w.setContentSize(NSSize(width: 400, height: 520))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
