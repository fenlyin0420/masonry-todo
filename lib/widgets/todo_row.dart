import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/todo.dart';
import '../models/todo_text.dart';
import '../nav.dart';
import '../store/todo_store.dart';
import 'check_square.dart';
import 'finish_aware.dart';
import 'store_scope.dart';

/// 列表形态的一行：前面方框点击完成，点内容进详情。
class TodoRow extends StatelessWidget {
  const TodoRow({super.key, required this.todo});

  final Todo todo;

  @override
  Widget build(BuildContext context) {
    final TodoStore store = StoreScope.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String title = displayTitle(todo);
    final String preview = bodyPreview(todo);
    final BorderRadius radius = BorderRadius.circular(16);

    return FinishAware(
      done: todo.done,
      borderRadius: radius,
      child: Material(
        color: cardColorFor(context, todo.id),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: InkWell(
          onTap: () => openDetail(context, todo.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CheckSquare(
                  checked: todo.done,
                  onTap: () {
                    final bool willBeDone = !todo.done;
                    store.setDone(todo.id, willBeDone);
                    if (!willBeDone) return;
                    // 完成的行会沉底，给一次撤销的机会，避免误点后还得翻回去找。
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text('「$title」已完成'),
                          duration: const Duration(seconds: 3),
                          behavior: SnackBarBehavior.floating,
                          action: SnackBarAction(
                            label: '撤销',
                            onPressed: () => store.setDone(todo.id, false),
                          ),
                        ),
                      );
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          decoration: todo.done
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: scheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                          color: scheme.onSurface,
                        ),
                      ),
                      if (preview.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            preview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: <Widget>[
                          Text(
                            formatMinute(todo.createdAt),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.85,
                              ),
                            ),
                          ),
                          if (todo.notes.isNotEmpty) ...<Widget>[
                            const SizedBox(width: 10),
                            Icon(
                              Icons.mode_comment_outlined,
                              size: 12,
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.85,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${todo.notes.length}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.85,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
