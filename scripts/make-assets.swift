// 生成应用图标和 DMG 安装背景
//   swift scripts/make-assets.swift
// 输出：Resources/AppIcon.icns、Resources/dmg-background.tiff（1x + 2x）
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources")
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("snipnote-assets-\(getpid())")
try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// 在 width×height 点的画布上作画，按 scale 倍输出 PNG
func renderPNG(width: Int, height: Int, scale: CGFloat, to url: URL, draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: Int(CGFloat(width) * scale), height: Int(CGFloat(height) * scale),
                        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = NSSize(width: width, height: height) // 写入正确的 DPI，2x 图是 144 dpi
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

func run(_ tool: String, _ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    try! p.run()
    p.waitUntilExit()
    precondition(p.terminationStatus == 0, "\(tool) failed")
}

/// 和应用里一样的箭头：尾部细、头部粗
func arrowPath(from a: CGPoint, to b: CGPoint, width w: CGFloat) -> CGPath {
    let length = hypot(b.x - a.x, b.y - a.y)
    let head = max(14, w * 4.5), half = head * 0.45, neck = length - head * 0.75
    let path = CGMutablePath()
    path.addLines(between: [
        CGPoint(x: 0, y: -w * 0.15), CGPoint(x: neck, y: -w * 0.6), CGPoint(x: length - head, y: -half),
        CGPoint(x: length, y: 0), CGPoint(x: length - head, y: half), CGPoint(x: neck, y: w * 0.6),
        CGPoint(x: 0, y: w * 0.15),
    ])
    path.closeSubpath()
    var t = CGAffineTransform(translationX: a.x, y: a.y).rotated(by: atan2(b.y - a.y, b.x - a.x))
    return path.copy(using: &t)!
}

// MARK: - 应用图标（1024 画布，按 macOS 图标网格留出边距）

func drawIcon(_ ctx: CGContext) {
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // 投影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.3))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0x059669))
    ctx.fillPath()
    ctx.restoreGState()

    // 绿色渐变底
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: nil, colors: [color(0x34D399), color(0x047857)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // 截图选区：白色虚线框 + 四角加粗
    let frame = CGRect(x: 250, y: 290, width: 524, height: 444)
    ctx.setStrokeColor(color(0xFFFFFF, 0.9))
    ctx.setLineWidth(14)
    ctx.setLineDash(phase: 0, lengths: [34, 26])
    ctx.stroke(frame)
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.setLineWidth(34)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let arm: CGFloat = 92
    for (corner, dx, dy) in [(CGPoint(x: frame.minX, y: frame.minY), 1.0, 1.0), (CGPoint(x: frame.maxX, y: frame.minY), -1.0, 1.0),
                             (CGPoint(x: frame.minX, y: frame.maxY), 1.0, -1.0), (CGPoint(x: frame.maxX, y: frame.maxY), -1.0, -1.0)] {
        ctx.addLines(between: [CGPoint(x: corner.x, y: corner.y + dy * arm), corner, CGPoint(x: corner.x + dx * arm, y: corner.y)])
    }
    ctx.strokePath()

    // 红色标注箭头，白色描边保证在绿色上醒目
    let arrow = arrowPath(from: CGPoint(x: 345, y: 385), to: CGPoint(x: 660, y: 640), width: 34)
    ctx.addPath(arrow)
    ctx.setStrokeColor(color(0xFFFFFF))
    ctx.setLineWidth(18)
    ctx.strokePath()
    ctx.addPath(arrow)
    ctx.setFillColor(color(0xEF4444))
    ctx.fillPath()
}

let iconset = tmp.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        let px = CGFloat(size * scale) / 1024
        renderPNG(width: size, height: size, scale: CGFloat(scale), to: iconset.appendingPathComponent(name)) { ctx in
            ctx.scaleBy(x: px / CGFloat(scale), y: px / CGFloat(scale))
            drawIcon(ctx)
        }
    }
}
run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path])
renderPNG(width: 1024, height: 1024, scale: 1, to: tmp.appendingPathComponent("icon-preview.png")) { drawIcon($0) }

// MARK: - DMG 背景（图标中心在 (160,190) 和 (480,190)，以窗口内容区左上角为原点）
// 窗口高度包含标题栏，内容区实际约 400 高；背景多画一截，标题栏高度不同时底部也不会露白

let W: CGFloat = 640, H: CGFloat = 440

func drawText(_ s: String, size: CGFloat, weight: NSFont.Weight, hex: UInt32, centerY yFromTop: CGFloat) {
    let str = NSAttributedString(string: s, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(cgColor: color(hex))!,
    ])
    let sz = str.size()
    str.draw(at: CGPoint(x: (W - sz.width) / 2, y: H - yFromTop - sz.height / 2))
}

func drawBackground(_ ctx: CGContext) {
    let gradient = CGGradient(colorsSpace: nil, colors: [color(0xF8FAFC), color(0xE8EDF3)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

    drawText("Snipnote", size: 24, weight: .bold, hex: 0x1F2937, centerY: 48)

    // 两个图标之间的箭头
    let y = H - 190
    ctx.setStrokeColor(color(0x10B981))
    ctx.setLineWidth(5)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [2, 12])
    ctx.move(to: CGPoint(x: 258, y: y))
    ctx.addLine(to: CGPoint(x: 372, y: y))
    ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: 368, y: y + 14))
    ctx.addLine(to: CGPoint(x: 384, y: y))
    ctx.addLine(to: CGPoint(x: 368, y: y - 14))
    ctx.strokePath()

    drawText("将 Snipnote 拖到 Applications 文件夹即可完成安装", size: 14, weight: .medium, hex: 0x374151, centerY: 330)
    drawText("Drag Snipnote to the Applications folder to install", size: 12, weight: .regular, hex: 0x6B7280, centerY: 354)
}

let bg1 = tmp.appendingPathComponent("dmg-background.png")
let bg2 = tmp.appendingPathComponent("dmg-background@2x.png")
renderPNG(width: Int(W), height: Int(H), scale: 1, to: bg1, draw: drawBackground)
renderPNG(width: Int(W), height: Int(H), scale: 2, to: bg2, draw: drawBackground)
// 合成多分辨率 TIFF，Retina 屏上也清晰
run("/usr/bin/tiffutil", ["-cathidpicheck", bg1.path, bg2.path, "-out", resources.appendingPathComponent("dmg-background.tiff").path])

print("✅ Resources/AppIcon.icns")
print("✅ Resources/dmg-background.tiff")
print("预览：\(tmp.path)")
