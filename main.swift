import Cocoa
import Darwin
import ServiceManagement

final class Monitor {
    private var prevTicks: [UInt32]?

    func cpu() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return 0 }
        let t = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        defer { prevTicks = t }
        guard let p = prevTicks else { return 0 }
        let d = zip(t, p).map { Double($0 &- $1) }
        let total = d.reduce(0, +)
        guard total > 0 else { return 0 }
        return (total - d[Int(CPU_STATE_IDLE)]) / total * 100
    }

    func memory() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return 0 }
        let page = Double(vm_kernel_page_size)
        // Matches Activity Monitor's "Memory Used": app + wired + compressed
        let used = Double(stats.internal_page_count - stats.purgeable_count + stats.wire_count + stats.compressor_page_count) * page
        return used / Double(ProcessInfo.processInfo.physicalMemory) * 100
    }

    func disk() -> Double {
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacityForImportantUsage, total > 0
        else { return 0 }
        return (1 - Double(free) / Double(total)) * 100
    }
}

struct Reading { let icon: String; let text: String; let unit: String; let hot: Bool }

final class Sensors {
    private let smc = SMC()
    private lazy var tempKeys: [String] = {
        guard let smc else { return [] }
        var keys: [String] = []
        for i in 0..<4000 {
            guard let k = smc.key(at: UInt32(i)) else { continue }
            // Tp* = performance cores, Te* = efficiency cores (Apple Silicon)
            if k.hasPrefix("Tp") || k.hasPrefix("Te"), let v = smc.double(k), v > 0, v < 150 { keys.append(k) }
        }
        return keys
    }()

    /// Hottest CPU core sensor, °C.
    func cpuTemperature() -> Double? {
        guard let smc else { return nil }
        return tempKeys.compactMap { smc.double($0) }.filter { $0 > 0 && $0 < 150 }.max()
    }

