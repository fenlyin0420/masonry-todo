import 'package:flutter/material.dart';

import '../models/todo.dart';
import '../models/todo_text.dart';
import '../store/todo_store.dart';
import '../widgets/store_scope.dart';

/// 详情：第一楼是这条 todo 本身（标题可空），分割线以下是记录想法的楼层。
class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.todoId});

  final String todoId;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final TodoStore store = StoreScope.of(context);
    final String text = _input.text;
    if (text.trim().isEmpty) return;
    store.addNote(widget.todoId, text);
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

  Future<void> _confirmDelete(Todo todo) async {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除这条 Todo？'),
        content: Text(
          '「${displayTitle(todo)}」以及它的全部记录都会被删掉，无法恢复。',
        ),
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
    StoreScope.of(context).delete(todo.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final TodoStore store = StoreScope.of(context);
    final Todo? todo = store.byId(widget.todoId);
    if (todo == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('详情')),
        body: const Center(child: Text('这条 todo 已经不在了')),
      );
    }
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('详情'),
        actions: <Widget>[
          IconButton(
            tooltip: '删除',
            onPressed: () => _confirmDelete(todo),
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
                _OriginFloor(todo: todo),
                _ThreadDivider(count: todo.notes.length),
                if (todo.notes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(
                        '还没有记录，写下你对这个任务的想法',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                for (int i = 0; i < todo.notes.length; i++)
                  _NoteFloor(floor: i + 2, note: todo.notes[i]),
              ],
            ),
          ),
          _Composer(
            controller: _input,
            focusNode: _inputFocus,
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

/// 第一楼：这条 todo 本身。
class _OriginFloor extends StatelessWidget {
  const _OriginFloor({required this.todo});

  final Todo todo;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String title = todo.title.trim();
    final String body = todo.body.trim();

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
          children: <Widget>[
            _StatusPill(done: todo.done),
            const Spacer(),
            Text(
              todo.done
                  ? '创建于 ${formatMinute(todo.createdAt)} · 完成于 ${formatMinute(todo.doneAt ?? todo.createdAt)}'
                  : formatMinute(todo.createdAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = done ? scheme.onSurfaceVariant : scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        done ? '已完成' : '进行中',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// 分割线：上面是 todo 本体，下面是记录。
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
          Expanded(
            child: Divider(color: scheme.outlineVariant, height: 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              count == 0 ? '记录' : '记录 · $count',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Divider(color: scheme.outlineVariant, height: 1),
          ),
        ],
      ),
    );
  }
}

class _NoteFloor extends StatelessWidget {
  const _NoteFloor({required this.floor, required this.note});

  final int floor;
  final Note note;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return _FloorShell(
      floor: floor,
      children: <Widget>[
        Text(
          note.text,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            formatMinute(note.createdAt),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
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
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;

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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 4,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: '写下你的想法、心得…',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: onSend,
                tooltip: '发表',
                icon: const Icon(Icons.arrow_upward_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
