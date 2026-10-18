import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../feedback.dart';
import '../models/entry.dart';
import '../models/entry_text.dart';
import '../nav.dart';
import '../store/entry_store.dart';
import 'check_square.dart';
import 'finish_aware.dart';
import 'store_scope.dart';

/// 列表形态的一行：待办前面方框点击完成，灵感前面是灯泡；
/// 点内容都进详情。
class EntryRow extends StatelessWidget {
  const EntryRow({super.key, required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final EntryStore store = StoreScope.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color accent = accentFor(entry.id);
    final String title = displayTitle(entry);
    final String preview = bodyPreview(entry);
    final bool done = entry.isDone;
    final BorderRadius radius = BorderRadius.circular(16);
    final String timeText = done
        ? '完成于 ${formatCardTime(entry.doneAt ?? entry.createdAt)}'
        : formatCardTime(entry.createdAt);

    return FinishAware(
      done: done,
      borderRadius: radius,
      child: Material(
        color: done
            ? doneCardColorFor(context)
            : cardColorFor(context, entry.id),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: done ? 0.35 : 0.6),
          ),
        ),
        child: InkWell(
          onTap: () => openDetail(context, entry.id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (entry.isTodo)
                  CheckSquare(
                    checked: done,
                    onTap: () => _toggleDone(context, store, title),
                  )
                else
                  _KindIcon(accent: accent),
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
                          decoration: done
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: scheme.onSurfaceVariant.withValues(
                            alpha: 0.6,
                          ),
                          color: done
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface,
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
                          Flexible(
                            child: Text(
                              timeText,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.85,
                                ),
                              ),
                            ),
                          ),
                          if (entry.notes.isNotEmpty) ...<Widget>[
                            const SizedBox(width: 10),
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 12,
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.85,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '${entry.notes.length}',
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

  void _toggleDone(BuildContext context, EntryStore store, String title) {
    final bool willBeDone = !entry.done;
    if (willBeDone) playFinishFeedback();
    store.setDone(entry.id, willBeDone);
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
            onPressed: () => store.setDone(entry.id, false),
          ),
        ),
      );
  }
}

/// 灵感在列表里的标记，占住待办方框的位置，视觉上左右对齐。
class _KindIcon extends StatelessWidget {
  const _KindIcon({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Center(
        child: Icon(Icons.lightbulb_outline_rounded, size: 20, color: accent),
      ),
    );
  }
}
