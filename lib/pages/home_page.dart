import 'dart:async';

import 'package:flutter/material.dart';

import '../backup_flow.dart';
import '../models/entry.dart';
import '../models/entry_text.dart';
import '../nav.dart';
import '../store/entry_storage.dart';
import '../store/entry_store.dart';
import '../update/update_controller.dart';
import '../widgets/entry_card.dart';
import '../widgets/entry_row.dart';
import '../widgets/masonry_grid.dart';
import '../widgets/store_scope.dart';
import '../widgets/update_scope.dart';
import '../widgets/update_watch.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final EntryStore store = StoreScope.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final EntryKind kind = store.kind;
    final bool isTodo = kind == EntryKind.todo;
    final List<Entry> entries = store.visibleEntries;
    final UpdateController? update = UpdateScope.of(context);

    final Widget page = Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('拾记'),
            const SizedBox(height: 2),
            Text(
              _subtitle(store, kind),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          if (update != null) ...<Widget>[
            IconButton(
              tooltip: '检查更新',
              icon: const Icon(Icons.system_update_alt_rounded, size: 20),
              onPressed: () => update.checkNow(manual: true),
            ),
            const SizedBox(width: 4),
          ],
          _ViewModeToggle(mode: store.viewMode, onChanged: store.setViewMode),
          const _BackupMenu(),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openCreate(context, kind),
        icon: Icon(
          isTodo ? Icons.add_rounded : Icons.lightbulb_outline_rounded,
        ),
        label: Text(isTodo ? '新建待办' : '记灵感'),
      ),
      body: Column(
        children: <Widget>[
          _KindTabs(
            kind: kind,
            todoCount: store.activeCount(),
            ideaCount: store.countOf(EntryKind.idea),
            onChanged: store.setKind,
          ),
          Expanded(
            child: entries.isEmpty
                ? _EmptyState(kind: kind)
                : (store.viewMode == ViewMode.grid
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          child: MasonryTwoColumn<Entry>(
                            items: entries,
                            heightEstimator: _estimateCardHeight,
                            itemBuilder: (BuildContext context, Entry entry) =>
                                EntryCard(
                                  key: ValueKey<String>(entry.id),
                                  entry: entry,
                                ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          itemCount: entries.length,
                          separatorBuilder:
                              (BuildContext context, int index) =>
                                  const SizedBox(height: 10),
                          itemBuilder: (BuildContext context, int index) {
                            final Entry entry = entries[index];
                            return EntryRow(
                              key: ValueKey<String>(entry.id),
                              entry: entry,
                            );
                          },
                        )),
          ),
        ],
      ),
    );
    if (update == null) return _StorageAlerts(child: page);
    return _StorageAlerts(
      child: UpdateWatch(controller: update, child: page),
    );
  }

  static String _subtitle(EntryStore store, EntryKind kind) {
    if (kind == EntryKind.idea) {
      final int count = store.countOf(EntryKind.idea);
      return count == 0 ? '还没有灵感' : '$count 条灵感';
    }
    final int total = store.countOf(EntryKind.todo);
    if (total == 0) return '还没有待办';
    final int active = store.activeCount();
    if (active == 0) return '全部完成 · 共 $total 项';
    return '$active 项未完成 · 共 $total 项';
  }

  /// 卡片高度粗估，只用来把条目分到左右两列：累计更矮的那列拿下一个。
  static double _estimateCardHeight(Entry entry) {
    final int titleChars = displayTitle(entry).length;
    final int previewChars = bodyPreview(entry).length;
    final int titleLines = (titleChars / 11).ceil().clamp(1, 3);
    final int previewLines = previewChars == 0
        ? 0
        : (previewChars / 15).ceil().clamp(1, 4);
    return 96 + titleLines * 21 + previewLines * 18;
  }
}

/// 备份入口：导出成文件、从文件导入。放在首页右上，不占列表空间。
enum _BackupAction { export, import }

class _BackupMenu extends StatelessWidget {
  const _BackupMenu();

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_BackupAction>(
      tooltip: '备份',
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      // over 会把菜单压在按钮上，把三点遮掉；改成从按钮下方展开。
      position: PopupMenuPosition.under,
      onSelected: (_BackupAction action) {
        switch (action) {
          case _BackupAction.export:
            unawaited(exportBackup(context));
          case _BackupAction.import:
            unawaited(importBackup(context));
        }
      },
      itemBuilder: (BuildContext context) =>
          const <PopupMenuEntry<_BackupAction>>[
            PopupMenuItem<_BackupAction>(
              value: _BackupAction.export,
              child: _BackupMenuRow(
                icon: Icons.ios_share_rounded,
                label: '导出备份',
              ),
            ),
            PopupMenuItem<_BackupAction>(
              value: _BackupAction.import,
              child: _BackupMenuRow(
                icon: Icons.unarchive_outlined,
                label: '导入备份',
              ),
            ),
          ],
    );
  }
}

