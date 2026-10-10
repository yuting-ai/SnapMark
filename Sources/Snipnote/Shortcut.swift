import AppKit
import Carbon.HIToolbox

/// 全局快捷键：Carbon 键码 + Carbon 修饰键
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(controlKey | optionKey))

    private static let defaultsKey = "shortcut"
    private static let modifierMask = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    static func load() -> Shortcut {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let s = try? JSONDecoder().decode(Shortcut.self, from: data) else { return .default }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        modifiers = Self.carbonModifiers(event.modifierFlags)
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    var modifierFlags: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { f.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { f.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { f.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { f.insert(.command) }
        return f
    }

    static func symbols(_ m: UInt32) -> String {
        var s = ""
        if m & UInt32(controlKey) != 0 { s += "⌃" }
        if m & UInt32(optionKey) != 0 { s += "⌥" }
        if m & UInt32(shiftKey) != 0 { s += "⇧" }
        if m & UInt32(cmdKey) != 0 { s += "⌘" }
        return s
    }

    var display: String { Self.symbols(modifiers) + keyName }

    var isFunctionKey: Bool { Self.functionKeys[Int(keyCode)] != nil }

    /// 必须带 ⌘ / ⌃ / ⌥ 之一，F1–F20 可以单独使用
    var isValid: Bool {
        isFunctionKey || modifiers & UInt32(cmdKey | controlKey | optionKey) != 0
    }

    /// 是否和系统设置里启用的快捷键（如 ⌘⇧4 截图、Spotlight）冲突
    var conflictsWithSystem: Bool {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr,
              let list = unmanaged?.takeRetainedValue() as? [[String: Any]] else { return false }
        return list.contains { hk in
            guard (hk[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let code = hk[kHISymbolicHotKeyCode as String] as? Int,
                  let mods = hk[kHISymbolicHotKeyModifiers as String] as? Int else { return false }
            return UInt32(code) == keyCode && UInt32(mods) & Self.modifierMask == modifiers
        }
    }

    /// 用于菜单项右侧显示快捷键
    var menuKeyEquivalent: String {
        if let n = Self.functionKeys[Int(keyCode)] {
            return String(Character(UnicodeScalar(NSF1FunctionKey + n - 1)!))
        }
        if keyCode == UInt32(kVK_Space) { return " " }
        if Self.specialKeys[Int(keyCode)] != nil { return "" } // 方向键等写在菜单标题里
        let name = keyName
        return name.count == 1 ? name.lowercased() : ""
    }

    // MARK: - 键名

    private static let functionKeys: [Int: Int] = [
        kVK_F1: 1, kVK_F2: 2, kVK_F3: 3, kVK_F4: 4, kVK_F5: 5, kVK_F6: 6, kVK_F7: 7, kVK_F8: 8, kVK_F9: 9, kVK_F10: 10,
        kVK_F11: 11, kVK_F12: 12, kVK_F13: 13, kVK_F14: 14, kVK_F15: 15, kVK_F16: 16, kVK_F17: 17, kVK_F18: 18,
        kVK_F19: 19, kVK_F20: 20,
    ]

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_KeypadEnter: "⌤",
    ]

    var keyName: String {
        if let n = Self.functionKeys[Int(keyCode)] { return "F\(n)" }
        if let s = Self.specialKeys[Int(keyCode)] { return s }
        return Self.translate(keyCode) ?? "#\(keyCode)"
    }

    /// 按当前（ASCII）键盘布局把键码翻译成字符，中文输入法下也能得到字母
    private static func translate(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
