import AppKit

/// 渲染演示截图（网站、README 用）：SnapMark --snapshot <输出目录>
/// 用一张虚构的"订单详情"窗口作为桌面，叠上真实的选区、标注和工具条，输出 snapmark-zh.png / snapmark-en.png
@MainActor
enum Snapshot {
    private static let canvas = CGSize(width: 960, height: 600)
    private static let scale: CGFloat = 2
    /// OverlayView 对 controller 是 unowned 引用，这里要持有它
    private static let controller = CaptureController()

    static func run(outputDirectory: URL) {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for language in [Language.zh, .en] {
            L10n.override = language
            let url = outputDirectory.appendingPathComponent("snapmark-\(language.rawValue).png")
            render(Demo(chinese: language == .zh), to: url)
            print("✅ \(url.path)")
        }
        L10n.override = nil
    }

    // MARK: - 演示内容

    private struct Demo {
        let title, customer, name, phoneLabel, phone, addressLabel, address, order, amountLabel, amount: String
        let statusLabel, status, button, note: String

        init(chinese: Bool) {
            if chinese {
                (title, customer, name, phoneLabel, phone) = ("订单详情 #20261010", "客户信息", "姓名", "电话", "138 0013 8000")
                (addressLabel, address, order) = ("地址", "上海市浦东新区世纪大道 100 号", "订单状态")
                (amountLabel, amount, statusLabel) = ("金额", "¥ 1,280.00", "状态")
                (status, button, note) = ("发货失败：收件地址缺少楼层和门牌号", "重新提交", "地址不全，需联系客户补充")
            } else {
                (title, customer, name, phoneLabel, phone) = ("Order #20261010", "Customer", "Name", "Phone", "+1 (415) 555-0132")
                (addressLabel, address, order) = ("Address", "100 Market Street, San Francisco", "Order Status")
                (amountLabel, amount, statusLabel) = ("Amount", "$ 1,280.00", "Status")
                (status, button, note) = ("Shipping failed: missing apartment number", "Resubmit", "Ask the customer for the full address")
            }
        }
    }

    private static let window = CGRect(x: 190, y: 110, width: 580, height: 400)
    private static let labelX = window.minX + 32
    private static let valueX = window.minX + 120
    private static func rowY(_ i: Int) -> CGFloat { window.maxY - 36 - 36 - CGFloat(i) * 34 }

