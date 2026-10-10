#!/bin/bash
# 编译并打包 Snipnote
#   ./build.sh            编译打包成 build/Snipnote.app（Apple Development 签名，本机使用）
#   ./build.sh --install  同上，并安装到 /Applications、开启开机自启并重新启动
#   ./build.sh --release  Universal 版本 + Developer ID 签名 + 公证，输出可分发的 dist/Snipnote-<版本>.dmg
#
# 环境变量：
#   SIGN_IDENTITY   指定签名证书（SHA-1 或名称）
#   NOTARY_PROFILE  公证用的钥匙串配置名，默认 Snipnote
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
APP=build/Snipnote.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)

# 按名称找钥匙串里第一张匹配的签名证书，输出它的 SHA-1
find_identity() {
    security find-identity -v -p codesigning | awk -v name="$1" 'index($0, name) {print $2; exit}'
}

package() {
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp "$1" "$APP/Contents/MacOS/Snipnote"
    cp Info.plist "$APP/Contents/"
    cp Resources/AppIcon.icns "$APP/Contents/Resources/"
}

# MARK: - 分发版本

if [[ "$MODE" == "--release" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    package "$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Snipnote"

    IDENTITY="${SIGN_IDENTITY:-$(find_identity "Developer ID Application")}"
    if [[ -z "$IDENTITY" ]]; then
        echo "❌ 钥匙串里没有 Developer ID Application 证书"
        exit 1
    fi
    # 公证要求：Hardened Runtime + 安全时间戳
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
    codesign --verify --strict "$APP"
    echo "✅ 已用 Developer ID 签名 $APP ($(lipo -archs "$APP/Contents/MacOS/Snipnote"))"

    # DMG：带背景和箭头的拖拽安装界面，用 dmgbuild 生成（装在 .build 下的独立虚拟环境里）
    VENV=.build/dmgbuild-venv
    if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
        echo "⏳ 首次使用，安装 dmgbuild…"
        python3 -m venv "$VENV"
        "$VENV/bin/pip" install --quiet dmgbuild
    fi
    mkdir -p dist
    DMG="dist/Snipnote-$VERSION.dmg"
    rm -f "$DMG"
    "$VENV/bin/dmgbuild" -s scripts/dmg-settings.py \
        -D app="$APP" -D background=Resources/dmg-background.tiff -D icon=Resources/AppIcon.icns \
        "Snipnote" "$DMG" >/dev/null
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
    echo "✅ 已生成并签名 $DMG"

    PROFILE="${NOTARY_PROFILE:-Snipnote}"
    if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
        cat <<MSG

⚠️  没有找到公证凭证「$PROFILE」，DMG 已签名但未公证，别人打开时仍会被 Gatekeeper 拦住。
   先在 https://appleid.apple.com 生成一个 App 专用密码，然后运行一次（按提示输入）：

     xcrun notarytool store-credentials "$PROFILE" --apple-id <你的 Apple ID> --team-id 3TJQ367JDZ

   之后重新运行 ./build.sh --release 即可自动公证。
MSG
        exit 1
    fi

    echo "⏳ 提交公证（通常 1–5 分钟）…"
    OUT=$(xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait 2>&1 || true)
    echo "$OUT"
    if ! grep -q "status: Accepted" <<<"$OUT"; then
        ID=$(awk '/^ *id:/ {print $2; exit}' <<<"$OUT")
        echo "❌ 公证没有通过，详细原因："
        [[ -n "$ID" ]] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE"
        exit 1
    fi

    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -vv "$DMG"
    # 上传到 GitHub Release 时用固定文件名，网站上的 releases/latest/download/Snipnote.dmg 才能一直指向最新版
    cp "$DMG" dist/Snipnote.dmg
    echo "✅ $DMG 已签名并公证，可以直接发给别人"
    echo "   发布：gh release create v$VERSION dist/Snipnote.dmg --title \"Snipnote $VERSION\" --notes \"…\""
    exit 0
fi

# MARK: - 本机版本

swift build -c release
package .build/release/Snipnote

# 用固定证书签名，重新编译后"屏幕录制"权限不会失效；没有证书时退回 ad-hoc 签名
IDENTITY="${SIGN_IDENTITY:-$(find_identity "Apple Development")}"
codesign --force --sign "${IDENTITY:--}" "$APP"

echo "✅ $APP"

if [[ "$MODE" == "--install" ]]; then
    pkill -x Snipnote 2>/dev/null && sleep 0.5 || true
    rm -rf /Applications/Snipnote.app
    cp -R "$APP" /Applications/
    open /Applications/Snipnote.app --args --enable-launch-at-login
    echo "✅ 已安装到 /Applications/Snipnote.app 并启动"
fi
