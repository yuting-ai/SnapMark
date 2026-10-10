import AppKit

/// 选区下方的工具条：第一行是工具和操作，第二行是粗细和颜色（选中工具后出现）
final class Toolbar: NSView {
    static let accent = NSColor(srgbRed: 0.10, green: 0.68, blue: 0.10, alpha: 1)
    static let colors: [NSColor] = [
        NSColor(srgbRed: 0.96, green: 0.26, blue: 0.21, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.76, blue: 0.03, alpha: 1),
        NSColor(srgbRed: 0.30, green: 0.69, blue: 0.31, alpha: 1),
        NSColor(srgbRed: 0.13, green: 0.59, blue: 0.95, alpha: 1),
        .white,
        .black,
    ]

    var onTool: ((Tool?) -> Void)?
    var onColor: ((NSColor) -> Void)?
    var onSize: ((CGFloat) -> Void)?
    var onUndo: (() -> Void)?
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?
    var onDone: (() -> Void)?

    private(set) var tool: Tool?
    private var toolButtons: [Tool: ToolbarButton] = [:]
    private var colorDots: [DotView] = []
    private let optionsRow = NSStackView()
    private let colorRow = NSStackView()
    private let colorSeparator = SeparatorView()
    private let sizeSlider = NSSlider(value: 4, minValue: 1, maxValue: 20, target: nil, action: nil)
    private let sizeLabel = NSTextField(labelWithString: "4")
    private let smallMark = NSTextField(labelWithString: "")
    private let bigMark = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.3
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        let mainRow = NSStackView()
        mainRow.spacing = 0
        for t in Tool.allCases {
            let button = ToolbarButton(symbol: t.symbol, tip: t.title) { [weak self] in self?.toggle(t) }
            toolButtons[t] = button
            mainRow.addArrangedSubview(button)
        }
        mainRow.addArrangedSubview(SeparatorView())
        mainRow.addArrangedSubview(ToolbarButton(symbol: "arrow.uturn.backward", tip: L10n.undoTip) { [weak self] in self?.onUndo?() })
        mainRow.addArrangedSubview(ToolbarButton(symbol: "square.and.arrow.down", tip: L10n.saveTip) { [weak self] in self?.onSave?() })
        mainRow.addArrangedSubview(SeparatorView())
        let cancel = ToolbarButton(symbol: "xmark", tip: L10n.cancelTip) { [weak self] in self?.onCancel?() }
        cancel.contentTintColor = .systemRed
        let done = ToolbarButton(symbol: "checkmark", tip: L10n.doneTip) { [weak self] in self?.onDone?() }
        done.contentTintColor = Self.accent
        mainRow.addArrangedSubview(cancel)
        mainRow.addArrangedSubview(done)

