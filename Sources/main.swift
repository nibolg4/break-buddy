import Cocoa
import SwiftUI
import ServiceManagement

enum Settings {
    private static let d = UserDefaults.standard

    static var workLimit: TimeInterval {
        get { d.double(forKey: "workLimit") > 0 ? d.double(forKey: "workLimit") : 50 * 60 }
        set { d.set(newValue, forKey: "workLimit") }
    }

    static var breakLength: TimeInterval {
        get { d.double(forKey: "breakLength") > 0 ? d.double(forKey: "breakLength") : 5 * 60 }
        set { d.set(newValue, forKey: "breakLength") }
    }

    static let renagInterval: TimeInterval = 5 * 60
}

struct ReminderView: View {
    let minutes: Int
    let onRest: () -> Void
    let onSnooze: (Int) -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("☕").font(.system(size: 52))
            Text("Пора сделать перерыв").font(.title2).bold()
            Text("Ты работаешь \(minutes) мин без паузы.\nВстань, пройдись, посмотри вдаль.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Ещё 5 мин") { onSnooze(5) }
                Button("Ещё 15 мин") { onSnooze(15) }
                Button("Иду отдыхать") { onRest() }.keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(28)
        .frame(width: 400)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var sessionStart = Date()
    private var lastTick = Date()
    private var onBreak = false
    private var nextReminder = Date()
    private var pausedUntil: Date?
    private var panel: NSPanel?
    private var lastNag = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        startSession(at: Date())
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            MainActor.assumeIsolated { self.tick() }
        }
        tick()
    }

    private var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private var isPaused: Bool {
        if let until = pausedUntil, until > Date() { return true }
        pausedUntil = nil
        return false
    }

    private func startSession(at date: Date) {
        sessionStart = date
        nextReminder = date.addingTimeInterval(Settings.workLimit)
        closeReminder()
    }

    private func tick() {
        let now = Date()
        let gap = now.timeIntervalSince(lastTick)
        lastTick = now

        if gap >= Settings.breakLength {
            onBreak = false
            startSession(at: now)
        }

        let idle = idleSeconds
        if idle >= Settings.breakLength {
            if !onBreak {
                onBreak = true
                closeReminder()
            }
        } else if onBreak {
            onBreak = false
            startSession(at: now.addingTimeInterval(-idle))
        }

        if !onBreak, !isPaused, now >= nextReminder {
            if panel == nil {
                showReminder()
            } else if now.timeIntervalSince(lastNag) >= Settings.renagInterval {
                nag()
            }
        }
        updateTitle()
    }

    private var workedMinutes: Int {
        Int(Date().timeIntervalSince(sessionStart) / 60)
    }

    private func updateTitle() {
        let title: String
        if isPaused {
            title = "⏸"
        } else if onBreak {
            title = "💤"
        } else if Date().timeIntervalSince(sessionStart) >= Settings.workLimit {
            title = "☕ \(workedMinutes)"
        } else {
            title = "⏱ \(workedMinutes)"
        }
        statusItem.button?.title = title
    }

    private func showReminder() {
        let view = ReminderView(
            minutes: workedMinutes,
            onRest: { [weak self] in
                self?.nextReminder = Date().addingTimeInterval(Settings.renagInterval)
                self?.closeReminder()
            },
            onSnooze: { [weak self] minutes in
                self?.nextReminder = Date().addingTimeInterval(TimeInterval(minutes * 60))
                self?.closeReminder()
            }
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: view)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.midY - panel.frame.height / 2))
        }
        self.panel = panel
        nag()
    }

    private func nag() {
        guard let panel else { return }
        lastNag = Date()
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        NSSound(named: "Glass")?.play()
        let origin = panel.frame.origin
        for (i, dx) in [-12.0, 12, -8, 8, -4, 0].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(i)) {
                panel.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y))
            }
        }
    }

    private func closeReminder() {
        panel?.close()
        panel = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status: String
        if isPaused, let until = pausedUntil {
            status = "На паузе до \(until.formatted(date: .omitted, time: .shortened))"
        } else if onBreak {
            status = "Перерыв: \(Int(idleSeconds / 60)) мин"
        } else {
            status = "Без перерыва: \(workedMinutes) мин из \(Int(Settings.workLimit / 60))"
        }
        menu.addItem(NSMenuItem(title: status, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())

        menu.addItem(item("Я отдохнул — начать заново", #selector(resetSession)))
        if isPaused {
            menu.addItem(item("Возобновить", #selector(resume)))
        } else {
            menu.addItem(item("Не беспокоить 1 час", #selector(pauseHour)))
        }
        menu.addItem(.separator())

        menu.addItem(item("Показать напоминание (тест)", #selector(testReminder)))
        menu.addItem(submenu("Напоминать через", values: [25, 45, 50, 60, 90], current: Settings.workLimit, action: #selector(setWorkLimit(_:))))
        menu.addItem(submenu("Перерыв засчитывается после", values: [2, 3, 5, 10], current: Settings.breakLength, action: #selector(setBreakLength(_:))))

        let login = item("Запускать при входе", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выход", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func submenu(_ title: String, values: [Int], current: TimeInterval, action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for minutes in values {
            let child = item("\(minutes) мин", action)
            child.tag = minutes
            child.state = Int(current / 60) == minutes ? .on : .off
            sub.addItem(child)
        }
        parent.submenu = sub
        return parent
    }

    @objc private func resetSession() {
        onBreak = false
        startSession(at: Date())
        updateTitle()
    }

    @objc private func testReminder() {
        if panel == nil { showReminder() } else { nag() }
    }

    @objc private func pauseHour() {
        pausedUntil = Date().addingTimeInterval(3600)
        closeReminder()
        updateTitle()
    }

    @objc private func resume() {
        pausedUntil = nil
        updateTitle()
    }

    @objc private func setWorkLimit(_ sender: NSMenuItem) {
        Settings.workLimit = TimeInterval(sender.tag * 60)
        nextReminder = sessionStart.addingTimeInterval(Settings.workLimit)
        tick()
    }

    @objc private func setBreakLength(_ sender: NSMenuItem) {
        Settings.breakLength = TimeInterval(sender.tag * 60)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
