# SnapMark

**中文** | [English](README.md)

一个轻量的 macOS 菜单栏截图工具，交互参考微信截图：框选、标注，按回车就复制到剪贴板，直接粘贴到聊天、邮件或文档里。

<p align="center"><img src="docs/images/snapmark-zh.png" width="720" alt="SnapMark 截图界面：选中一个订单窗口，用矩形框出错误、箭头和文字说明，电话号码打了马赛克，下方是工具条"></p>

## 下载

**[⬇ 下载 SnapMark（macOS）](https://github.com/yuting-ai/SnapMark/releases/latest/download/SnapMark.dmg)**

macOS 14 或更高版本 · Apple 芯片和 Intel 均可 · 已通过 Apple 公证 · 免费开源（MIT）

介绍页：[lepton.me/snapmark](https://lepton.me/snapmark) · 所有版本和更新说明：[Releases](https://github.com/yuting-ai/SnapMark/releases)

## 功能

- **自动识别窗口**：鼠标悬停时高亮窗口，单击即可选中（在桌面上单击是整个屏幕）；也可以拖动框选任意区域，拖边角调整大小。
- **六种标注**：矩形、椭圆、箭头、画笔、文字和马赛克。第二行用滑块调粗细（文字是字号），选择颜色。
- **随时修改**：点一下已有的标注就能移动、改粗细和颜色，`⌫` 删除，双击文字重新编辑，`⌘Z` 撤销。新画的标注会自动选中，可以马上调大小。
- **自动进剪贴板**：按回车或双击选区，截图立刻复制。`⌘S` 同时保存 PNG 到桌面。
- **自定义快捷键**：默认 `⌃⌥A`，可以改成任何顺手的组合，和系统快捷键冲突时会提醒。
- **多屏与 Retina**：每块屏幕都能截，按原始分辨率导出。
- **中文和英文界面**：默认跟随系统语言，也可以在设置里切换。
- **轻巧不打扰**：只在菜单栏，可以开机自启。不联网，不收集任何数据。

## 系统要求

- macOS 14 或更高版本（Apple 芯片和 Intel 均可）

## 安装

1. [下载 SnapMark.dmg](https://github.com/yuting-ai/SnapMark/releases/latest/download/SnapMark.dmg)，双击打开，把 SnapMark 拖进「应用程序」文件夹。
2. 打开 SnapMark。它没有窗口，也不在程序坞里，只会在屏幕右上角的**菜单栏**出现一个剪刀图标。
3. 第一次截图时，macOS 会请求权限：在「系统设置 → 隐私与安全性 → 屏幕与系统音频录制」中打开 SnapMark，然后**退出并重新打开** SnapMark（权限要重启后才生效）。
4. 按 `⌃⌥A` 开始截图。

> **为什么需要「屏幕录制」权限？** macOS 要求所有截图工具获得这个权限才能读取屏幕内容。SnapMark 不联网，截图只会进入剪贴板，或在你按 `⌘S` 时保存到桌面。

## 使用

| 操作 | 说明 |
|---|---|
| `⌃⌥A` | 开始截图（也可以点菜单栏的剪刀图标） |
| 悬停 + 单击 | 选中鼠标下的窗口 |
| 拖动 | 框选区域；拖边或角调整大小，拖内部移动，方向键微调（按住 `⇧` 每次 10 点） |
| 工具条 | 选择标注工具，第二行调粗细 / 字号和颜色；再点一次当前工具可以回到移动选区 |
| 点击已有标注 | 选中，可以拖动、方向键微调、改粗细 / 字号和颜色，`⌫` 删除 |
| 双击已有文字 | 重新编辑文字 |
| `↩` / 双击选区 / ✓ | 完成，复制到剪贴板 |
| `⌘S` / 保存按钮 | 复制到剪贴板，同时保存 PNG 到桌面 |
| `⌘Z` | 撤销 |
| `Esc` / 右键 | 取消（有选区但还没标注时，右键会先清掉选区） |

文字工具：单击开始输入，`↩` 或点别处结束，`⌥↩` 换行。粗细和字号会记住，下次截图沿用。

菜单栏菜单里还有：

| 菜单项 | 说明 |
|---|---|
| 设置… | 修改截图快捷键、切换界面语言 |
| 开机自动启动 | 登录时自动打开 SnapMark |

## 常见问题

**按快捷键没有反应？**
可能被其他应用占用了。点菜单栏的剪刀图标 →「设置…」，换一个组合即可。和系统快捷键冲突时，设置窗口会提示去哪里关掉系统的那个。

**授权了屏幕录制，截图还是失败？**
权限要在 SnapMark 重新启动后才生效。从菜单栏退出 SnapMark，再重新打开。

**马赛克涂多了怎么办？**
`⌘Z` 撤销，或者取消选中马赛克工具后点一下那块马赛克，按 `⌫` 删除。

## 卸载

在菜单栏菜单里退出 SnapMark，然后把它从「应用程序」拖到废纸篓。如果开过「开机自动启动」，先在菜单里取消勾选。

## 开发

需要 Xcode 命令行工具（Swift 5.9 或更高），不需要 Xcode 工程。

```bash
./build.sh            # 编译并打包成 build/SnapMark.app
./build.sh --install  # 同上，并安装到 /Applications、开启开机自启并重新启动
```

`build.sh` 默认用钥匙串里的 Apple Development 证书签名，这样重新编译后「屏幕录制」权限不会失效。可以用 `SIGN_IDENTITY` 环境变量指定其他证书。

运行前先退出已安装的 SnapMark，否则菜单栏会出现两个图标。

| 文件 | 内容 |
|---|---|
| `Sources/SnapMark/AppDelegate.swift` | 菜单栏图标和菜单、快捷键注册、开机自启 |
| `Sources/SnapMark/CaptureController.swift` | 一次截图的流程：多屏遮罩窗口、复制、保存 |
| `Sources/SnapMark/OverlayView.swift` | 框选、调整、标注交互，以及导出 |
| `Sources/SnapMark/Annotation.swift` | 标注的数据模型、绘制和命中检测 |
| `Sources/SnapMark/Toolbar.swift` | 工具条 |
| `Sources/SnapMark/ScreenCapturer.swift` | ScreenCaptureKit 截屏，读取窗口位置用于自动识别 |
| `Sources/SnapMark/HotKey.swift` | Carbon 全局快捷键 |
| `Sources/SnapMark/Shortcut.swift` | 快捷键的保存、显示名、合法性和系统冲突检测 |
| `Sources/SnapMark/SettingsWindow.swift` | 设置窗口和快捷键录制按钮 |
| `Sources/SnapMark/L10n.swift` | 所有界面文字的中英文 |
| `Sources/SnapMark/Snapshot.swift` | 渲染演示截图 |

### 截图和图标

README 里的截图用一个虚构的窗口渲染，不会出现真实的屏幕内容。修改界面后重新生成中英文截图：

```bash
build/SnapMark.app/Contents/MacOS/SnapMark --snapshot docs/images
```

应用图标 `Resources/AppIcon.icns` 和 DMG 安装背景 `Resources/dmg-background.tiff` 由脚本绘制：

```bash
swift scripts/make-assets.swift
```

### 本地化

所有界面文字都在 `Sources/SnapMark/L10n.swift` 里，每条写成 `t("中文", "English")`。

### 发布

`./build.sh --release` 一条命令完成：Universal 编译（Apple 芯片 + Intel）→ Developer ID 签名（Hardened Runtime）→ 制作带背景的 DMG → 公证并附上公证结果 → Gatekeeper 验证。产物在 `dist/SnapMark-<版本>.dmg`，同时复制一份 `dist/SnapMark.dmg`。

DMG 由 [dmgbuild](https://github.com/dmgbuild/dmgbuild) 生成，第一次运行时会自动装进 `.build/dmgbuild-venv`，布局在 `scripts/dmg-settings.py`。

第一次使用前，需要把公证凭证存进钥匙串（需要 Apple ID 的 App 专用密码）：

```bash
xcrun notarytool store-credentials SnapMark --apple-id <Apple ID> --team-id 3TJQ367JDZ
```

发布新版本：修改 `Info.plist` 里的 `CFBundleShortVersionString`，然后运行：

```bash
./build.sh --release
```

发布到 GitHub。DMG 统一以 `SnapMark.dmg` 的文件名上传，这样下载链接（`releases/latest/download/SnapMark.dmg`）始终指向最新版本：

```bash
gh release create v1.1 dist/SnapMark.dmg --title "SnapMark 1.1" --notes "…"
```

## 许可

SnapMark 以 [MIT 许可证](LICENSE) 发布。
