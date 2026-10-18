import 'package:flutter/widgets.dart';

import '../store/entry_store.dart';

/// 把 [EntryStore] 挂到 widget 树上；store 变化时依赖它的 widget 自动重建。
class StoreScope extends InheritedNotifier<EntryStore> {
  const StoreScope({super.key, required EntryStore store, required super.child})
    : super(notifier: store);

  static EntryStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StoreScope>();
    assert(scope != null, 'StoreScope 没有挂在 widget 树上');
    return scope!.notifier!;
  }
}
