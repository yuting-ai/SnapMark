import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared

    // Snipnote --snapshot <输出目录>：渲染中英文演示截图后退出
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
        Snapshot.run(outputDirectory: URL(fileURLWithPath: args[i + 1]))
        exit(0)
    }

    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
