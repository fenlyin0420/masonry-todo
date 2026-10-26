# 拾记 开发文档

面向维护者的技术说明：项目结构、数据模型、持久化格式、关键交互与发版流程。
用户视角的功能介绍见 [README](../README.md)。

## 技术栈

- Flutter / Dart 3，主要目标平台是 Android（release 只出 APK）。
- Linux 桌面构建仅用于本地预览 UI，不进入发布产物。
- 依赖：`path_provider`（本地目录）、`image_picker`（选图）、`image`（压缩图片）、
  `package_info_plus`（版本号）、`dio`（检查更新与下载 APK）、
  `file_picker`（导出 / 导入备份走系统文件对话框）、
  `flutter_markdown_plus`（详情页的块级 Markdown 渲染）、`markdown`（卡片预览的行内解析）。

## 目录结构

```text
lib/
  main.dart              入口：加载本地数据、装配更新控制器
  app_theme.dart         主题、卡片强调色与完成态底色
  feedback.dart          完成待办时的触感序列
  nav.dart               详情 / 新建 / 编辑的路由封装
  backup_flow.dart       导出 / 导入备份的文件对话框与提示
  models/
    entry.dart           Entry、Note、EntryKind 与 JSON 序列化
    entry_text.dart      标题推断、正文预览、时间格式化
  markdown/
    inline_markdown.dart Markdown 解析成行内片段、去标记的纯文本、片段截取
  store/
    entry_store.dart     全应用唯一数据源（ChangeNotifier）
    entry_storage.dart   快照结构、JSON 文件存储、内存存储
    backup.dart          备份文本的编码与解析（图片走 base64）
    note_image_store.dart 楼层图片的落盘、压缩与清理
  pages/
    home_page.dart       双标签首页、瀑布流 / 列表、空状态
    detail_page.dart     楼层式详情、记录输入、楼层编辑与删除、图片查看
    entry_editor_page.dart 新建与编辑共用页
  widgets/
    entry_card.dart      瀑布流卡片
    entry_row.dart       列表行
    markdown_view.dart   行内 Markdown 文本（卡片 / 列表）与块级 Markdown（详情）
    hold_to_finish.dart  长按 3 秒的指针计时与分段回调
    card_fracture.dart   长按期间盖在卡片上的裂纹
    finish_aware.dart    完成态的降饱和与压暗动画
    masonry_grid.dart    按条目顺序左右交替的双列瀑布流
    check_square.dart    列表行前的完成方框
    store_scope.dart     InheritedNotifier，向子树提供 EntryStore
    update_watch.dart    更新提示、下载进度与安装引导
    update_scope.dart    向子树提供 UpdateController
  update/
    app_version.dart     版本解析与比较
    github_release.dart  Release JSON 解析、按 ABI 选包
    update_controller.dart 检查 / 下载 / 安装状态机
test/                    单元测试与 widget 测试
docs/                    本文档与截图
```

## 数据模型

```dart
enum EntryKind { todo, idea }

class Entry {
  final String id;
  final EntryKind kind;   // 创建后不再改变
  final String title;     // 可为空，展示时回退到正文第一句
  final String body;
  final DateTime createdAt;
  bool done;              // 仅待办使用
  DateTime? doneAt;       // 仅 done == true 时有值
  int rank;               // 手动排出来的优先级，小的在前
  final List<Note> notes; // 楼层记录，第一条不是 Note
}

class Note {
  final String id;
  final String text;
  final DateTime createdAt;
  final String? image;    // 图片文件名，文件在 images/ 下
}
```

约束：

- 灵感永远没有完成状态。`Entry.isDone` 只在 `kind == todo && done` 时为真，
  `EntryStore.setDone` 对灵感是空操作，反序列化时也会忽略灵感上的 `done` 字段。
- 编辑只改 `title` / `body`。`EntryStore.update` 会保留 id、类型、创建时间、
  完成状态与楼层列表；内容没有变化时不写盘。
