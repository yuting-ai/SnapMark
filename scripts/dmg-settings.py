# dmgbuild 配置：带背景和箭头的拖拽安装窗口
# 由 build.sh --release 调用，-D app=... -D background=... -D icon=...
import os.path

application = defines["app"]
appname = os.path.basename(application)

format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]  # 挂载后卷宗的图标

# 窗口尺寸包含标题栏（约 28pt），内容区约 640×400；背景图 640×440 多出的部分不会露白
# 图标中心对齐背景上箭头的两端
background = defines["background"]
window_rect = ((200, 160), (640, 428))
icon_size = 128
text_size = 13
icon_locations = {
    appname: (160, 190),
    "Applications": (480, 190),
}

default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
arrange_by = None
