import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var shortcut = Shortcut.load()
    private let controller = CaptureController()
    private var settings: SettingsWindowController?

    private let captureItem = NSMenuItem(title: "", action: #selector(captureFromMenu), keyEquivalent: "")
    private let warningItem = NSMenuItem(title: "", action: #selector(openSettings), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 供安装脚本使用：open SnapMark.app --args --enable-launch-at-login
        if CommandLine.arguments.contains("--enable-launch-at-login") {
            do {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
                NSLog("SnapMark launch at login status: \(SMAppService.mainApp.status.rawValue)")
            } catch {
                NSLog("SnapMark launch at login failed: \(error)")
            }
        }

        setupStatusItem()
        registerHotKey()

        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let icon = NSImage(systemSymbolName: "scissors", accessibilityDescription: "SnapMark")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        buildMenu()
    }

    /// 切换语言时重建
    private func buildMenu() {
        let menu = NSMenu()

        // 这两项会复用，先从旧菜单里拿出来，否则 addItem 会抛异常
        statusItem.menu?.removeAllItems()
        captureItem.target = self
        menu.addItem(captureItem)
        warningItem.target = self
        menu.addItem(warningItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: L10n.settingsMenu, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let login = NSMenuItem(title: L10n.launchAtLogin, action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        updateMenu(registered: hotKey?.isRegistered == true)
    }

    // MARK: - 快捷键

    @discardableResult
    private func registerHotKey() -> Bool {
        hotKey = nil // 先注销旧的，否则同一组合会注册失败
        hotKey = HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { [weak self] in
            self?.controller.start()
        }
        let ok = hotKey?.isRegistered == true
        updateMenu(registered: ok)
        return ok
    }

    private func updateMenu(registered: Bool) {
        let key = shortcut.menuKeyEquivalent
        captureItem.keyEquivalent = key
        captureItem.keyEquivalentModifierMask = shortcut.modifierFlags
        // 菜单显示不了的键（比如方向键）就写在标题里
        captureItem.title = key.isEmpty ? "\(L10n.capture)  \(shortcut.display)" : L10n.capture
        warningItem.title = L10n.hotKeyFailedMenu(shortcut.display)
        warningItem.isHidden = registered
    }

    @objc private func openSettings() {
        if settings == nil {
            let s = SettingsWindowController(shortcut: shortcut)
            s.onRecordingStarted = { [weak self] in self?.hotKey = nil }
            s.onRecordingCancelled = { [weak self] in self?.registerHotKey() }
            s.onShortcut = { [weak self] new in self?.changeShortcut(to: new) }
            s.onLanguageChanged = { [weak self] in self?.buildMenu() }
            settings = s
        }
        settings?.show()
    }

    private func changeShortcut(to new: Shortcut) -> String? {
        let old = shortcut
        shortcut = new
        if registerHotKey() {
            new.save()
            return nil
        }
        shortcut = old
        registerHotKey()
        return L10n.shortcutTaken(new.display)
    }

    // MARK: - 菜单操作

    @objc private func captureFromMenu() {
        // 等菜单收起后再截，避免把菜单截进去
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.controller.start()
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
