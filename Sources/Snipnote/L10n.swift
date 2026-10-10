import Foundation

enum Language: String, CaseIterable {
    case system, zh, en
}

/// 界面文字（中 / 英）。所有面向用户的文字都集中在这里
enum L10n {
    private static let defaultsKey = "language"

    static var language: Language {
        get { Language(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    /// 临时指定语言（--snapshot 用），不写入设置
    nonisolated(unsafe) static var override: Language?

    static var isChinese: Bool {
        switch override ?? language {
        case .zh: true
        case .en: false
        case .system: Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
        }
    }

    private static func t(_ zh: String, _ en: String) -> String { isChinese ? zh : en }

    // MARK: 菜单栏

    static var capture: String { t("截图", "Take Screenshot") }
    static var settingsMenu: String { t("设置…", "Settings…") }
    static var launchAtLogin: String { t("开机自动启动", "Launch at Login") }
    static var quit: String { t("退出 Snipnote", "Quit Snipnote") }
    static func hotKeyFailedMenu(_ key: String) -> String {
        t("⚠️ 快捷键 \(key) 注册失败，点此修改", "⚠️ Shortcut \(key) unavailable, click to change")
    }

    // MARK: 设置窗口

    static var settingsTitle: String { t("Snipnote 设置", "Snipnote Settings") }
    static var shortcutLabel: String { t("截图快捷键", "Shortcut") }
    static var languageLabel: String { t("语言", "Language") }
    static func languageName(_ l: Language) -> String {
        switch l {
        case .system: t("跟随系统", "System Default")
        case .zh: "中文"
        case .en: "English"
        }
    }
    static var resetDefault: String { t("恢复默认", "Reset") }
    static var pressShortcut: String { t("请按快捷键…", "Type shortcut…") }
    static var hintIdle: String { t("点击按钮后按下新的快捷键", "Click the button, then press a new shortcut") }
    static var hintRecording: String { t("请按下新的快捷键，Esc 取消", "Press a new shortcut, Esc to cancel") }
    static var invalidShortcut: String {
        t("需要包含 ⌘、⌃ 或 ⌥ 中的至少一个（F1–F20 可以单独使用）",
          "Must include ⌘, ⌃ or ⌥ (F1–F20 can be used alone)")
    }
    static func shortcutSet(_ key: String) -> String { t("已设置为 \(key)", "Shortcut set to \(key)") }
    static func shortcutSystemConflict(_ key: String) -> String {
        t("已设置为 \(key)，但它和系统快捷键冲突，可能不会生效。可以在「系统设置 → 键盘 → 键盘快捷键」里关掉系统的那个。",
          "Set to \(key), but it conflicts with a system shortcut and may not work. You can turn off the system one in System Settings → Keyboard → Keyboard Shortcuts.")
    }
    static func shortcutTaken(_ key: String) -> String {
        t("\(key) 注册失败，可能已被其他应用占用，请换一个",
          "Couldn't register \(key). It may be used by another app — please choose another.")
    }

    // MARK: 截图权限

    static var captureFailedTitle: String { t("无法截屏", "Unable to Capture Screen") }
    static var captureFailedInfo: String {
        t("请在「系统设置 → 隐私与安全性 → 屏幕与系统音频录制」中允许 Snipnote，然后退出并重新打开 Snipnote。",
          "Allow Snipnote in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen Snipnote.")
    }
    static var openSystemSettings: String { t("打开系统设置", "Open System Settings") }
    static var cancel: String { t("取消", "Cancel") }

    // MARK: 工具条

    static func toolName(_ tool: Tool) -> String {
        switch tool {
        case .rect: t("矩形", "Rectangle")
        case .ellipse: t("椭圆", "Ellipse")
        case .arrow: t("箭头", "Arrow")
        case .pen: t("画笔", "Pen")
        case .text: t("文字", "Text")
        case .mosaic: t("马赛克", "Mosaic")
        }
    }
    static var undoTip: String { t("撤销 ⌘Z", "Undo ⌘Z") }
    static var saveTip: String { t("保存到桌面 ⌘S", "Save to Desktop ⌘S") }
    static var cancelTip: String { t("取消 Esc", "Cancel Esc") }
    static var doneTip: String { t("完成并复制 ↩", "Copy to Clipboard ↩") }
    static var fontSizeTip: String { t("字号", "Font Size") }
    static var brushSizeTip: String { t("笔刷大小", "Brush Size") }
    static var lineWidthTip: String { t("粗细", "Line Width") }
}
