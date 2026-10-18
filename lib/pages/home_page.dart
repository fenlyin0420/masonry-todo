import 'package:flutter/material.dart';

import '../models/todo.dart';
import '../models/todo_text.dart';
import '../nav.dart';
import '../store/todo_storage.dart';
import '../store/todo_store.dart';
import '../update/update_controller.dart';
import '../widgets/masonry_grid.dart';
import '../widgets/store_scope.dart';
import '../widgets/todo_card.dart';
import '../widgets/todo_row.dart';
import '../widgets/update_scope.dart';
import '../widgets/update_watch.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final TodoStore store = StoreScope.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final List<Todo> todos = store.todos;
    final UpdateController? update = UpdateScope.of(context);

    final Widget page = Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('Masonry Todo'),
            const SizedBox(height: 2),
            Text(
              todos.isEmpty
                  ? '还没有记录'
                  : '${store.activeCount} 项未完成 · 共 ${todos.length} 项',
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
          const SizedBox(width: 12),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openCreate(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建'),
      ),
      body: todos.isEmpty
          ? const _EmptyState()
          : (store.viewMode == ViewMode.grid
                ? SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    child: MasonryTwoColumn<Todo>(
                      items: todos,
                      heightEstimator: _estimateCardHeight,
                      itemBuilder: (BuildContext context, Todo todo) =>
                          TodoCard(key: ValueKey<String>(todo.id), todo: todo),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                    itemCount: todos.length,
                    separatorBuilder: (BuildContext context, int index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final Todo todo = todos[index];
                      return TodoRow(
                        key: ValueKey<String>(todo.id),
                        todo: todo,
                      );
                    },
                  )),
    );
    if (update == null) return page;
    return UpdateWatch(controller: update, child: page);
  }

  /// 卡片高度粗估，只用来把条目分到左右两列：累计更矮的那列拿下一个。
  static double _estimateCardHeight(Todo todo) {
    final int titleChars = displayTitle(todo).length;
    final int previewChars = bodyPreview(todo).length;
    final int titleLines = (titleChars / 11).ceil().clamp(1, 3);
    final int previewLines = previewChars == 0
        ? 0
        : (previewChars / 15).ceil().clamp(1, 4);
    return 96 + titleLines * 21 + previewLines * 18;
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
            color: selected ? scheme.surface : Colors.transparent,
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
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.dashboard_customize_outlined,
              size: 52,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 14),
            Text(
              '还没有 Todo',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '点右下角「新建」记下第一件事',
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
