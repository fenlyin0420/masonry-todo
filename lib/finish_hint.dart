import 'package:flutter/material.dart';

import 'feedback.dart';
import 'nav.dart';

/// 待办没写过感想就想完成时的提示：说清缺什么，并留一条直接去写的路。
///
/// 首页卡片长按和列表方框都会走这里，完成状态一概不动。
void showNoteRequiredHint(BuildContext context, String entryId) {
  playRejectFeedback();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Text('先写一条感想，再把它完成'),
        // 带 action 的 SnackBar 新版默认 persist，会一直挂在屏幕上。
        persist: false,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '去写',
          onPressed: () => openDetail(context, entryId),
        ),
      ),
    );
}
