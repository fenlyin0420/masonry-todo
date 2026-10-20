import 'package:flutter/material.dart';

import '../models/entry.dart';
import '../store/entry_store.dart';
import '../widgets/store_scope.dart';

/// 新建与编辑共用一页。新建时返回即可保存：宁可之后去删，
/// 也别把刚敲进去的内容丢掉。
class EntryEditorPage extends StatefulWidget {
  const EntryEditorPage({super.key, this.entryId, this.kind = EntryKind.todo});

  /// 为 null 表示新建；否则编辑这条条目。
  final String? entryId;
  final EntryKind kind;

  @override
  State<EntryEditorPage> createState() => _EntryEditorPageState();
}

class _EntryEditorPageState extends State<EntryEditorPage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  late EntryKind _kind;
  bool _prefilled = false;
  bool _committed = false;

  bool get _editing => widget.entryId != null;

  String get _kindName => _kind == EntryKind.todo ? '待办' : '灵感';

  bool get _hasContent =>
      _title.text.trim().isNotEmpty || _body.text.trim().isNotEmpty;

  bool get _canSubmit => _editing || _hasContent;

  @override
  void initState() {
    super.initState();
    _kind = widget.kind;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    final String? id = widget.entryId;
    if (id == null) return;
    final Entry? entry = StoreScope.of(context).byId(id);
    if (entry == null) return;
    _kind = entry.kind;
    _title.text = entry.title;
    _body.text = entry.body;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// 写入并返回是否真的产生了改动。
  bool _save() {
    if (_committed) return false;
    final EntryStore store = StoreScope.of(context);
    final String? id = widget.entryId;
    if (id != null) {
      _committed = true;
      return store.update(id, title: _title.text, body: _body.text);
    }
    if (!_hasContent) return false;
    store.create(kind: _kind, title: _title.text, body: _body.text);
    _committed = true;
    return true;
  }

  void _submit() {
    _save();
    Navigator.of(context).pop();
  }

  /// 系统返回、AppBar 返回都走这里：有内容就先落库再离开。
  void _handleBack() {
    final bool changed = _save();
    if (changed) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('已保存到$_kindName'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool missing =
        _editing && StoreScope.of(context).byId(widget.entryId!) == null;
    if (missing) {
      return Scaffold(
        appBar: AppBar(title: const Text('编辑')),
        body: const Center(child: Text('这条内容已经不在了')),
      );
    }

    return PopScope(
      // 自己决定离开前是否保存，所以先拦下系统的返回。
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _editing
                ? '编辑$_kindName'
                : (_kind == EntryKind.todo ? '新建待办' : '记灵感'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: _canSubmit ? _submit : null,
              child: Text(_editing ? '保存' : '创建'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _title,
                autofocus: !_editing,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  hintText: '标题（可留空，自动取正文第一句）',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                minLines: 6,
                maxLines: 14,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _kind == EntryKind.todo
                      ? '正文：这件事具体要做什么'
                      : '正文：这个念头是什么样子的',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    _kind == EntryKind.todo
                        ? Icons.tips_and_updates_outlined
                        : Icons.auto_awesome_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _kind == EntryKind.todo
                          ? '创建后点进卡片，可以在下面继续记录你的想法与心得。'
                          : '灵感没有完成状态，随时可以回到这里补充新的念头。',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _editing ? '返回时自动保存改动。' : '直接返回也会保存，不会丢掉刚写的内容。',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '正文支持 Markdown：**加粗**、`代码`、- 列表、> 引用。',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
