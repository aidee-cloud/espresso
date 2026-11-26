// Espresso — a tiny menu bar app that keeps your Mac awake.
// Left-click the cup to toggle. Right-click (or Control/Option-click) for options.

import AppKit
import IOKit.pwr_mgt
import ServiceManagement

// MARK: - Power assertion

final class SleepBlocker {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive = false

    @discardableResult
    func start(allowDisplaySleep: Bool) -> Bool {
        stop()
        let type = (allowDisplaySleep
            ? kIOPMAssertionTypePreventUserIdleSystemSleep
            : kIOPMAssertionTypePreventUserIdleDisplaySleep) as CFString
        let reason = "Espresso is keeping this Mac awake" as CFString
        let result = IOPMAssertionCreateWithName(type,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 reason,
                                                 &assertionID)
        isActive = (result == kIOReturnSuccess)
        return isActive
    }

    func stop() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }
}

// MARK: - Preferences

enum Prefs {
    private static let d = UserDefaults.standard
    static let durationChoices: [Int] = [0, 5, 10, 15, 30, 60, 120, 300] // minutes, 0 = indefinitely

    static var defaultDuration: Int {
        get { d.object(forKey: "defaultDuration") as? Int ?? 0 }
        set { d.set(newValue, forKey: "defaultDuration") }
    }
    static var activateAtLaunch: Bool {
        get { d.bool(forKey: "activateAtLaunch") }
        set { d.set(newValue, forKey: "activateAtLaunch") }
    }
    static var allowDisplaySleep: Bool {
        get { d.bool(forKey: "allowDisplaySleep") }
        set { d.set(newValue, forKey: "allowDisplaySleep") }
    }
    static var hasLaunchedBefore: Bool {
        get { d.bool(forKey: "hasLaunchedBefore") }
        set { d.set(newValue, forKey: "hasLaunchedBefore") }
    }
}

func durationLabel(_ minutes: Int) -> String {
    switch minutes {
    case 0: return "Indefinitely"
    case let m where m < 60: return "\(m) minutes"
    case 60: return "1 hour"
    default: return "\(minutes / 60) hours"
    }
}

