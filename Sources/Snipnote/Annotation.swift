import AppKit

enum Tool: CaseIterable {
    case rect, ellipse, arrow, pen, text, mosaic

    var symbol: String {
        switch self {
        case .rect: "rectangle"
        case .ellipse: "circle"
        case .arrow: "arrow.up.right"
        case .pen: "scribble"
        case .text: "textformat"
        case .mosaic: "checkerboard.rectangle"
        }
    }

    var title: String { L10n.toolName(self) }

    /// 滑块范围：文字是字号，马赛克是笔刷宽度，其余是线宽
    var sizeRange: ClosedRange<CGFloat> {
        switch self {
        case .text: 12...72
        case .mosaic: 8...60
        default: 1...20
        }
    }

    var defaultSize: CGFloat {
        switch self {
        case .text: 22
        case .mosaic: 24
        default: 4
        }
    }
}

/// 一个标注，坐标都是遮罩视图里的点坐标（左下角原点）
enum Annotation {
    case rect(CGRect, NSColor, CGFloat)
    case ellipse(CGRect, NSColor, CGFloat)
    case arrow(CGPoint, CGPoint, NSColor, CGFloat)
    case pen([CGPoint], NSColor, CGFloat)
    case mosaic([CGPoint], CGFloat)
    case text(String, CGRect, NSFont, NSColor)

