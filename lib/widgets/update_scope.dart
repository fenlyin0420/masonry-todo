import 'package:flutter/widgets.dart';

import '../update/update_controller.dart';

/// 把 [UpdateController] 挂到树上，子树可用 [of] 取到。
/// [of] 用 findAncestorWidgetOfExactType，不建立依赖关系；
/// 状态变化的重建由 UpdateWatch 自己挂的 listener 驱动。
class UpdateScope extends InheritedNotifier<UpdateController> {
  const UpdateScope({
    super.key,
    required UpdateController super.notifier,
    required super.child,
  });

  static UpdateController? of(BuildContext context) {
    return context.findAncestorWidgetOfExactType<UpdateScope>()?.notifier;
  }
}