    private static func render(_ demo: Demo, to url: URL) {
        let desktop = drawDesktop(demo)
        let bounds = CGRect(origin: .zero, size: canvas)

        // 和真实截图时一样的结构：冻结的桌面 + 遮罩层
        let container = NSView(frame: bounds)
        let background = NSImageView(frame: bounds)
        background.image = NSImage(cgImage: desktop, size: canvas)
        background.imageScaling = .scaleAxesIndependently
        let overlay = OverlayView(frame: bounds, image: desktop, windowRects: [], controller: controller)
        container.addSubview(background)
        container.addSubview(overlay)

        let red = Toolbar.colors[0]
        let phoneWidth = textWidth(demo.phone, size: 15)
        let statusWidth = textWidth(demo.status, size: 15)
        let statusBox = CGRect(x: labelX - 10, y: rowY(6) - 17, width: valueX + statusWidth + 12 - (labelX - 10), height: 34)
        let noteFont = NSFont.systemFont(ofSize: 20, weight: .semibold)
        let noteTopLeft = CGPoint(x: window.maxX - 24 - textWidth(demo.note, size: 20, weight: .semibold), y: window.minY + 78)
        let arrowTail = CGPoint(x: window.maxX - 84, y: noteTopLeft.y + 6) // 从文字右上方指向红框

        overlay.loadDemo(
            selection: window,
            annotations: [
                .mosaic([CGPoint(x: valueX - 2, y: rowY(2)), CGPoint(x: valueX + phoneWidth + 2, y: rowY(2))], 26),
                .rect(statusBox, red, 4),
                .arrow(arrowTail, CGPoint(x: min(statusBox.maxX - 80, arrowTail.x - 140), y: statusBox.minY - 6), red, 5),
                .text(demo.note, Annotation.textFrame(demo.note, font: noteFont, topLeft: noteTopLeft), noteFont, red),
            ],
            tool: .rect
        )

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width * scale), pixelsHigh: Int(canvas.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = canvas
        container.layoutSubtreeIfNeeded()
        container.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    // MARK: - 虚构桌面

    private static func drawDesktop(_ demo: Demo) -> CGImage {
        let ctx = CGContext(data: nil, width: Int(canvas.width * scale), height: Int(canvas.height * scale),
                            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }

        // 壁纸
        let wallpaper = CGGradient(colorsSpace: nil, colors: [rgb(0x1E3A8A), rgb(0x0E7490), rgb(0x10B981)] as CFArray, locations: [0, 0.6, 1])!
        ctx.drawLinearGradient(wallpaper, start: CGPoint(x: 0, y: canvas.height), end: CGPoint(x: canvas.width, y: 0), options: [])
        ctx.setFillColor(rgb(0xFFFFFF, 0.06))
        ctx.fillEllipse(in: CGRect(x: -120, y: 300, width: 520, height: 520))
        ctx.fillEllipse(in: CGRect(x: 640, y: -200, width: 480, height: 480))

        // 窗口
        let path = CGPath(roundedRect: window, cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: rgb(0x000000, 0.35))
        ctx.addPath(path)
        ctx.setFillColor(rgb(0xFFFFFF))
        ctx.fillPath()
        ctx.restoreGState()

        // 标题栏
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setFillColor(rgb(0xF3F4F6))
        ctx.fill(CGRect(x: window.minX, y: window.maxY - 36, width: window.width, height: 36))
        ctx.setFillColor(rgb(0xE5E7EB))
        ctx.fill(CGRect(x: window.minX, y: window.maxY - 37, width: window.width, height: 1))
        ctx.restoreGState()
        for (i, c) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            ctx.setFillColor(rgb(UInt32(c)))
            ctx.fillEllipse(in: CGRect(x: window.minX + 16 + CGFloat(i) * 20, y: window.maxY - 24, width: 12, height: 12))
        }
        text(demo.title, size: 13, weight: .semibold, color: 0x374151, x: window.midX - textWidth(demo.title, size: 13, weight: .semibold) / 2, centerY: window.maxY - 18)

        // 内容
        let rows: [(String, String?, UInt32)] = [
            (demo.customer, nil, 0), (demo.name, demo.customer == "客户信息" ? "张晓明" : "Alex Chen", 0x111827),
            (demo.phoneLabel, demo.phone, 0x111827), (demo.addressLabel, demo.address, 0x111827),
            (demo.order, nil, 0), (demo.amountLabel, demo.amount, 0x111827), (demo.statusLabel, demo.status, 0xDC2626),
        ]
        for (i, row) in rows.enumerated() {
            if let value = row.1 {
                text(row.0, size: 15, weight: .regular, color: 0x6B7280, x: labelX, centerY: rowY(i))
                text(value, size: 15, weight: .medium, color: row.2, x: valueX, centerY: rowY(i))
            } else {
                text(row.0, size: 16, weight: .bold, color: 0x111827, x: labelX, centerY: rowY(i))
            }
        }

        // 按钮
        let buttonWidth = textWidth(demo.button, size: 14, weight: .semibold) + 32
        let button = CGRect(x: labelX, y: window.minY + 24, width: buttonWidth, height: 32)
        ctx.addPath(CGPath(roundedRect: button, cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.setFillColor(rgb(0x2563EB))
        ctx.fillPath()
        text(demo.button, size: 14, weight: .semibold, color: 0xFFFFFF, x: button.minX + 16, centerY: button.midY)

        return ctx.makeImage()!
    }

    // MARK: - 工具

    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func attributed(_ s: String, size: CGFloat, weight: NSFont.Weight, color: UInt32 = 0) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: NSColor(cgColor: rgb(color))!,
        ])
    }

    private static func textWidth(_ s: String, size: CGFloat, weight: NSFont.Weight = .medium) -> CGFloat {
        ceil(attributed(s, size: size, weight: weight).size().width)
    }

    private static func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: UInt32, x: CGFloat, centerY: CGFloat) {
        let str = attributed(s, size: size, weight: weight, color: color)
        str.draw(at: CGPoint(x: x, y: centerY - str.size().height / 2))
    }
}
