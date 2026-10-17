import 'package:flutter/material.dart';

import '../store/todo_store.dart';
import '../widgets/store_scope.dart';

/// 新建 todo：标题可以留空，留空时卡片标题取正文第一句。
class CreateTodoPage extends StatefulWidget {
  const CreateTodoPage({super.key});

  @override
  State<CreateTodoPage> createState() => _CreateTodoPageState();
}

class _CreateTodoPageState extends State<CreateTodoPage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _title.text.trim().isNotEmpty || _body.text.trim().isNotEmpty;

  void _submit() {
    if (!_canSubmit) return;
    final TodoStore store = StoreScope.of(context);
    store.create(title: _title.text, body: _body.text);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('新建 Todo'),
        actions: <Widget>[
          TextButton(
            onPressed: _canSubmit ? _submit : null,
            child: const Text('创建'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_title, _body]),
        builder: (BuildContext context, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: _title,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
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
                  decoration: const InputDecoration(
                    hintText: '正文：这件事具体要做什么',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.tips_and_updates_outlined,
                      size: 14,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '创建后点进卡片，可以在下面继续记录你的想法与心得。',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