    var isMeaningful: Bool {
        switch self {
        case let .rect(r, _, _), let .ellipse(r, _, _):
            return r.width > 2 && r.height > 2
        case let .arrow(a, b, _, _):
            return hypot(b.x - a.x, b.y - a.y) > 4
        case let .pen(points, _, _), let .mosaic(points, _):
            return points.count > 1
        case let .text(s, _, _, _):
            return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var kind: Tool {
        switch self {
        case .rect: .rect
        case .ellipse: .ellipse
        case .arrow: .arrow
        case .pen: .pen
        case .mosaic: .mosaic
        case .text: .text
        }
    }

    var color: NSColor? {
        switch self {
        case let .rect(_, c, _), let .ellipse(_, c, _), let .arrow(_, _, c, _), let .pen(_, c, _), let .text(_, _, _, c): c
        case .mosaic: nil
        }
    }

    /// 线宽 / 笔刷宽度 / 字号
    var size: CGFloat {
        switch self {
        case let .rect(_, _, w), let .ellipse(_, _, w), let .arrow(_, _, _, w), let .pen(_, _, w), let .mosaic(_, w): w
        case let .text(_, _, font, _): font.pointSize
        }
    }

    func with(size: CGFloat) -> Annotation {
        switch self {
        case let .rect(r, c, _): return .rect(r, c, size)
        case let .ellipse(r, c, _): return .ellipse(r, c, size)
        case let .arrow(a, b, c, _): return .arrow(a, b, c, size)
        case let .pen(pts, c, _): return .pen(pts, c, size)
        case let .mosaic(pts, _): return .mosaic(pts, size)
        case let .text(s, r, font, c):
            // 改字号时保持左上角不动
            let newFont = NSFont(descriptor: font.fontDescriptor, size: size) ?? .systemFont(ofSize: size, weight: .semibold)
            return .text(s, Self.textFrame(s, font: newFont, topLeft: CGPoint(x: r.minX, y: r.maxY)), newFont, c)
        }
    }

    func with(color: NSColor) -> Annotation {
        switch self {
        case let .rect(r, _, w): .rect(r, color, w)
        case let .ellipse(r, _, w): .ellipse(r, color, w)
        case let .arrow(a, b, _, w): .arrow(a, b, color, w)
        case let .pen(pts, _, w): .pen(pts, color, w)
        case .mosaic: self
        case let .text(s, r, font, _): .text(s, r, font, color)
        }
    }

    func offsetBy(dx: CGFloat, dy: CGFloat) -> Annotation {
        let move = { (p: CGPoint) in CGPoint(x: p.x + dx, y: p.y + dy) }
        switch self {
        case let .rect(r, c, w): return .rect(r.offsetBy(dx: dx, dy: dy), c, w)
        case let .ellipse(r, c, w): return .ellipse(r.offsetBy(dx: dx, dy: dy), c, w)
        case let .arrow(a, b, c, w): return .arrow(move(a), move(b), c, w)
        case let .pen(pts, c, w): return .pen(pts.map(move), c, w)
        case let .mosaic(pts, w): return .mosaic(pts.map(move), w)
        case let .text(s, r, font, c): return .text(s, r.offsetBy(dx: dx, dy: dy), font, c)
        }
    }

    /// 点中线条附近（而不是形状内部）才算选中，这样还能在形状里面继续画
    func hitTest(_ p: CGPoint) -> Bool {
        let tolerance: CGFloat = 10
        switch self {
        case let .text(_, r, _, _):
            return r.insetBy(dx: -4, dy: -4).contains(p)
        case let .arrow(a, b, _, w):
            return Self.arrowPath(from: a, to: b, width: w).contains(p)
                || Self.stroked(Self.polyline([a, b]), width: w + tolerance).contains(p)
        case .mosaic:
            return outline.contains(p)
        default:
            return Self.stroked(path, width: size + tolerance).contains(p)
        }
    }

    /// 选中时显示虚线框的范围
    var bounds: CGRect {
        switch self {
        case let .text(_, r, _, _): r
        default: outline.boundingBoxOfPath
        }
    }

    private var path: CGPath {
        switch self {
        case let .rect(r, _, _): CGPath(rect: r, transform: nil)
        case let .ellipse(r, _, _): CGPath(ellipseIn: r, transform: nil)
        case let .arrow(a, b, _, _): Self.polyline([a, b])
        case let .pen(pts, _, _), let .mosaic(pts, _): Self.polyline(pts)
        case let .text(_, r, _, _): CGPath(rect: r, transform: nil)
        }
    }

    private var outline: CGPath {
        if case let .arrow(a, b, _, w) = self { return Self.arrowPath(from: a, to: b, width: w) }
        return Self.stroked(path, width: size)
    }

    private static func polyline(_ points: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: points)
        return p
    }

    private static func stroked(_ path: CGPath, width: CGFloat) -> CGPath {
        path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
    }

    /// 文字的外框，左上角固定在 topLeft
    static func textFrame(_ s: String, font: NSFont, topLeft: CGPoint) -> CGRect {
        let str = NSAttributedString(string: s.isEmpty ? " " : s, attributes: [.font: font])
        let r = str.boundingRect(with: CGSize(width: 10_000, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
        let w = max(ceil(r.width) + 4, 12)
        let h = max(ceil(r.height), lineHeight)
        return CGRect(x: topLeft.x, y: topLeft.y - h, width: w, height: h)
    }

    /// 拖动过程中更新形状
    func updated(from start: CGPoint, to p: CGPoint) -> Annotation {
        let r = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
        switch self {
        case let .rect(_, c, w): return .rect(r, c, w)
        case let .ellipse(_, c, w): return .ellipse(r, c, w)
        case let .arrow(_, _, c, w): return .arrow(start, p, c, w)
        case let .pen(points, c, w): return .pen(points + [p], c, w)
        case let .mosaic(points, w): return .mosaic(points + [p], w)
        case .text: return self
        }
    }

    /// `mosaic` 是整屏的低分辨率版本，`canvas` 是整屏的范围
    func draw(in ctx: CGContext, mosaic: CGImage?, canvas: CGRect) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch self {
        case let .rect(r, c, w):
            ctx.setStrokeColor(c.cgColor)
            ctx.setLineWidth(w)
            ctx.stroke(r)
        case let .ellipse(r, c, w):
            ctx.setStrokeColor(c.cgColor)
            ctx.setLineWidth(w)
            ctx.strokeEllipse(in: r)
        case let .arrow(a, b, c, w):
            ctx.setFillColor(c.cgColor)
            ctx.addPath(Self.arrowPath(from: a, to: b, width: w))
            ctx.fillPath()
        case let .pen(points, c, w):
            ctx.setStrokeColor(c.cgColor)
            ctx.setLineWidth(w)
            ctx.addLines(between: points)
            ctx.strokePath()
        case let .mosaic(points, w):
            guard let mosaic else { return }
            ctx.addLines(between: points)
            ctx.setLineWidth(w)
            ctx.replacePathWithStrokedPath()
            ctx.clip()
            ctx.interpolationQuality = .none
            ctx.draw(mosaic, in: canvas)
        case let .text(s, r, font, c):
            let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: c])
            // 多给点宽度，避免排版误差导致意外换行
            str.draw(in: CGRect(x: r.minX, y: r.minY, width: r.width + 2000, height: r.height))
        }
    }

    /// 尾部细、头部粗的箭头
    static func arrowPath(from a: CGPoint, to b: CGPoint, width w: CGFloat) -> CGPath {
        let length = hypot(b.x - a.x, b.y - a.y)
        let headLength = min(length, max(14, w * 4.5))
        let headHalf = headLength * 0.45
        let neck = length - headLength * 0.75

        let path = CGMutablePath()
        path.addLines(between: [
            CGPoint(x: 0, y: -w * 0.15),
            CGPoint(x: neck, y: -w * 0.6),
            CGPoint(x: length - headLength, y: -headHalf),
            CGPoint(x: length, y: 0),
            CGPoint(x: length - headLength, y: headHalf),
            CGPoint(x: neck, y: w * 0.6),
            CGPoint(x: 0, y: w * 0.15),
        ])
        path.closeSubpath()

        var transform = CGAffineTransform(translationX: a.x, y: a.y)
            .rotated(by: atan2(b.y - a.y, b.x - a.x))
        return path.copy(using: &transform) ?? path
    }
}
