import AppKit

struct Service {
    let name: String
    let device: String
}

enum ToolError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

func command(_ path: String, _ arguments: [String]) throws -> String {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard process.terminationStatus == 0 else {
        throw ToolError.message(output.isEmpty ? "系统命令执行失败。" : output)
    }
    return output
}

func services() throws -> [Service] {
    let output = try command("/usr/sbin/networksetup", ["-listnetworkserviceorder"])
    var result: [Service] = []
    var name: String?
    for line in output.components(separatedBy: .newlines) {
        if line.range(of: #"^\([0-9*]+\) "#, options: .regularExpression) != nil,
           let end = line.firstIndex(of: ")") {
            name = String(line[line.index(end, offsetBy: 2)...])
        } else if line.hasPrefix("(Hardware Port:"), let serviceName = name,
                  let deviceStart = line.range(of: ", Device: ") {
            let device = String(line[deviceStart.upperBound...].dropLast())
            result.append(Service(name: serviceName, device: device))
            name = nil
        }
    }
    guard !result.isEmpty else { throw ToolError.message("未读取到网络服务，请打开系统设置检查网络。") }
    return result
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let picker = NSPopUpButton()
    private let priority = NSTextField(labelWithString: "")
    private let route = NSTextField(wrappingLabelWithString: "")
    private let order = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "选择要优先使用的网络，再点击切换。")
    private let apply = NSButton(title: "设为优先", target: nil, action: nil)
    private var current: [Service] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "网络优先级"
        window.center()
        let content = window.contentView!
        let title = NSTextField(labelWithString: "选择你的上网线路")
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        let note = NSTextField(wrappingLabelWithString: "Wi-Fi、iPhone USB、有线网卡，一键调整优先顺序。\n其他网络的相对顺序保持不变。")
        note.textColor = .secondaryLabelColor
        priority.font = .systemFont(ofSize: 15, weight: .semibold)
        route.textColor = .secondaryLabelColor
        order.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        status.font = .systemFont(ofSize: 12)
        apply.target = self
        apply.action = #selector(switchPriority)
        apply.bezelStyle = .rounded
        apply.keyEquivalent = "\r"
        let refreshButton = NSButton(title: "刷新状态", target: self, action: #selector(refreshClicked))
        refreshButton.bezelStyle = .rounded
        let selection = NSStackView(views: [picker, apply, refreshButton])
        selection.orientation = .horizontal
        selection.spacing = 10
        picker.widthAnchor.constraint(equalToConstant: 230).isActive = true
        let hint = NSTextField(wrappingLabelWithString: "优先级不会更换 Wi-Fi 名称。所选网络需要已连接且可上网；VPN 或代理可能另行接管流量。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, note, selection, priority, route, order, status, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28)
        ])
        refresh()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refresh() {
        do {
            let selected = picker.titleOfSelectedItem
            current = try services()
            picker.removeAllItems()
            picker.addItems(withTitles: current.map(\.name))
            if let selected, current.contains(where: { $0.name == selected }) {
                picker.selectItem(withTitle: selected)
            }
            priority.stringValue = "当前优先：\(current[0].name)"
            order.stringValue = current.enumerated().map { "\($0.offset + 1). \($0.element.name)" }.joined(separator: "   →   ")
            let output = try? command("/sbin/route", ["-n", "get", "default"])
            let interface = output?.components(separatedBy: .newlines)
                .first(where: { $0.contains("interface:") })?
                .components(separatedBy: "interface:").last?
                .trimmingCharacters(in: .whitespaces)
            if let interface {
                let name = current.first(where: { $0.device == interface })?.name ?? interface
                route.stringValue = "当前 IPv4 默认出口：\(name)（\(interface)）"
            } else {
                route.stringValue = "当前没有可读取的 IPv4 默认出口。"
            }
            apply.isEnabled = true
        } catch {
            status.stringValue = "读取失败：\(error.localizedDescription)"
            status.textColor = .systemRed
            apply.isEnabled = false
        }
    }

    @objc private func refreshClicked() {
        status.stringValue = "已刷新网络状态。"
        status.textColor = .secondaryLabelColor
        refresh()
    }

    @objc private func switchPriority() {
        guard let selected = picker.titleOfSelectedItem else { return }
        do {
            let latest = try services()
            guard latest.contains(where: { $0.name == selected }) else {
                throw ToolError.message("所选网络服务已不存在，请刷新后重新选择。")
            }
            let names = [selected] + latest.map(\.name).filter { $0 != selected }
            _ = try command("/usr/sbin/networksetup", ["-ordernetworkservices"] + names)
            guard try services().map(\.name) == names else {
                throw ToolError.message("系统没有应用新的顺序，请到系统设置检查。")
            }
            status.stringValue = "已将 \(selected) 设为最高优先级。"
            status.textColor = .systemGreen
            refresh()
            // Default route changes may arrive after the order update.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
        } catch {
            status.stringValue = "切换失败：\(error.localizedDescription)"
            status.textColor = .systemRed
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