- 排序规则：未完成在前，同一组内按 `rank` 从小到大，`rank` 相同（旧数据、
  从没排过）时退回按创建时间新到旧；已完成的沉底，`rank` 相同再按完成时间新到旧。
  灵感没有完成状态，等于按 `rank`、再按创建时间。
- 优先级：新建条目的 `rank` 取现有最小值减一，所以新条目排在最前面；列表里按住
  拖动会按拖完的顺序重排 `rank`（见 [拖动排序](#拖动排序)）。

## 持久化

- 位置：应用文档目录下 `masonry_todo/todos.json`。目录与文件名沿用 1.x 的命名，
  升级时不搬迁用户数据。
- 写入：先写 `todos.json.tmp` 再改名；改名之前把旧主文件轮转为 `todos.json.bak`，
  于是磁盘上始终同时留着新的一份和上一个版本。
- 读取顺序：主文件 → 不比它旧的 `.tmp`（上次改名没走完）→ `.bak`（主文件读不出来）。
  走兜底时 `EntryStore.takeRecoveryNotice()` 给出原因，首页提示用户，不静默。
- 坏文件：解析失败的主文件改名为 `todos.json.corrupt` 留档；半截的 `.tmp` 直接丢弃。
- 保存失败：`EntryStore.saveError` 记住原因并通知，首页提示「保存失败」并给重试，
  写成功一次后自动清空。
- 进程被杀：切后台、隐藏、退出前触发 `flush()`，排队中的写入不会留给杀手。
- 快照格式（v4）：

```json
{
  "version": 4,
  "viewModes": { "todo": "grid", "idea": "list" },
  "kind": "todo",
  "showCompleted": false,
  "entries": [
    {
      "id": "...",
      "kind": "todo",
      "title": "...",
      "body": "...",
      "createdAt": "2026-10-18T09:12:00.000",
      "done": false,
      "doneAt": null,
      "rank": -1,
      "notes": [
        { "id": "...", "text": "...", "createdAt": "..." }
      ]
    }
  ]
}
```

- 兼容：读取时 `entries` 与旧版 `todos` 字段都认；缺少 `kind` 的条目按待办处理；
  `kind` 缺省为 `todo`。待办页与灵感页各记一套 `viewModes`，互不影响；v2 及更早
  只有一个共用的 `viewMode`，读入时两边都沿用它，缺省为 `grid`。
  v4 起多了 `rank`（缺省 0）与 `showCompleted`（缺省 false）：旧数据读进来
  等于「没排过优先级、已完成收起」，排序退回按时间，与升级前看到的一致。
- 所有写操作由 `EntryStore` 串行排队（`_pendingSave`），测试可用 `flush()` 等待落盘。

### 图片

- 楼层图片存放在 `masonry_todo/images/`，`Note.image` 只保存文件名。
- GIF 原样复制以保留动画，超过 8 MB 拒绝；其他图片超过 1600 px 时按 EXIF 方向
  烘正后压成 JPEG（质量 82）。
- 删除条目时，详情页先出页面再清理该条目引用到的图片文件。

### 备份

- 导出：`encodeBackup` 把 `AppSnapshot` 连同它引用到的图片（base64）编成单个 `.json`，
  经系统保存对话框交给用户，可存到下载或网盘目录。格式：

```json
{
  "format": "masonry_todo.backup",
  "version": 1,
  "exportedAt": "2026-10-18T09:30:00.000",
  "appVersion": "1.4.0+7",
  "snapshot": {
    "version": 3,
    "viewModes": { "todo": "grid", "idea": "grid" },
    "kind": "todo",
    "entries": []
  },
  "images": { "1734567890123456-123456789.jpg": "<base64>" }
}
```

  条目里的 `image` 仍只是文件名，**图片字节在顶层 `images` 里**（键 = 文件名），
  所以整包自带图，不需要另外拷 `images/` 目录。图片文件不在磁盘上就跳过，不因为
  一张丢了的图让整次导出失败；但会把名字记进 `BackupExport.missingImages`，
  导出完成时提示「有 N 张图片在原机上找不到，没进备份」，不静默丢。
- 导入：`decodeBackup` 认两种输入——本应用导出的备份（`format: masonry_todo.backup`）
  与直接拷来的 `todos.json`；其它文件抛 `FormatException`，文案可直接展示给用户。
  导入后逐个核对条目引用的图是否落盘，缺几张就在提示里说清（备份本身就没带）。
- 合并：`EntryStore.mergeImported` 按 id 合并，没见过的补上；已有的以本地为准
  （用户后来的改动更可信），只补齐本地缺的楼层与完成状态。图片先落盘再合并条目，
  同名文件不覆盖，名字里带路径分隔符的直接拒掉。

## 关键交互

### 长按完成

`HoldToFinish` 直接监听指针事件，而不是 tap 手势竞技场：按住期间 widget 重建或
指针路径失效时，`onTapUp` 不保证到达，计时器会无人取消地跑完。

- 按住满 3 秒触发 `onFinish`。
- 松手、指针取消、位移超过 12 px 都会中止计时。
- 未触发完成就松手视为一次轻点（进入详情）。
- 触感由调用方负责，`HoldToFinish` 本身不播放，只用 `onTick` 报告进度跨过了
  `1/tickDivisions` 的哪一段。
- 完成瞬间条目可能被过滤器从列表里拿走、widget 先被 dispose，而这次按住的指针
  事件还会继续派发过来：所有指针回调都先看 `mounted`，否则 `_abort` 会撞上已
  dispose 的 `AnimationController`。

### 碎裂动画

长按期间不再画圆形进度条，改为卡片一路裂开、一路发抖（`card_fracture.dart`）。

- 裂纹图案由 `entry.id.hashCode` 决定，同一条目每次长按裂法一致；坐标归一化到
  `0..1`，按实际尺寸缩放，卡片宽高变了不用重新生成。
- 图案 = 一个主撞击点炸开 5–7 条主裂纹（各带一条分叉）+ 一个次撞击点 + 把相邻
  主裂纹外段连起来的环向裂纹。每条裂纹有自己的露出门槛，不是一起冒出来。
- 进度推进时裂纹按折线长度一点点长出来（二次缓入缓出），宽度也跟着自己的露出
  程度加宽；裂缝是「压暗的底色 + 中间一道暗线 + 一侧高光」三层叠出来的，
  不是简单画一条线。
- 抖动幅度按进度平方增长，前一半几乎看不出来。整个碎裂只用一次 `CustomPaint`
  叠在卡片上，卡片内容不复制——没有把卡片切成几块重绘的开销。
- 震动走 `feedback.dart` 的 `playHoldTick`：每跨过四分之一段一下轻震，最后一段
  换成 medium，完成瞬间再走 `finishFeedback` 的重-中-轻三段。

### 拖动排序

列表形态里按住整行就能上下拖，拖完的顺序就是优先级，卡片形态按同一顺序摆放。

- 手机用 `ReorderableDelayedDragStartListener`（长按后拖），桌面用
  `ReorderableDragStartListener`（按住即拖），没有拖动把手。
- 只接 `onReorderItem`（`onReorder` 自 Flutter 3.41 起废弃），它的 `newIndex`
  已经扣掉移出位。
- `EntryStore.reorderVisible` 按拖完的顺序重排 `rank`，被过滤器藏起来的条目
  保持原相对顺序排在后面；落位时播放一次轻震。
- 未完成与已完成的分组不受拖动影响：把已完成项拖到未完成项上面，它会落回已完成
  组里对应的位置。

### 过滤器

待办页右上角的漏斗按钮切换「显示已完成」，默认收起，状态随快照持久化。

- 只影响待办页的列表；灵感没有完成状态，过滤器对它是空操作。
- `EntryStore.visibleEntries` 负责过滤，`entries` 仍是完整顺序，详情页、计数和
  备份都不受过滤器影响。
- 全部做完时列表会空出来，空状态改成「未完成的都做完了」并给一个「显示已完成」
  按钮，避免看起来像数据没了。

### 完成反馈

`feedback.dart` 的 `finishFeedback()` 依次播放 heavy → medium → light 三段
`HapticFeedback`，用系统触感实现，不需要 VIBRATE 权限。完成卡片与列表方框
两条路径都会调用；触感失败只记录日志，不影响状态变更。长按过程中的分段震动
（`playHoldTick`）与拖动落位的轻震（`playReorderFeedback`）走同一套。

### 返回即保存

新建与编辑共用 `EntryEditorPage`，通过 `PopScope(canPop: false)` 接管返回：

- 新建：有内容就落库，并提示「已保存到待办 / 灵感」；全空则什么也不留。
- 编辑：返回时自动保存改动；内容没变不写盘。
- 点右上角按钮与系统返回走同一套保存逻辑，避免两条路径行为不一致。

### 完成态视觉

- 卡片底色从强调色淡彩切换为中性灰（`doneCardColorFor`），标题划线，
  右上角保留强调色对勾徽标，底部显示完成时间。
- `FinishAware` 做亮度保持的降饱和 + 轻微压暗；动画只由 `done` 变化驱动，
  初始就是完成态的卡片不会重播。完成标记只靠标题划线与右上角对勾徽标，
  不再在卡面上画斜线。

### Markdown

正文与楼层记录按 Markdown 渲染，标题仍是纯文本。

- 详情页：`MarkdownView`（`flutter_markdown_plus`）出完整的块级结构——标题、
  有序 / 无序列表、引用、代码块、分割线、表格。样式表由 `markdownStyleSheet`
  按主题拼出，正文行高与原来手写的 `Text` 一致。
- 卡片 / 列表：行太窄塞不下结构，`inline_markdown.dart` 先把块级结构压平成一层
  文本，只保留粗体、斜体、行内代码、删除线、链接这些行内样式，
  再由 `MarkdownText` 渲染成限行数的富文本。
- 标题、`bodyPreview`、卡片高度估算用的都是去掉标记后的纯文本
  （`markdownPlainText`），所以卡片标题不会出现 `**`、`#` 之类的符号。
- 标题取自正文第一句时，预览按纯文本下标跳过这一句再渲染
  （`previewSlice` + `sliceRuns`），样式不会串位。
- 楼层折叠：先用纯文本量出每行高度，决定折叠几行、折多高；再让 Markdown 按
  无限高度排完，用 `ClipRect` 裁到该高度（直接限制高度会把列表、代码块挤成
  `RenderFlex` 溢出）。纯文本行高只是估算，块间距会把渲染结果撑高，所以底部叠
  一层淡出，不假装恰好裁在行边界上。
- 遵循 CommonMark 的定界规则：`**注意：**这里` 不会加粗（闭定界符前后都是文字，
  既不右邻接又左邻接），写成 `**注意：** 这里` 才行。

## 界面结构

- 首页顶部分段控件切换「待办 / 灵感」：点标签与左右滑动都能切页（`PageView`），
  两者共用一个页码；当前页写回 store，标题、计数与悬浮按钮跟着变，启动时按 store
  记住的标签页直接打开。标签与展示形态（卡片 / 列表）都持久化。
- 瀑布流 `MasonryTwoColumn` 按条目顺序左一格、右一格地交替摆放，阅读顺序是
  行优先（先左后右，再下一行），所以卡片与列表看到的是同一个优先级顺序；
  两列各自往下堆，卡片高度不同，行不必对齐。
- 待办页右上角的漏斗按钮切换是否显示已完成，默认收起。
- 灵感在卡片 / 列表 / 详情里都用灯泡与「灵感」状态胶囊标识。

## 自动更新（仅 Android）

- 启动 1 秒后检查 `releases/latest`，首页右上角可手动检查；手动检查不受
  「同一版本只提示一次」的去重限制。同一会话内自动检查 3 分钟只做一次，省接口额度。
- 检查先问 `api.github.com`；未认证接口每小时只有 60 次，被限流（403/429）、连不上
  或返回看不懂时，改用 `github.com/<repo>/releases/latest` 的 302 定位 tag，再按
  `masonry-todo-<abi>.apk` 命名约定拼下载地址——发布页不计入接口额度。
- 版本比较见 `update/app_version.dart`：先比 major.minor.patch，三段相同且双方
  都有第四段时才比构建号。
- 按设备 ABI 选择 `masonry-todo-<abi>.apk`；已知 ABI 但多个 APK 里找不到对应包时
  判定失败，不静默下错包。
- 下载：`update/resumable_download.dart` 写 `*.part`，用 `Range: bytes=N-` 续传；
  服务器回 200（不认 Range）就从头下，不会把两段拼在一起。GitHub 的附件地址会
  302 到带签名的 CDN，但每次重试都重新请求原地址，所以续传不受签名过期影响。
- 卡死保护：连接被掐断时 dio 的响应流既不报错也不结束，所以每 30 秒没新字节就由
  看门狗判死并重试；4xx 不重试，5xx / 超时 / 断连最多重试 3 次，每轮都从 `.part` 续上。
- 失败文案按原因分开（限流带 `x-ratelimit-reset` 算出的恢复时间、超时、断连、
  存储满）；下载失败的提示条上有「重试」，直接续传而不是重新检查。
- 下载写到应用私有 `updates/` 目录，经 FileProvider 交给系统安装器；缺少
  「安装未知应用」权限时引导到系统设置。`installApk` 的原生异常会回传 Dart，
  提示「打不开安装器：…」而不是没反应。
- MethodChannel 名为 `masonry_todo.updates`（历史命名，保持与原生侧一致）。

## 本地开发

需要 Flutter SDK 与 Android SDK（构建 Android 时再配 JDK 17+）。

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d <device>
```

Linux 桌面预览（不影响发布产物）：

```bash
flutter build linux --debug
./build/linux/x64/debug/bundle/masonry_todo
```

注意：项目现有代码使用较短的行宽格式，CI 只检查 `flutter analyze` 与测试，
不校验 `dart format`；不要对整文件跑格式化，否则会产生大量无关 diff。

## 测试

```bash
flutter test
```

覆盖范围：

- `entry_store_test`：创建 / 完成 / 记录 / 删除、排序、过滤器默认值与落盘、
  拖动排序改写优先级、待办与灵感隔离、编辑保留楼层、楼层改文字 / 换图 / 删图与整层删除、
  标签与形态持久化、旧版 `todos` 数据与缺少 `rank` 的条目兼容。
- `entry_text_test`：标题回退、正文预览、时间格式化。
- `markdown_inline_test`：去掉标记后的纯文本、行内语义标记、嵌套样式、片段截取、
  卡片标题与预览的取句位置。
- `widget_test`：双标签切换、左右滑动切页、新建与返回保存、编辑、长按完成、灵感不可完成、
  过滤器展开收起、列表拖动排序与卡片顺序同步、列表撤销、删除确认、楼层长按编辑与删除。
- `note_image_test`：图片字段序列化、GIF / 压缩 / 删除文件。
- `update_*`：版本比较、Release 解析与选包、下载状态机、更新提示弹窗。

## 发版

1. 更新 `pubspec.yaml` 的 `version`（例如 `1.2.0+4`）与 `RELEASE_NOTES.md`。
2. 打标签并推送：`git tag -a v1.2.0 -m "..."`、`git push origin v1.2.0`。
3. CI 先跑 `flutter analyze` 与 `flutter test`，再按 arm64 / armv7 构建 APK，
   上传构建产物并创建 GitHub Release；`RELEASE_NOTES.md` 作为发布说明。
4. 签名材料由 CI secrets 注入，仓库内不保存 keystore 与口令。

兼容性约定：

- `applicationId`、APK 文件名、`masonry_todo.updates` 通道名与本地数据目录
  都保持不变，老版本才能覆盖升级并继续读到原有数据。
- Dart 包名 `masonry_todo` 同样保持不动；应用显示名变更只影响界面文案与
  Android `android:label`。
