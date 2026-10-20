import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../feedback.dart';
import '../models/entry.dart';
import '../models/entry_text.dart';
import '../nav.dart';
import '../store/entry_store.dart';
import 'finish_aware.dart';
import 'hold_to_finish.dart';
import 'markdown_view.dart';
import 'store_scope.dart';

/// 首页卡片：待办可以长按 3 秒完成，灵感只作记录。
/// 顶部标题（无标题取正文第一句）、正文预览、底部类型与时间。
class EntryCard extends StatelessWidget {
  const EntryCard({super.key, required this.entry});

  final Entry entry;

  static const BorderRadius radius = BorderRadius.all(Radius.circular(18));

  @override
  Widget build(BuildContext context) {
    final EntryStore store = StoreScope.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color accent = accentFor(entry.id);
    final String title = displayTitle(entry);
    final ({bool visible, int skip}) preview = previewSlice(entry);
    final bool done = entry.isDone;
    final bool canFinish = entry.isTodo && !done;
    final String timeText = done
        ? '完成于 ${formatCardTime(entry.doneAt ?? entry.createdAt)}'
        : formatCardTime(entry.createdAt);

    return HoldToFinish(
      enabled: canFinish,
      onFinish: () {
        playFinishFeedback();
        store.setDone(entry.id, true);
      },
      onTap: () => openDetail(context, entry.id),
      builder: (BuildContext context, double progress) {
        return FinishAware(
          done: done,
          borderRadius: radius,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: done
                  ? doneCardColorFor(context)
                  : cardColorFor(context, entry.id),
              borderRadius: radius,
              border: Border.all(
                color: scheme.outlineVariant.withValues(
                  alpha: done ? 0.35 : 0.6,
                ),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
            child: Stack(
              children: <Widget>[
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: EdgeInsets.only(right: done ? 26 : 0),
                      child: Text(
                        title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          color: done
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface,
                          decoration: done ? TextDecoration.lineThrough : null,
                          decorationColor: scheme.onSurfaceVariant.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ),
                    if (preview.visible)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: MarkdownText(
                          entry.body,
                          skipChars: preview.skip,
                          maxLines: 4,
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
                          if (entry.isTodo)
                            Expanded(
                              child: _Meta(
                                text: timeText,
                                color: scheme.onSurfaceVariant,
                              ),
                            )
                          else
                            Expanded(
                              child: _Meta(
                                text: timeText,
                                color: scheme.onSurfaceVariant,
                                icon: Icons.lightbulb_outline_rounded,
                                iconColor: accent,
                              ),
                            ),
                          if (entry.notes.isNotEmpty) ...<Widget>[
                            const SizedBox(width: 6),
                            _Meta(
                              text: '${entry.notes.length}',
                              color: scheme.onSurfaceVariant,
                              icon: Icons.chat_bubble_outline_rounded,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (done)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _DoneBadge(color: accent),
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

/// 底部的一行小字，图标可选。
class _Meta extends StatelessWidget {
  const _Meta({
    required this.text,
    required this.color,
    this.icon,
    this.iconColor,
  });

  final String text;
  final Color color;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: color.withValues(alpha: 0.85));
    final IconData? glyph = icon;
    if (glyph == null) {
      return Text(text, style: style, overflow: TextOverflow.ellipsis);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          glyph,
          size: 12,
          color: iconColor ?? color.withValues(alpha: 0.85),
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(text, style: style, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// 已完成角标：用这张卡原本的强调色，灰掉的卡面上留一点身份。
class _DoneBadge extends StatelessWidget {
  const _DoneBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Icon(Icons.check_rounded, size: 13, color: color),
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
