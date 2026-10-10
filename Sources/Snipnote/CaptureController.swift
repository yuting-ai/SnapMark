import AppKit

/// 管理一次截图会话：截屏 → 每块屏幕一个遮罩窗口 → 复制/保存 → 关闭
@MainActor
final class CaptureController {
    private var windows: [OverlayWindow] = []
    private var busy = false
    /// 正在框选的那块屏幕（多屏时只允许在一块屏幕上框选）
    weak var activeView: OverlayView?

    func start() {
        guard !busy else { return }
        busy = true
        let rects = ScreenCapturer.windowRects()
        Task { @MainActor in
            do {
                let shots = try await ScreenCapturer.captureAll()
                guard !shots.isEmpty else { busy = false; return }
                present(shots, windowRects: rects)
            } catch {
                busy = false
                Self.showCaptureError(error)
            }
        }
    }

    private func present(_ shots: [ScreenShot], windowRects: [CGRect]) {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation

        for shot in shots {
            let frame = shot.screen.frame
            let bounds = CGRect(origin: .zero, size: frame.size)
            let localRects = windowRects
                .map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY).intersection(bounds) }
                .filter { !$0.isNull && $0.width > 10 && $0.height > 10 }

            let container = NSView(frame: bounds)
            let background = NSImageView(frame: bounds)
            background.image = NSImage(cgImage: shot.image, size: frame.size)
            background.imageScaling = .scaleAxesIndependently
            let overlay = OverlayView(frame: bounds, image: shot.image, windowRects: localRects, controller: self)
            container.addSubview(background)
            container.addSubview(overlay)

            let window = OverlayWindow(frame: frame)
            window.contentView = container
            window.orderFrontRegardless()
            windows.append(window)

            if frame.contains(mouse) {
                window.makeKey()
                window.makeFirstResponder(overlay)
                overlay.updateHover(screenPoint: mouse)
            }
        }
    }

    func confirm(save: Bool) {
        guard let view = activeView, let (image, pointSize) = view.render() else { return }

        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = pointSize // 保持 Retina 尺寸，粘贴后显示大小与屏幕一致
        guard let png = rep.representation(using: .png, properties: [:]) else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.png, .tiff], owner: nil)
        pasteboard.setData(png, forType: .png)
        if let tiff = rep.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }

        if save {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            let url = desktop.appendingPathComponent("Snipnote \(formatter.string(from: Date())).png")
            try? png.write(to: url)
        }
        close()
    }

    func cancel() {
        close()
    }

    private func close() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        activeView = nil
        busy = false
        NSApp.hide(nil) // 把焦点还给之前的应用
    }

    private static func showCaptureError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L10n.captureFailedTitle
        alert.informativeText = L10n.captureFailedInfo + "\n\n" + error.localizedDescription
        alert.addButton(withTitle: L10n.openSystemSettings)
        alert.addButton(withTitle: L10n.cancel)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

final class OverlayWindow: NSWindow {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    // 不让系统把窗口挤到菜单栏下面
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
