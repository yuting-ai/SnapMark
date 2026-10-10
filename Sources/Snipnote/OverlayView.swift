import AppKit

/// 盖在冻结截图上的透明层：负责框选、调整选区、标注和导出
final class OverlayView: NSView, NSTextViewDelegate {
    private enum Drag {
        case idle
        case creating(CGPoint)
        case moving(CGPoint, CGRect)
        case resizing(Handle, CGRect)
        case drawing(CGPoint)
        case movingAnnotation(CGPoint, Annotation)
    }

    private struct Handle {
        let left, right, bottom, top: Bool
    }

    private let image: CGImage
    private let windowRects: [CGRect]
    private unowned let controller: CaptureController
    private lazy var mosaicImage: CGImage? = Self.pixelate(image, block: 10 * scale)

    private(set) var selection: CGRect?
    private var hoverRect: CGRect?
    private var annotations: [Annotation] = []
    private var current: Annotation?
    private var tool: Tool?
    private var color = Toolbar.colors[0]
    private var drag = Drag.idle
    private let toolbar = Toolbar()

    /// 选中的已有标注
    private var selectedIndex: Int?
    /// 每次改动前的快照，用于撤销
    private var undoStack: [[Annotation]] = []
    /// 一次连续编辑（拖滑块、拖动标注）只记一次撤销点
    private var editCheckpointTaken = false

    private var textView: NSTextView?
    private var textAnchor = CGPoint.zero // 文字框左上角
    private var reeditingText = false

    /// 截图像素 / 视图点
    private var scale: CGFloat { CGFloat(image.width) / max(bounds.width, 1) }