    /// Fastest fan's RPM and its fraction of max speed.
    func fanRPM() -> (rpm: Double, fraction: Double)? {
        guard let smc, let n = smc.double("FNum"), n > 0 else { return nil }
        let fans = (0..<Int(n)).compactMap { i -> (Double, Double)? in
            guard let rpm = smc.double("F\(i)Ac") else { return nil }
            let mx = smc.double("F\(i)Mx") ?? 0
            return (rpm, mx > 0 ? rpm / mx : 0)
        }
        return fans.max { $0.0 < $1.0 }.map { (rpm: $0.0, fraction: $0.1) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let mon = Monitor()
    let sensors = Sensors()
    var timer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (i, m) in metrics.enumerated() {
            let mi = NSMenuItem(title: "Show \(m.title)", action: #selector(toggleMetric(_:)), keyEquivalent: "")
            mi.target = self
            mi.tag = i
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        let am = NSMenuItem(title: "Activity Monitor", action: #selector(openAM), keyEquivalent: "")
        am.target = self
        menu.addItem(am)
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        defer { refreshMenu() }
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        if !UserDefaults.standard.bool(forKey: "loginConfigured") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "loginConfigured")
            menu.items.first { $0.title == "Launch at Login" }?.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        _ = mon.cpu()
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    let metrics = [(title: "CPU", key: "cpu", icon: "cpu", hidden: false),
                   (title: "Memory", key: "memory", icon: "memorychip", hidden: false),
                   (title: "Storage", key: "storage", icon: "internaldrive", hidden: false),
                   (title: "CPU Temperature", key: "temp", icon: "thermometer.medium", hidden: true),
                   (title: "Fan Speed", key: "fan", icon: "fan", hidden: true)]

    func isShown(_ i: Int) -> Bool {
        let k = "hide_" + metrics[i].key
        return UserDefaults.standard.object(forKey: k) == nil ? !metrics[i].hidden : !UserDefaults.standard.bool(forKey: k)
    }

    func update() {
        // Always sample every metric so CPU deltas stay accurate while hidden.
        let cpu = mon.cpu(), mem = mon.memory(), disk = mon.disk()
        let temp = sensors.cpuTemperature(), fan = sensors.fanRPM()
        let all: [Reading] = [
            Reading(icon: metrics[0].icon, text: String(format: "%.0f", cpu), unit: "%", hot: cpu > 80),
            Reading(icon: metrics[1].icon, text: String(format: "%.0f", mem), unit: "%", hot: mem > 80),
            Reading(icon: metrics[2].icon, text: String(format: "%.0f", disk), unit: "%", hot: disk > 80),
            Reading(icon: metrics[3].icon, text: temp.map { String(format: "%.0f", $0) } ?? "–", unit: "°", hot: (temp ?? 0) > 90),
            Reading(icon: metrics[4].icon, text: fan.map { String(format: "%.0f", $0.rpm) } ?? "–", unit: "rpm", hot: (fan?.fraction ?? 0) > 0.8),
        ]
        var items = metrics.indices.filter(isShown).map { all[$0] }
        if items.isEmpty { items = [all[0]] }
        item.button?.image = gauges(items)
        item.button?.title = ""
        item.button?.toolTip = String(format: "CPU %.0f%%  Memory %.0f%%  Storage %.0f%%", cpu, mem, disk)
            + (temp.map { String(format: "  Temp %.0f°C", $0) } ?? "")
            + (fan.map { String(format: "  Fan %.0f rpm", $0.rpm) } ?? "")
    }

    @objc func toggleMetric(_ sender: NSMenuItem) {
        let shown = metrics.indices.filter(isShown)
        if isShown(sender.tag) && shown.count <= 1 { return }  // keep at least one visible
        UserDefaults.standard.set(isShown(sender.tag), forKey: "hide_" + metrics[sender.tag].key)
        refreshMenu()
        update()
    }

    /// Sync checkmarks; the last visible metric is locked so one is always shown.
    func refreshMenu() {
        let shown = metrics.indices.filter(isShown)
        for mi in item.menu?.items ?? [] where mi.action == #selector(toggleMetric(_:)) {
            let on = isShown(mi.tag)
            mi.state = on ? .on : .off
            mi.isEnabled = !(on && shown.count <= 1)
        }
    }

    /// Compact "icon + number%" groups; each group is only as wide as its text.
    func gauges(_ items: [Reading]) -> NSImage {
        let iconW: CGFloat = 17, iconGap: CGFloat = 2, gap: CGFloat = 8, height: CGFloat = 18
        let numFont = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        let pctFont = NSFont.systemFont(ofSize: 9, weight: .medium)
        struct Group { let r: Reading; let numW: CGFloat; let pctW: CGFloat }
        let groups = items.map { r -> Group in
            let nw = NSAttributedString(string: r.text, attributes: [.font: numFont]).size().width
            let pw = NSAttributedString(string: r.unit, attributes: [.font: pctFont]).size().width
            return Group(r: r, numW: ceil(nw), pctW: ceil(pw))
        }
        let widths = groups.map { iconW + iconGap + $0.numW + $0.pctW }
        let size = NSSize(width: widths.reduce(0, +) + gap * CGFloat(groups.count - 1), height: height)
        return NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0
            for (g, w) in zip(groups, widths) {
                let color: NSColor = g.r.hot ? .systemRed : .labelColor
                if let sym = NSImage(systemSymbolName: g.r.icon, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) {
                    let tinted = NSImage(size: sym.size, flipped: false) { r in
                        sym.draw(in: r)
                        color.setFill()
                        r.fill(using: .sourceIn)
                        return true
                    }
                    let h = min(sym.size.height, 15), iw = sym.size.width * h / sym.size.height
                    tinted.draw(in: NSRect(x: x + (iconW - iw) / 2, y: (height - h) / 2, width: iw, height: h))
                }
                let num = NSAttributedString(string: g.r.text, attributes: [.font: numFont, .foregroundColor: color])
                let nx = x + iconW + iconGap
                num.draw(at: NSPoint(x: nx, y: (height - num.size().height) / 2))
                let pc = NSAttributedString(string: g.r.unit, attributes: [.font: pctFont, .foregroundColor: color.withAlphaComponent(0.8)])
                pc.draw(at: NSPoint(x: nx + g.numW, y: (height - num.size().height) / 2 + (num.size().height - pc.size().height) / 2 - 1.5))
                x += w + gap
            }
            return true
        }
    }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch { NSLog("Login item error: \(error)") }
        sender.state = svc.status == .enabled ? .on : .off
    }

    @objc func openAM() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
