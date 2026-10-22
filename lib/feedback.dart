import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 完成一记待办时的触感：一记重击，再两下轻击，像把卡片按进「已完成」。
///
/// 走 [HapticFeedback] 而不是振动插件：不需要 VIBRATE 权限，
/// 系统震动强度跟随用户的触感设置。
Future<void> finishFeedback() async {
  try {
    await HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 70));
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await HapticFeedback.lightImpact();
  } catch (error) {
    // 没有马达或通道不可用时静默，别让触感失败影响已完成状态。
    debugPrint('触感反馈失败：$error');
  }
}

/// 完成反馈即发即忘，调用方不用 await。
void playFinishFeedback() {
  unawaited(finishFeedback());
}

/// 按住卡片等它碎裂时的逐段震动：[step] 从 0 开始，每跨过一段一下，
/// 越往后越重。用的是系统触感，不需要 VIBRATE 权限。
void playHoldTick(int step) {
  unawaited(_holdTick(step));
}

Future<void> _holdTick(int step) async {
  await _safe(
    step >= 3 ? HapticFeedback.mediumImpact : HapticFeedback.selectionClick,
  );
}

/// 拖动排序落位时的一下轻震，确认顺序真的变了。
void playReorderFeedback() {
  unawaited(_safe(HapticFeedback.selectionClick));
}

/// 触感失败只记日志：没有马达或通道不可用时不该影响功能。
Future<void> _safe(Future<void> Function() impact) async {
  try {
    await impact();
  } catch (error) {
    debugPrint('触感反馈失败：$error');
  }
}
