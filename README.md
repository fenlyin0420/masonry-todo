# Masonry Todo

卡片式待办清单，Flutter 写的 Android 应用。所有数据只存在手机本地，没有账号、没有网络请求。

## 功能

- **双列瀑布流**：矩形卡片左右两列排布，高度各不相同，互不对齐。
- **卡片内容**：顶部是标题，留空时自动取正文第一句；下面是正文预览。
- **长按 3 秒完成**：卡片上一个环形进度走完即标记完成，松手或滑动会取消。完成后卡片整体压暗，并划过一条斜线。
- **列表形态**：右上角切到列表，每行前面一个方框，点一下即完成；完成的行会沉到底部，误点可以撤销。
- **详情像评论区**：第一楼是这条 todo 本身（标题可空），分割线以下逐楼记录你的想法、心得，每条都带精确到分的发表时间。新增记录自动滚到最新一楼。
- **删除只在详情页**：右上角删除，二次确认后连同全部记录一起移除。
- 深色 / 浅色跟随系统。

## 安装

到 [Releases](../../releases) 下载 `app-release.apk`，在手机上允许「安装未知来源应用」后安装。
首次安装需要 Android 7.0 及以上。

## 本地开发

```bash
flutter pub get
flutter run              # 连接手机或启动模拟器
flutter test             # 单元测试 + widget 测试
flutter build apk --release
```

Release 构建读取 `android/key.properties`（`storeFile` / `storePassword` / `keyAlias` / `keyPassword`）
指定签名；没有这个文件时退回 debug 签名，方便本地出可安装的包。

## 数据存放

应用私有目录下的 `masonry_todo/todos.json`，写入时先写临时文件再替换，避免中断留下半截数据。
卡片形态的选择也保存在同一个文件里。

## 发布

推一个 `v*` 标签（例如 `v1.0.0`）会触发 `.github/workflows/release.yml`：
先跑 `flutter analyze` 与 `flutter test`，再构建 APK、上传构建产物，并把 APK 挂到对应的 GitHub Release。
在 Actions 页面手动触发同一个工作流则只产出 APK 产物，不创建 Release。