func remainingLabel(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded(.up))
    if total < 60 { return "less than a minute left" }
    let mins = (total + 59) / 60
    let h = mins / 60, m = mins % 60
    if h == 0 { return "\(m) min left" }
    return m == 0 ? "\(h) h left" : "\(h) h \(m) min left"
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let blocker = SleepBlocker()
    private var endDate: Date?
    private var tickTimer: Timer?

    private var isOn: Bool { blocker.isActive }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Re-apply the assertion after wake, just in case.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        if !Prefs.hasLaunchedBefore {
            Prefs.hasLaunchedBefore = true
            showWelcome()
        }

        if Prefs.activateAtLaunch {
            activate(minutes: Prefs.defaultDuration)
        } else {
            refreshUI()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        blocker.stop()
    }

    // MARK: Click handling

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
            || event?.modifierFlags.contains(.option) == true
        if wantsMenu {
            showMenu()
        } else {
            toggle()
        }
    }

    private func showMenu() {
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil) // opens the menu
        statusItem.menu = nil                // so the next left-click toggles again
    }

    // MARK: State

    @objc private func toggle() {
        if isOn { deactivate() } else { activate(minutes: Prefs.defaultDuration) }
    }

    private func activate(minutes: Int) {
        guard blocker.start(allowDisplaySleep: Prefs.allowDisplaySleep) else {
            NSSound.beep()
            refreshUI()
            return
        }
        endDate = minutes > 0 ? Date().addingTimeInterval(TimeInterval(minutes * 60)) : nil
        startTicking()
        refreshUI()
    }

    private func deactivate() {
        blocker.stop()
        endDate = nil
        tickTimer?.invalidate()
        tickTimer = nil
        refreshUI()
    }

    private func startTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
        guard endDate != nil else { return }
        let t = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    @objc private func tick() {
        if let end = endDate, end.timeIntervalSinceNow <= 0 {
            deactivate()
        } else {
            refreshUI()
        }
    }

    @objc private func didWake() {
        if let end = endDate, end.timeIntervalSinceNow <= 0 {
            deactivate()
        } else if isOn {
            blocker.start(allowDisplaySleep: Prefs.allowDisplaySleep)
            refreshUI()
        }
    }

    private func statusText() -> String {
        guard isOn else { return "Espresso is off — your Mac can sleep" }
        if let end = endDate {
            return "Espresso is on — \(remainingLabel(end.timeIntervalSinceNow))"
        }
        return "Espresso is on — keeping your Mac awake"
    }

    private func refreshUI() {
        guard let button = statusItem.button else { return }
        let symbol = isOn ? "cup.and.saucer.fill" : "cup.and.saucer"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: isOn ? "Espresso on" : "Espresso off")
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = false
        button.toolTip = statusText() + "\nClick to toggle · Right-click for options"
    }

    // MARK: Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let status = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let toggleItem = NSMenuItem(title: isOn ? "Turn Off" : "Turn On",
                                    action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        // Activate for…
        let activateFor = NSMenuItem(title: "Activate for", action: nil, keyEquivalent: "")
        let activateSub = NSMenu()
        for m in Prefs.durationChoices {
            let item = NSMenuItem(title: durationLabel(m), action: #selector(activateForDuration(_:)), keyEquivalent: "")
            item.target = self
            item.tag = m
            activateSub.addItem(item)
        }
        activateFor.submenu = activateSub
        menu.addItem(activateFor)

        menu.addItem(.separator())

        // Preferences (inline, like the classic utility)
        let defaultItem = NSMenuItem(title: "Default Duration", action: nil, keyEquivalent: "")
        let defaultSub = NSMenu()
        for m in Prefs.durationChoices {
            let item = NSMenuItem(title: durationLabel(m), action: #selector(setDefaultDuration(_:)), keyEquivalent: "")
            item.target = self
            item.tag = m
            item.state = (m == Prefs.defaultDuration) ? .on : .off
            defaultSub.addItem(item)
        }
        defaultItem.submenu = defaultSub
        menu.addItem(defaultItem)

        let displayItem = NSMenuItem(title: "Allow Display to Sleep",
                                     action: #selector(toggleAllowDisplaySleep), keyEquivalent: "")
        displayItem.target = self
        displayItem.state = Prefs.allowDisplaySleep ? .on : .off
        menu.addItem(displayItem)

        let launchActivate = NSMenuItem(title: "Activate at Launch",
                                        action: #selector(toggleActivateAtLaunch), keyEquivalent: "")
        launchActivate.target = self
        launchActivate.state = Prefs.activateAtLaunch ? .on : .off
        menu.addItem(launchActivate)

        let loginItem = NSMenuItem(title: "Start at Login",
                                   action: #selector(toggleStartAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About Espresso", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit Espresso", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func activateForDuration(_ sender: NSMenuItem) {
        activate(minutes: sender.tag)
    }

    @objc private func setDefaultDuration(_ sender: NSMenuItem) {
        Prefs.defaultDuration = sender.tag
    }

    @objc private func toggleAllowDisplaySleep() {
        Prefs.allowDisplaySleep.toggle()
        if isOn { blocker.start(allowDisplaySleep: Prefs.allowDisplaySleep) } // re-apply with new type
        refreshUI()
    }

    @objc private func toggleActivateAtLaunch() {
        Prefs.activateAtLaunch.toggle()
    }

    @objc private func toggleStartAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            alert("Couldn't change the login item",
                  "\(error.localizedDescription)\n\nTip: move Espresso to your Applications folder and try again, or add it manually in System Settings → General → Login Items.")
        }
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Keeps your Mac awake.\nClick the cup in the menu bar to toggle, right-click for options.")
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showWelcome() {
        alert("Espresso lives in your menu bar ☕",
              "Look for the cup icon at the top of your screen.\n\n• Click it to keep your Mac awake (filled cup = on).\n• Click again to let it sleep normally.\n• Right-click for durations and settings.")
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "OK")
        a.runModal()
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
