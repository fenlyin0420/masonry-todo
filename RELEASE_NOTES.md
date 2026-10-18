# Masonry Todo 1.1.0

## 新功能

- **图片评论**：详情页的输入框旁多了「加图」按钮，从相册选照片或 GIF 发到这条记录里——GIF 保留动画，其他照片自动压缩；楼层里点图片可以全屏查看。
- **应用内自动更新**：启动时自动检查 GitHub Releases 上的新版本，首页右上角也可手动检查。发现新版本后在应用内下载，完成后直接唤起系统安装器（首次需要允许「安装未知应用」）。
- **安装包按架构拆分**：Release 里不再是大杂烩整包，按设备架构出 `masonry-todo-arm64-v8a.apk`（绝大多数手机）和 `masonry-todo-armeabi-v7a.apk`（老机型），各约一半体积。

## 修复

- 首页已完成状态的卡片点不开详情的 bug。

## Assets

- `masonry-todo-arm64-v8a.apk` — Android arm64
- `masonry-todo-armeabi-v7a.apk` — Android arm32
