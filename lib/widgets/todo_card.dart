import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/todo.dart';
import '../nav.dart';
import '../models/todo_text.dart';
import '../store/todo_store.dart';
import 'finish_aware.dart';
import 'hold_to_finish.dart';
import 'store_scope.dart';

/// 首页卡片：顶部标题（无标题取正文第一句）、下方正文预览、长按 3 秒完成。
class TodoCard extends StatelessWidget {
  const TodoCard({super.key, required this.todo});

  final Todo todo;

  static const BorderRadius radius = BorderRadius.all(Radius.circular(18));

  @override
  Widget build(BuildContext context) {
    final TodoStore store = StoreScope.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String title = displayTitle(todo);
    final String preview = bodyPreview(todo);

    return HoldToFinish(
      enabled: !todo.done,
      onFinish: () => store.setDone(todo.id, true),
      onTap: () => openDetail(context, todo.id),
      builder: (BuildContext context, double progress) {
        return FinishAware(
          done: todo.done,
          borderRadius: radius,
          child: Container(
            decoration: BoxDecoration(
              color: cardColorFor(context, todo.id),
              borderRadius: radius,
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
            child: Stack(
              children: <Widget>[
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (preview.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          preview,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        children: <Widget>[
                          Text(
                            formatMinute(todo.createdAt),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.85,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (todo.notes.isNotEmpty) ...<Widget>[
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
                    ),
                  ],
                ),
                if (progress > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(child: _HoldProgress(value: progress)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HoldProgress extends StatelessWidget {
  const _HoldProgress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.surface.withValues(alpha: 0.92),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8),
        ],
      ),
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          value: value,
          strokeWidth: 2.4,
          backgroundColor: scheme.primary.withValues(alpha: 0.18),
        ),
      ),
    );
  }
}
