import 'package:flutter/widgets.dart';

import '../store/todo_store.dart';

/// 把 [TodoStore] 挂到 widget 树上；store 变化时依赖它的 widget 自动重建。
class StoreScope extends InheritedNotifier<TodoStore> {
  const StoreScope({
    super.key,
    required TodoStore store,
    required super.child,
  }) : super(notifier: store);

  static TodoStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StoreScope>();
    assert(scope != null, 'StoreScope 没有挂在 widget 树上');
    return scope!.notifier!;
  }
}