        // 粗细 / 字号滑块
        for label in [smallMark, bigMark, sizeLabel] { label.textColor = NSColor(white: 0.35, alpha: 1) }
        sizeSlider.controlSize = .small
        sizeSlider.isContinuous = true
        sizeSlider.refusesFirstResponder = true // 拖滑块时文字框保持输入状态
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeSliderChanged)
        sizeSlider.translatesAutoresizingMaskIntoConstraints = false
        sizeSlider.widthAnchor.constraint(equalToConstant: 120).isActive = true
        sizeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        sizeLabel.alignment = .right
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        sizeLabel.widthAnchor.constraint(equalToConstant: 22).isActive = true
        let sizeRow = NSStackView(views: [smallMark, sizeSlider, bigMark, sizeLabel])
        sizeRow.spacing = 6
        sizeRow.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 2)
        sizeRow.heightAnchor.constraint(equalToConstant: 26).isActive = true
        optionsRow.spacing = 0
        optionsRow.addArrangedSubview(sizeRow)

        optionsRow.addArrangedSubview(colorSeparator)
        colorRow.spacing = 0
        for (i, c) in Self.colors.enumerated() {
            let dot = DotView(color: c) { [weak self] in self?.selectColor(i) }
            colorDots.append(dot)
            colorRow.addArrangedSubview(dot)
        }
        optionsRow.addArrangedSubview(colorRow)
        optionsRow.isHidden = true
        colorDots[0].isSelected = true

        let column = NSStackView(views: [mainRow, optionsRow])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2
        column.edgeInsets = NSEdgeInsets(top: 3, left: 4, bottom: 3, right: 4)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 高亮当前工具
    func setTool(_ t: Tool?) {
        tool = t
        for (k, b) in toolButtons {
            b.contentTintColor = k == t ? Self.accent : ToolbarButton.normalTint
        }
    }

    /// 第二行显示哪类选项：kind 为 nil 时隐藏
    func configureOptions(kind: Tool?, size: CGFloat, color: NSColor?) {
        optionsRow.isHidden = kind == nil
        guard let kind else { return }

        let range = kind.sizeRange
        sizeSlider.minValue = Double(range.lowerBound)
        sizeSlider.maxValue = Double(range.upperBound)
        sizeSlider.doubleValue = Double(size)
        sizeLabel.stringValue = "\(Int(size.rounded()))"
        if kind == .text {
            smallMark.stringValue = "A"
            bigMark.stringValue = "A"
            smallMark.font = .systemFont(ofSize: 10, weight: .medium)
            bigMark.font = .systemFont(ofSize: 16, weight: .medium)
            sizeSlider.toolTip = L10n.fontSizeTip
        } else {
            smallMark.stringValue = "●"
            bigMark.stringValue = "●"
            smallMark.font = .systemFont(ofSize: 6)
            bigMark.font = .systemFont(ofSize: 14)
            sizeSlider.toolTip = kind == .mosaic ? L10n.brushSizeTip : L10n.lineWidthTip
        }

        colorRow.isHidden = kind == .mosaic
        colorSeparator.isHidden = kind == .mosaic
        for (j, d) in colorDots.enumerated() {
            d.isSelected = color == Self.colors[j]
        }
    }

    private func toggle(_ t: Tool) {
        let next: Tool? = tool == t ? nil : t
        setTool(next)
        onTool?(next)
    }

    @objc private func sizeSliderChanged() {
        let size = CGFloat(sizeSlider.doubleValue.rounded())
        sizeLabel.stringValue = "\(Int(size))"
        onSize?(size)
    }

    private func selectColor(_ i: Int) {
        for (j, d) in colorDots.enumerated() { d.isSelected = i == j }
        onColor?(Self.colors[i])
    }

    // 背景用 draw 画而不是 layer 属性，这样 --snapshot 渲染时也有背景
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.98, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    // 吞掉工具条空白处的点击，免得传给下面的遮罩
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
}

final class ToolbarButton: NSButton {
    static let normalTint = NSColor(white: 0.25, alpha: 1)
    private let handler: () -> Void

    init(symbol: String, tip: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: NSRect(x: 0, y: 0, width: 32, height: 28))
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?.withSymbolConfiguration(config)
        imagePosition = .imageOnly
        isBordered = false
        toolTip = tip
        refusesFirstResponder = true
        contentTintColor = Self.normalTint
        target = self
        action = #selector(fire)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 32).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}

final class DotView: NSView {
    var isSelected = false { didSet { needsDisplay = true } }
    private let color: NSColor
    private let onClick: () -> Void

    init(color: NSColor, onClick: @escaping () -> Void) {
        self.color = color
        self.onClick = onClick
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 26).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3))
            ring.lineWidth = 1.5
            NSColor(white: 0.35, alpha: 1).setStroke()
            ring.stroke()
        }
        let dot = NSBezierPath(ovalIn: bounds.insetBy(dx: 7, dy: 7))
        color.setFill()
        dot.fill()
        dot.lineWidth = 0.5
        NSColor(white: 0, alpha: 0.25).setStroke()
        dot.stroke()
    }

    override func mouseDown(with event: NSEvent) { onClick() }
}

final class SeparatorView: NSView {
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 9, height: 22))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 9).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.82, alpha: 1).setFill()
        NSRect(x: bounds.midX - 0.5, y: 3, width: 1, height: bounds.height - 6).fill()
    }
}
