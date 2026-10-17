import 'package:flutter/material.dart';

/// 列表模式前面的方框：点一下切换完成状态。
class CheckSquare extends StatelessWidget {
  const CheckSquare({
    super.key,
    required this.checked,
    required this.onTap,
  });

  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: checked ? '标记为未完成' : '标记为已完成',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                color: checked ? scheme.primary : Colors.transparent,
                border: Border.all(
                  color: checked
                      ? scheme.primary
                      : scheme.onSurfaceVariant.withValues(alpha: 0.55),
                  width: 1.8,
                ),
              ),
              child: checked
                  ? Icon(Icons.check_rounded, size: 15, color: scheme.onPrimary)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