class _BackupMenuRow extends StatelessWidget {
  const _BackupMenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 18),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}

/// 把存储层的异常摆到用户面前：载入时走了兜底、保存失败。两者都不该静默。
class _StorageAlerts extends StatefulWidget {
  const _StorageAlerts({required this.child});

  final Widget child;

  @override
  State<_StorageAlerts> createState() => _StorageAlertsState();
}

class _StorageAlertsState extends State<_StorageAlerts> {
  EntryStore? _store;
  Object? _shownError;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final EntryStore store = StoreScope.of(context);
    if (!identical(store, _store)) {
      _store?.removeListener(_schedule);
      _store = store..addListener(_schedule);
    }
    _schedule();
  }

  @override
  void dispose() {
    _store?.removeListener(_schedule);
    super.dispose();
  }

  /// store 变化可能发生在 build 期间，提示推到这一帧之后再弹。
  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _report();
    });
  }

  void _report() {
    final EntryStore? store = _store;
    if (store == null) return;

    final RecoverySource? recovery = store.takeRecoveryNotice();
    if (recovery != null) {
      _snack(
        recovery == RecoverySource.backup
            ? '上次的数据读不出来，已从自动备份恢复'
            : '上次没存完就退出了，已恢复到最后一次改动',
      );
    }

    final Object? error = store.saveError;
    if (error == null) {
      _shownError = null;
      return;
    }
    if (identical(error, _shownError)) return;
    _shownError = error;
    _snack(
      '保存失败，这次改动还没写进手机',
      action: SnackBarAction(
        label: '重试',
        onPressed: () => store.retrySave(),
      ),
    );
  }

  void _snack(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: action,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _KindTabs extends StatelessWidget {
  const _KindTabs({
    required this.kind,
    required this.todoCount,
    required this.ideaCount,
    required this.onChanged,
  });

  final EntryKind kind;
  final int todoCount;
  final int ideaCount;
  final ValueChanged<EntryKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _TabButton(
                icon: Icons.checklist_rounded,
                label: '待办',
                count: todoCount == 0 ? null : todoCount,
                selected: kind == EntryKind.todo,
                onTap: () => onChanged(EntryKind.todo),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: _TabButton(
                icon: Icons.lightbulb_outline_rounded,
                label: '灵感',
                count: ideaCount == 0 ? null : ideaCount,
                selected: kind == EntryKind.idea,
                onTap: () => onChanged(EntryKind.idea),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color foreground = selected
        ? scheme.onSurface
        : scheme.onSurfaceVariant;
    final int? badge = count;
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 38,
          decoration: BoxDecoration(
            // 未选中不能用 Colors.transparent：它是透明黑，Color.lerp 不按预乘
            // 插值，补间中途会变成半透明灰色，切换时底色闪一下。
            color: scheme.surface.withValues(alpha: selected ? 1 : 0),
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 5,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 17,
                color: selected ? scheme.primary : foreground,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: foreground,
                ),
              ),
              if (badge != null) ...<Widget>[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: foreground.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$badge',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.mode, required this.onChanged});

  final ViewMode mode;
  final ValueChanged<ViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ModeButton(
            icon: Icons.grid_view_rounded,
            tooltip: '卡片',
            selected: mode == ViewMode.grid,
            onTap: () => onChanged(ViewMode.grid),
          ),
          _ModeButton(
            icon: Icons.view_list_rounded,
            tooltip: '列表',
            selected: mode == ViewMode.list,
            onTap: () => onChanged(ViewMode.list),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            // 同 _TabButton：未选中用同色调的零透明，避免补间经过灰色。
            color: scheme.surface.withValues(alpha: selected ? 1 : 0),
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected
                ? <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 18,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.kind});

  final EntryKind kind;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isTodo = kind == EntryKind.todo;
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              isTodo
                  ? Icons.dashboard_customize_outlined
                  : Icons.lightbulb_outline_rounded,
              size: 52,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 14),
            Text(
              isTodo ? '还没有待办' : '还没有灵感',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isTodo ? '点右下角「新建待办」记下第一件事' : '点右下角「记灵感」留下第一个念头',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
