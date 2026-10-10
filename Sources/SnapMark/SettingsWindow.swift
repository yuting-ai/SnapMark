import AppKit

/// 设置窗口：截图快捷键、界面语言
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// 开始录制时暂停全局快捷键，否则按下当前组合会直接触发截图
    var onRecordingStarted: (() -> Void)?
    var onRecordingCancelled: (() -> Void)?
    /// 返回 nil 表示成功，否则是错误信息
    var onShortcut: ((Shortcut) -> String?)?
    var onLanguageChanged: (() -> Void)?

    private let recorder = ShortcutRecorder()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    init(shortcut: Shortcut) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        recorder.shortcut = shortcut
        recorder.onStart = { [weak self] in
            self?.showHint()
            self?.onRecordingStarted?()
        }
        recorder.onCancel = { [weak self] in
            self?.showHint()
            self?.onRecordingCancelled?()
        }
        recorder.onInvalid = { [weak self] in
            self?.showStatus(L10n.invalidShortcut, isError: true)
        }
        recorder.onRecord = { [weak self] s in self?.apply(s) }

        buildContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 切换语言时整个重建一遍
    private func buildContent() {
        window?.title = L10n.settingsTitle
        recorder.refreshTitle()

        let shortcutLabel = NSTextField(labelWithString: L10n.shortcutLabel)
        let reset = NSButton(title: L10n.resetDefault, target: self, action: #selector(resetToDefault))
        reset.bezelStyle = .rounded
        let shortcutControls = NSStackView(views: [recorder, reset])
        shortcutControls.spacing = 8

        let languageLabel = NSTextField(labelWithString: L10n.languageLabel)
        let languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for l in Language.allCases {
            languagePopup.addItem(withTitle: L10n.languageName(l))
            languagePopup.lastItem?.representedObject = l.rawValue
        }
        languagePopup.selectItem(at: Language.allCases.firstIndex(of: L10n.language) ?? 0)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))

        let grid = NSGridView(views: [
            [shortcutLabel, shortcutControls],
            [languageLabel, languagePopup],
        ])
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.preferredMaxLayoutWidth = 380

        let column = NSStackView(views: [grid, statusLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 14
        column.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        column.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            column.topAnchor.constraint(equalTo: content.topAnchor),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            column.widthAnchor.constraint(equalToConstant: 420),
        ])
        window?.contentView = content
        showHint()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let l = Language(rawValue: raw), l != L10n.language else { return }
        L10n.language = l
        // 等弹出菜单收起后再重建界面
        DispatchQueue.main.async { [weak self] in
            self?.buildContent()
            self?.onLanguageChanged?()
        }
    }

    private func apply(_ s: Shortcut) {
        if let error = onShortcut?(s) {
            showStatus(error, isError: true)
        } else {
            recorder.shortcut = s
            if s.conflictsWithSystem {
                showStatus(L10n.shortcutSystemConflict(s.display), isError: true)
            } else {
                showStatus(L10n.shortcutSet(s.display), isError: false)
            }
        }
    }

    @objc private func resetToDefault() {
        recorder.cancelRecording()
        apply(.default)
    }

    private func showHint() {
        showStatus(recorder.isRecording ? L10n.hintRecording : L10n.hintIdle, isError: false)
    }

    private func showStatus(_ text: String, isError: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    func windowDidResignKey(_ notification: Notification) {
        recorder.cancelRecording()
    }
}

/// 点一下进入录制状态，按下组合键即完成
final class ShortcutRecorder: NSButton {
    var shortcut: Shortcut = .default { didSet { updateTitle() } }
    var onStart: (() -> Void)?
    var onCancel: (() -> Void)?
    var onInvalid: (() -> Void)?
    var onRecord: ((Shortcut) -> Void)?

    private(set) var isRecording = false
    private var monitor: Any?

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(toggle)
        font = .systemFont(ofSize: 13, weight: .medium)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 130).isActive = true
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggle() {
        isRecording ? cancelRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        updateTitle()
        onStart?()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handle(event)
            return nil // 录制期间吞掉所有按键
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        stop()
        onCancel?()
    }

    private func stop() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        updateTitle()
    }

    private func handle(_ event: NSEvent) {
        if event.type == .flagsChanged {
            // 按住修饰键时实时显示，比如 "⌃⌥…"
            let m = Shortcut.carbonModifiers(event.modifierFlags)
            title = m == 0 ? L10n.pressShortcut : Shortcut.symbols(m) + "…"
            return
        }
        let s = Shortcut(event: event)
        if event.keyCode == 53 && s.modifiers == 0 { // 单独按 Esc 取消
            cancelRecording()
            return
        }
        guard s.isValid else {
            onInvalid?()
            return
        }
        stop()
        onRecord?(s)
    }

    func refreshTitle() { updateTitle() }

    private func updateTitle() {
        title = isRecording ? L10n.pressShortcut : shortcut.display
    }
}