    init(frame: CGRect, image: CGImage, windowRects: [CGRect], controller: CaptureController) {
        self.image = image
        self.windowRects = windowRects
        self.controller = controller
        super.init(frame: frame)

        toolbar.isHidden = true
        addSubview(toolbar)
        toolbar.onTool = { [weak self] t in self?.setTool(t) }
        toolbar.onColor = { [weak self] c in self?.applyColor(c) }
        toolbar.onSize = { [weak self] size in self?.applySize(size) }
        toolbar.onUndo = { [weak self] in self?.undo() }
        toolbar.onSave = { [weak self] in self?.controller.confirm(save: true) }
        toolbar.onCancel = { [weak self] in self?.controller.cancel() }
        toolbar.onDone = { [weak self] in self?.controller.confirm(save: false) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    // MARK: - 尺寸设置（会记住，下次截图沿用）

    private static func sizeKey(_ kind: Tool) -> String {
        switch kind {
        case .text: "size.text"
        case .mosaic: "size.mosaic"
        default: "size.line" // 矩形、椭圆、箭头、画笔共用线宽
        }
    }

    private func preferredSize(_ kind: Tool) -> CGFloat {
        let v = UserDefaults.standard.double(forKey: Self.sizeKey(kind))
        return v > 0 ? CGFloat(v) : kind.defaultSize
    }

    private func setPreferredSize(_ size: CGFloat, for kind: Tool) {
        UserDefaults.standard.set(Double(size), forKey: Self.sizeKey(kind))
    }

    private var textFont: NSFont { .systemFont(ofSize: preferredSize(.text), weight: .semibold) }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let hole = selection ?? hoverRect
        ctx.setFillColor(NSColor(white: 0, alpha: 0.4).cgColor)
        if let hole {
            ctx.addRect(bounds)
            ctx.addRect(hole)
            ctx.fillPath(using: .evenOdd)
        } else {
            ctx.fill(bounds)
        }

        if let sel = selection {
            ctx.saveGState()
            ctx.clip(to: sel)
            drawAnnotations(ctx)
            ctx.restoreGState()
        }

        if let hole {
            let w: CGFloat = selection == nil ? 3 : 1
            ctx.setStrokeColor(Toolbar.accent.cgColor)
            ctx.setLineWidth(w)
            ctx.stroke(hole.insetBy(dx: -w / 2, dy: -w / 2))
        }

        if let sel = selection {
            drawHandles(sel, ctx)
            drawSizeLabel(sel)
        }

        if let i = selectedIndex {
            drawSelectionBox(annotations[i].bounds.insetBy(dx: -4, dy: -4), ctx)
        }
    }

    private func drawAnnotations(_ ctx: CGContext) {
        for a in annotations + [current].compactMap({ $0 }) {
            a.draw(in: ctx, mosaic: mosaicImage, canvas: bounds)
        }
    }

    /// 选中标注时的黑白虚线框，在任何背景上都看得清
    private func drawSelectionBox(_ r: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.setLineWidth(1)
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.stroke(r)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        ctx.stroke(r)
        ctx.restoreGState()
    }

    private func drawHandles(_ r: CGRect, _ ctx: CGContext) {
        ctx.setFillColor(Toolbar.accent.cgColor)
        for x in [r.minX, r.midX, r.maxX] {
            for y in [r.minY, r.midY, r.maxY] where !(x == r.midX && y == r.midY) {
                ctx.fill(CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
            }
        }
    }

    private func drawSizeLabel(_ sel: CGRect) {
        let text = "\(Int((sel.width * scale).rounded())) × \(Int((sel.height * scale).rounded()))"
        let str = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
        let size = str.size()
        var box = CGRect(x: sel.minX, y: sel.maxY + 5, width: size.width + 10, height: size.height + 4)
        if box.maxY > bounds.maxY {
            box.origin = CGPoint(x: sel.minX + 5, y: sel.maxY - box.height - 5)
        }
        box.origin.x = min(box.minX, bounds.maxX - box.width)
        NSColor(white: 0, alpha: 0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
        str.draw(at: CGPoint(x: box.minX + 5, y: box.minY + 2))
    }

    // MARK: - 导出

    /// 把选区和标注合成为一张原始分辨率的图
    func render() -> (CGImage, CGSize)? {
        commitText()
        guard let sel = selection, sel.width >= 1, sel.height >= 1 else { return nil }
        let s = scale
        guard let ctx = CGContext(data: nil,
                                  width: Int((sel.width * s).rounded()),
                                  height: Int((sel.height * s).rounded()),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: Self.rgbSpace(of: image),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: -sel.minX, y: -sel.minY)
        ctx.interpolationQuality = .none
        ctx.draw(image, in: bounds)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        drawAnnotations(ctx)
        NSGraphicsContext.restoreGraphicsState()

        return ctx.makeImage().map { ($0, sel.size) }
    }

    private static func rgbSpace(of image: CGImage) -> CGColorSpace {
        if let cs = image.colorSpace, cs.model == .rgb { return cs }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    /// 缩小再用最近邻放大，就是马赛克
    private static func pixelate(_ image: CGImage, block: CGFloat) -> CGImage? {
        let w = max(1, Int(CGFloat(image.width) / block))
        let h = max(1, Int(CGFloat(image.height) / block))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: rgbSpace(of: image),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: - 鼠标

    func updateHover(screenPoint: CGPoint) {
        guard let window else { return }
        updateHover(convert(window.convertPoint(fromScreen: screenPoint), from: nil))
    }

    private func updateHover(_ p: CGPoint) {
        guard selection == nil, case .idle = drag else { return }
        if let active = controller.activeView, active !== self {
            hoverRect = nil
        } else {
            // 鼠标下最前面的窗口；桌面上就是整个屏幕
            hoverRect = snap(windowRects.first { $0.contains(p) } ?? bounds)
        }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let p = point(event)
        updateHover(p)
        updateCursor(at: p)
    }

    override func mouseExited(with event: NSEvent) {
        if selection == nil {
            hoverRect = nil
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = point(event)
        if commitText() { return }
        if let active = controller.activeView, active !== self { return }
        window?.makeKey()

        if let sel = selection {
            let hit = sel.contains(p) ? hitAnnotation(at: p) : nil
            if event.clickCount == 2, sel.contains(p) {
                // 双击文字重新编辑，双击其他地方完成截图
                if let hit, case .text = annotations[hit] {
                    reeditText(at: hit)
                } else {
                    controller.confirm(save: false)
                }
                return
            }
            if let h = handle(at: p, in: sel) {
                select(nil)
                drag = .resizing(h, sel)
            } else if let hit {
                // 点中已有标注：选中，可以拖动、改粗细/字号/颜色
                select(hit)
                drag = .movingAnnotation(p, annotations[hit])
                NSCursor.closedHand.set()
            } else if sel.contains(p), let tool {
                select(nil)
                if tool == .text {
                    beginText(at: p)
                    return
                }
                let start = clamp(p, to: sel)
                drag = .drawing(start)
                current = newAnnotation(tool, at: start)
            } else if sel.contains(p) {
                select(nil)
                drag = .moving(p, sel)
                NSCursor.closedHand.set()
            } else if annotations.isEmpty {
                // 还没标注时，在选区外拖动可以重新框选
                selection = nil
                drag = .creating(clamp(p, to: bounds))
            } else {
                select(nil)
                return
            }
        } else {
            controller.activeView = self
            drag = .creating(clamp(p, to: bounds))
        }
        layoutToolbar()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = point(event)
        switch drag {
        case .idle:
            return
        case let .creating(start):
            let q = clamp(p, to: bounds)
            guard selection != nil || hypot(q.x - start.x, q.y - start.y) > 3 else { return }
            hoverRect = nil
            selection = snap(rect(start, q))
        case let .moving(start, original):
            var r = original.offsetBy(dx: p.x - start.x, dy: p.y - start.y)
            r.origin.x = min(max(0, r.minX), bounds.width - r.width)
            r.origin.y = min(max(0, r.minY), bounds.height - r.height)
            selection = snap(r)
        case let .resizing(h, o):
            let q = clamp(p, to: bounds)
            let a = CGPoint(x: h.left ? q.x : o.minX, y: h.bottom ? q.y : o.minY)
            let b = CGPoint(x: h.right ? q.x : o.maxX, y: h.top ? q.y : o.maxY)
            selection = snap(rect(a, b))
        case let .drawing(start):
            guard let sel = selection else { return }
            current = current?.updated(from: start, to: clamp(p, to: sel))
        case let .movingAnnotation(start, original):
            modifySelected { _ in original.offsetBy(dx: p.x - start.x, dy: p.y - start.y) }
        }
        layoutToolbar()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let p = point(event)
        switch drag {
        case .creating:
            if selection == nil, let hover = hoverRect {
                // 单击：选中鼠标下的窗口
                selection = hover
                hoverRect = nil
            } else if let sel = selection, sel.width < 4 || sel.height < 4 {
                selection = nil
            }
            if selection == nil { controller.activeView = nil }
        case .drawing:
            if let c = current, c.isMeaningful {
                checkpoint()
                annotations.append(c)
                select(annotations.count - 1) // 画完自动选中，可以马上调粗细
            }
            current = nil
        default:
            break
        }
        drag = .idle
        updateHover(p)
        layoutToolbar()
        updateCursor(at: p)
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        commitText()
        if selection != nil, annotations.isEmpty, controller.activeView === self {
            // 右键：先取消选区，再按一次退出
            selection = nil
            controller.activeView = nil
            setTool(nil)
            toolbar.setTool(nil)
            updateHover(point(event))
        } else {
            controller.cancel()
        }
    }

    private func updateCursor(at p: CGPoint) {
        if !toolbar.isHidden, toolbar.frame.contains(p) {
            NSCursor.arrow.set()
            return
        }
        guard let sel = selection else {
            NSCursor.crosshair.set()
            return
        }
        if let h = handle(at: p, in: sel) {
            let horizontal = h.left || h.right, vertical = h.top || h.bottom
            if horizontal && !vertical { NSCursor.resizeLeftRight.set() }
            else if vertical && !horizontal { NSCursor.resizeUpDown.set() }
            else { NSCursor.crosshair.set() }
        } else if sel.contains(p) {
            if hitAnnotation(at: p) != nil {
                NSCursor.openHand.set()
                return
            }
            switch tool {
            case nil: NSCursor.openHand.set()
            case .text: NSCursor.iBeam.set()
            default: NSCursor.crosshair.set()
            }
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        let target = controller.activeView ?? self
        let cmd = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 53: // Esc
            controller.cancel()
        case 36, 76: // Return / Enter
            controller.confirm(save: false)
        case 51, 117: // Delete / Forward Delete：删除选中的标注
            target.deleteSelected()
        case 123: target.nudge(dx: -1, dy: 0, event)
        case 124: target.nudge(dx: 1, dy: 0, event)
        case 125: target.nudge(dx: 0, dy: -1, event)
        case 126: target.nudge(dx: 0, dy: 1, event)
        default:
            switch (cmd, event.charactersIgnoringModifiers?.lowercased()) {
            case (true, "z"): target.undo()
            case (true, "c"): controller.confirm(save: false)
            case (true, "s"): controller.confirm(save: true)
            default: super.keyDown(with: event)
            }
        }
    }

    /// 方向键：有选中的标注就移动标注，否则移动选区
    private func nudge(dx: CGFloat, dy: CGFloat, _ event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        if selectedIndex != nil {
            modifySelected { $0.offsetBy(dx: dx * step, dy: dy * step) }
            return
        }
        guard var r = selection else { return }
        r = r.offsetBy(dx: dx * step, dy: dy * step)
        r.origin.x = min(max(0, r.minX), bounds.width - r.width)
        r.origin.y = min(max(0, r.minY), bounds.height - r.height)
        selection = r
        layoutToolbar()
        needsDisplay = true
    }

    // MARK: - 标注的选中与编辑

    private func hitAnnotation(at p: CGPoint) -> Int? {
        annotations.indices.reversed().first { i in
            // 用马赛克工具时允许在已有马赛克上继续涂
            if tool == .mosaic, annotations[i].kind == .mosaic { return false }
            return annotations[i].hitTest(p)
        }
    }

    private func select(_ index: Int?) {
        selectedIndex = index
        editCheckpointTaken = false
        updateOptions()
        needsDisplay = true
    }

    private func checkpoint() {
        undoStack.append(annotations)
    }

    private func modifySelected(_ change: (Annotation) -> Annotation) {
        guard let i = selectedIndex else { return }
        if !editCheckpointTaken {
            checkpoint()
            editCheckpointTaken = true
        }
        annotations[i] = change(annotations[i])
        needsDisplay = true
    }

    private func deleteSelected() {
        guard let i = selectedIndex else { return }
        checkpoint()
        annotations.remove(at: i)
        select(nil)
    }

    private func undo() {
        if commitText() { return }
        guard let previous = undoStack.popLast() else { return }
        annotations = previous
        select(nil)
    }

    /// 滑块：改选中的标注，同时作为之后新标注的默认值
    private func applySize(_ size: CGFloat) {
        guard let kind = optionsKind else { return }
        setPreferredSize(size, for: kind)
        if let tv = textView {
            tv.font = textFont
            resizeTextView()
        } else if selectedIndex != nil {
            modifySelected { $0.with(size: size) }
        }
    }

    private func applyColor(_ c: NSColor) {
        color = c
        if let tv = textView {
            tv.textColor = c
            tv.insertionPointColor = c
        } else if selectedIndex != nil {
            // 换颜色算一次独立的撤销点
            editCheckpointTaken = false
            modifySelected { $0.with(color: c) }
            editCheckpointTaken = false
        }
    }

    /// 第二行选项对应的标注类型：选中标注时跟随标注，否则跟随当前工具
    private var optionsKind: Tool? {
        if textView != nil { return .text }
        if let i = selectedIndex { return annotations[i].kind }
        return tool
    }

    private func updateOptions() {
        let kind = optionsKind
        if let i = selectedIndex, textView == nil {
            toolbar.configureOptions(kind: kind, size: annotations[i].size, color: annotations[i].color)
        } else {
            toolbar.configureOptions(kind: kind, size: kind.map(preferredSize) ?? 0, color: color)
        }
        layoutToolbar()
    }

    // MARK: - 工具

    private func setTool(_ t: Tool?) {
        commitText()
        tool = t
        select(nil)
    }

    private func newAnnotation(_ tool: Tool, at p: CGPoint) -> Annotation? {
        let size = preferredSize(tool)
        switch tool {
        case .rect: return .rect(CGRect(origin: p, size: .zero), color, size)
        case .ellipse: return .ellipse(CGRect(origin: p, size: .zero), color, size)
        case .arrow: return .arrow(p, p, color, size)
        case .pen: return .pen([p], color, size)
        case .mosaic: return .mosaic([p], size)
        case .text: return nil
        }
    }

    private func layoutToolbar() {
        let dragging: Bool
        switch drag {
        case .creating, .moving, .resizing: dragging = true
        default: dragging = false
        }
        guard let sel = selection, !dragging else {
            toolbar.isHidden = true
            return
        }
        toolbar.isHidden = false
        toolbar.layoutSubtreeIfNeeded()
        let size = toolbar.fittingSize
        var x = sel.maxX - size.width
        x = min(max(4, x), bounds.width - size.width - 4)
        var y = sel.minY - size.height - 8
        if y < 4 {
            y = sel.maxY + 8
            if y + size.height > bounds.height - 4 { y = sel.minY + 8 }
        }
        toolbar.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    // MARK: - 文字

    private func beginText(at topLeft: CGPoint, string: String = "", font: NSFont? = nil, color textColor: NSColor? = nil) {
        let tv = NSTextView(frame: .zero)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.font = font ?? textFont
        tv.textColor = textColor ?? color
        tv.insertionPointColor = textColor ?? color
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: 10_000, height: 10_000)
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = false
        tv.wantsLayer = true
        tv.layer?.borderWidth = 1
        tv.layer?.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        tv.string = string
        tv.delegate = self

        textAnchor = topLeft
        textView = tv
        addSubview(tv, positioned: .below, relativeTo: toolbar)
        resizeTextView()
        window?.makeFirstResponder(tv)
        tv.selectAll(nil)
        updateOptions()
    }

    /// 双击已有文字：拿出来重新编辑
    private func reeditText(at index: Int) {
        guard case let .text(s, r, font, c) = annotations[index] else { return }
        checkpoint()
        annotations.remove(at: index)
        select(nil)
        // 滑块和颜色跟随这段文字
        setPreferredSize(font.pointSize, for: .text)
        color = c
        reeditingText = true
        beginText(at: CGPoint(x: r.minX, y: r.maxY), string: s, font: font, color: c)
    }

    /// 文字框随内容伸缩，左上角固定
    private func resizeTextView() {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer, let font = tv.font else { return }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let width = max(ceil(used.width) + 4, 12)
        let height = max(ceil(used.height), lm.defaultLineHeight(for: font))
        tv.frame = CGRect(x: textAnchor.x, y: textAnchor.y - height, width: width, height: height)
    }

    func textDidChange(_ notification: Notification) {
        resizeTextView()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // 回车 / Esc 结束输入；⌥↩ 换行
        if selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:)) {
            commitText()
            return true
        }
        return false
    }

    @discardableResult
    private func commitText() -> Bool {
        guard let tv = textView else { return false }
        let a = Annotation.text(tv.string, tv.frame, tv.font ?? textFont, tv.textColor ?? color)
        tv.removeFromSuperview()
        textView = nil
        if a.isMeaningful {
            if !reeditingText { checkpoint() } // 重新编辑时，开始编辑那一刻已经记过撤销点
            annotations.append(a)
            select(annotations.count - 1) // 选中刚输入的文字，可以直接拖滑块改字号
        } else {
            select(nil)
        }
        reeditingText = false
        window?.makeFirstResponder(self)
        needsDisplay = true
        return true
    }

    // MARK: - 演示截图

    /// --snapshot 用：直接设置选区、标注和当前工具
    func loadDemo(selection: CGRect, annotations: [Annotation], tool: Tool?) {
        controller.activeView = self
        self.selection = selection
        hoverRect = nil
        self.annotations = annotations
        undoStack = []
        setTool(tool)
        toolbar.setTool(tool)
        needsDisplay = true
    }

    // MARK: - 几何工具

    private func point(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func clamp(_ p: CGPoint, to r: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
    }

    private func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// 对齐到物理像素，保证导出的图边缘清晰
    private func snap(_ r: CGRect) -> CGRect {
        let s = scale
        let x1 = (r.minX * s).rounded() / s, y1 = (r.minY * s).rounded() / s
        let x2 = (r.maxX * s).rounded() / s, y2 = (r.maxY * s).rounded() / s
        return CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
    }

    private func handle(at p: CGPoint, in r: CGRect) -> Handle? {
        let tol: CGFloat = 6
        let inX = p.x > r.minX - tol && p.x < r.maxX + tol
        let inY = p.y > r.minY - tol && p.y < r.maxY + tol
        let nearL = abs(p.x - r.minX) <= tol && inY
        let nearR = abs(p.x - r.maxX) <= tol && inY && !nearL
        let nearB = abs(p.y - r.minY) <= tol && inX
        let nearT = abs(p.y - r.maxY) <= tol && inX && !nearB
        guard nearL || nearR || nearB || nearT else { return nil }
        return Handle(left: nearL, right: nearR, bottom: nearB, top: nearT)
    }
}
