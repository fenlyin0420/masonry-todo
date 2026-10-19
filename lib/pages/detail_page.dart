import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/entry.dart';
import '../models/entry_text.dart';
import 'entry_editor_page.dart';
import '../store/entry_store.dart';
import '../store/note_image_store.dart';
import '../widgets/store_scope.dart';

/// 详情：第一楼是这条内容本身（标题可空），分割线以下是记录想法的楼层。
class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.entryId});

  final String entryId;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final NoteImageStore _images = NoteImageStore();
  final ImagePicker _picker = ImagePicker();

  /// 待发送的图片（选好后先预览，发送时才落库）。
  File? _pendingImage;

  @override
  void initState() {
    super.initState();
    // 发送键的可用性跟随输入内容，需要逐字重建
    _input.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
      );
      if (picked == null || !mounted) return;
      setState(() => _pendingImage = File(picked.path));
    } catch (error) {
      debugPrint('选择图片失败：$error');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('选择图片失败，可能没有相册权限'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  void _dropPendingImage() {
    setState(() => _pendingImage = null);
  }

  Future<void> _send() async {
    final String text = _input.text.trim();
    final File? image = _pendingImage;
    if (text.isEmpty && image == null) return;
    final EntryStore store = StoreScope.of(context);
    String? imageName;
    if (image != null) {
      try {
        imageName = await _images.store(image);
      } catch (error) {
        debugPrint('图片保存失败：$error');
        // 纯图片记录存不了图就不能发，保留预览让用户换一张。
        if (text.isEmpty) {
          if (!mounted) return;
          _snack('图片太大或无法保存，换一张再发');
          return;
        }
        if (!mounted) return;
        _snack('图片保存失败，这条记录只发了文字');
      }
    }
    final Note? note = store.addNote(widget.entryId, text, image: imageName);
    if (note == null && imageName != null) {
      // 条目已不存在：清掉刚落盘的图片，别留孤儿文件。
      unawaited(_images.deleteFile(imageName));
    }
    if (mounted) setState(() => _pendingImage = null);
    _input.clear();
    _inputFocus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _confirmDelete(Entry entry) async {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String kindName = entry.isTodo ? '待办' : '灵感';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('删除这条$kindName？'),
        content: Text('「${displayTitle(entry)}」以及它的全部记录都会被删掉，无法恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final List<String> imageNames = entry.notes
        .map((note) => note.image)
        .whereType<String>()
        .toList();
    StoreScope.of(context).delete(entry.id);
    Navigator.of(context).pop();
    // 先出页面再清图片，避免等待期间闪一帧空态。
    unawaited(_cleanupImages(imageNames));
  }

  Future<void> _cleanupImages(List<String> names) async {
    for (final name in names) {
      try {
        await _images.deleteFile(name);
      } catch (error) {
        debugPrint('清理图片失败：$error');
      }
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  @override
  Widget build(BuildContext context) {
    final EntryStore store = StoreScope.of(context);
    final Entry? entry = store.byId(widget.entryId);
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('详情')),
        body: const Center(child: Text('这条内容已经不在了')),
      );
    }
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String kindName = entry.isTodo ? '待办' : '灵感';

    return Scaffold(
      appBar: AppBar(
        title: Text('$kindName详情'),
        actions: <Widget>[
          IconButton(
            tooltip: '编辑',
            onPressed: () => _openEditor(entry),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: () => _confirmDelete(entry),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              children: <Widget>[
                _OriginFloor(entry: entry),
                _ThreadDivider(count: entry.notes.length),
                if (entry.notes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        entry.isTodo
                            ? '还没有记录，写下你对这个任务的记录'
                            : '还没有记录，写下这个念头延伸出的想法',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                for (int i = 0; i < entry.notes.length; i++)
                  _NoteFloor(
                    floor: i + 2,
                    note: entry.notes[i],
                    images: _images,
                  ),
              ],
            ),
          ),
          _Composer(
            controller: _input,
            focusNode: _inputFocus,
            onSend: _send,
            pendingImage: _pendingImage,
            canSend: _input.text.trim().isNotEmpty || _pendingImage != null,
            hintText: entry.isTodo ? '写下你的想法、心得…' : '补充这个念头的延伸…',
            onPickImage: _pickImage,
            onDropPendingImage: _dropPendingImage,
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor(Entry entry) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            EntryEditorPage(entryId: entry.id),
      ),
    );
  }
}

/// 第一楼：这条条目本身。
class _OriginFloor extends StatelessWidget {
  const _OriginFloor({required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String title = entry.title.trim();
    final String body = entry.body.trim();
    final TextStyle? timeStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return _FloorShell(
      floor: 1,
      children: <Widget>[
        if (title.isNotEmpty)
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        if (body.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: title.isEmpty ? 0 : 8),
            child: Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ),
        if (title.isEmpty && body.isEmpty)
          Text(
            '（没有填写内容）',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _StatusPill(entry: entry),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    entry.isDone
                        ? '创建于 ${formatMinute(entry.createdAt)}'
                        : formatMinute(entry.createdAt),
                    textAlign: TextAlign.right,
                    style: timeStyle,
                  ),
                  if (entry.isDone)
                    Text(
                      '完成于 ${formatMinute(entry.doneAt ?? entry.createdAt)}',
                      textAlign: TextAlign.right,
                      style: timeStyle,
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 评论楼层正文的折叠高度：超过这个高度的楼层点「查看详情」展开。
/// 折叠按整行算，不会把中间一行拦腰截断。
const double _noteCollapsedHeight = 120;

/// 折叠开关：过长的评论靠它展开 / 收起。
class _ExpandToggle extends StatelessWidget {
  const _ExpandToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: theme.textTheme.labelMedium,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(expanded ? '收起' : '查看详情'),
            Icon(
              expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

/// 评论楼层的正文：超过 [_noteCollapsedHeight] 就按整行截断，点开关展开全文。
class _CollapsibleText extends StatefulWidget {
  const _CollapsibleText({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_CollapsibleText> createState() => _CollapsibleTextState();
}

class _CollapsibleTextState extends State<_CollapsibleText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 先按渲染宽度排版一遍拿到每行高度，判断要不要折叠，省得靠首帧回调测量闪一下。
        if (!constraints.maxWidth.isFinite) {
          return Text(widget.text, style: widget.style);
        }
        final List<LineMetrics> lines = _textLines(
          widget.text,
          widget.style,
          constraints.maxWidth,
          MediaQuery.textScalerOf(context),
        );
        final int visibleLines = _collapsedLineCount(lines);
        if (visibleLines >= lines.length) {
          return Text(widget.text, style: widget.style);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_expanded)
              Text(widget.text, style: widget.style)
            else
              // 按整行裁剪：用固定高度硬裁会把最后一行切成上下两半。
              Text(
                widget.text,
                style: widget.style,
                maxLines: visibleLines,
                overflow: TextOverflow.clip,
              ),
            const SizedBox(height: 2),
            _ExpandToggle(
              expanded: _expanded,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
          ],
        );
      },
    );
  }
}

/// 按给定宽度排版一遍，取每一行的高度（与 Text 的排版一致）。
List<LineMetrics> _textLines(
  String text,
  TextStyle? style,
  double width,
  TextScaler textScaler,
) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: textScaler,
  )..layout(maxWidth: width);
  return painter.computeLineMetrics();
}

/// 折叠时显示几整行：不超出 [_noteCollapsedHeight] 的最大整行数。
int _collapsedLineCount(List<LineMetrics> lines) {
  double used = 0;
  int count = 0;
  for (final LineMetrics line in lines) {
    if (used + line.height > _noteCollapsedHeight + 0.5) break;
    used += line.height;
    count++;
  }
  return count < 1 ? 1 : count;
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool done = entry.isDone;
    final String label = !entry.isTodo
        ? '灵感'
        : (done ? '已完成' : '进行中');
    final Color color = !entry.isTodo
        ? scheme.tertiary
        : (done ? scheme.onSurfaceVariant : scheme.primary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 分割线：上面是条目本体，下面是记录。
class _ThreadDivider extends StatelessWidget {
  const _ThreadDivider({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: <Widget>[
          Expanded(child: Divider(color: scheme.outlineVariant, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              count == 0 ? '记录' : '记录 · $count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Divider(color: scheme.outlineVariant, height: 1)),
        ],
      ),
    );
  }
}

class _NoteFloor extends StatelessWidget {
  const _NoteFloor({
    required this.floor,
    required this.note,
    required this.images,
  });

  final int floor;
  final Note note;
  final NoteImageStore images;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return _FloorShell(
      floor: floor,
      children: <Widget>[
        if (note.text.isNotEmpty)
          _CollapsibleText(
            text: note.text,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
          ),
        if (note.image != null)
          Padding(
            padding: EdgeInsets.only(top: note.text.isEmpty ? 0 : 8),
            child: _NoteImage(name: note.image!, images: images),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            formatMinute(note.createdAt),
            style: theme.textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// 缩略图上限：评论区的图片按比例缩到这个框里，别再占满一整行。
const double _thumbMaxWidth = 140;
const double _thumbMaxHeight = 180;

/// 楼层里的图片：缩成小图靠左显示，点按放大。动图（GIF）由 Image.file 原生播放。
class _NoteImage extends StatefulWidget {
  const _NoteImage({required this.name, required this.images});

  final String name;
  final NoteImageStore images;

  @override
  State<_NoteImage> createState() => _NoteImageState();
}

class _NoteImageState extends State<_NoteImage> {
  // fileFor 走 platform channel，挂在 build 里每次重建都会重查、
  // 让 FutureBuilder 回到 waiting 导致图片闪烁；这里缓存一次。
  late Future<File> _file;

  @override
  void initState() {
    super.initState();
    _file = widget.images.fileFor(widget.name);
  }

  @override
  void didUpdateWidget(covariant _NoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.name != widget.name) {
      _file = widget.images.fileFor(widget.name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return FutureBuilder<File>(
      future: _file,
      builder: (BuildContext context, AsyncSnapshot<File> snapshot) {
        final File? file = snapshot.data;
        if (file == null || !file.existsSync()) {
          return _brokenImage(scheme);
        }
        return Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: () => _openPreview(file),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _thumbMaxWidth,
                  maxHeight: _thumbMaxHeight,
                ),
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (
                    BuildContext context,
                    Object error,
                    StackTrace? stackTrace,
                  ) => _brokenImage(scheme),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _brokenImage(ColorScheme scheme) {
    return Container(
      width: _thumbMaxWidth,
      height: 100,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
    );
  }

  Future<void> _openPreview(File file) async {
    // 预览时先交还焦点：返回时焦点会恢复给输入框，键盘就自己弹出来了。
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => _ImagePreviewPage(file: file),
      ),
    );
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }
}

class _ImagePreviewPage extends StatelessWidget {
  const _ImagePreviewPage({required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: Center(
              child: Image.file(
                file,
                fit: BoxFit.contain,
                errorBuilder:
                    (
                      BuildContext context,
                      Object error,
                      StackTrace? stackTrace,
                    ) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 48,
                    ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top,
            right: 8,
            child: Material(
              color: Colors.black.withValues(alpha: 0.35),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloorShell extends StatelessWidget {
  const _FloorShell({required this.floor, required this.children});

  final int floor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$floor',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.pendingImage,
    required this.canSend,
    required this.hintText,
    required this.onPickImage,
    required this.onDropPendingImage,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final File? pendingImage;
  final bool canSend;
  final String hintText;
  final VoidCallback onPickImage;
  final VoidCallback onDropPendingImage;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (pendingImage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          pendingImage!,
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (
                            BuildContext context,
                            Object error,
                            StackTrace? stackTrace,
                          ) => const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '发送时会附上这张图（动图保留动画）',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      IconButton(
                        tooltip: '移除图片',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: onDropPendingImage,
                      ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  IconButton(
                    tooltip: '添加图片',
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                    onPressed: onPickImage,
                  ),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      minLines: 1,
                      maxLines: 4,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: hintText,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    onPressed: canSend ? onSend : null,
                    tooltip: '发表',
                    icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
