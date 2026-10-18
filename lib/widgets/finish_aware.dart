import 'package:flutter/material.dart';

/// 完成态的视觉：彩色被抽干、整体轻微压暗。
/// 动画由 [done] 变化驱动；卡片底色与标题划线由调用方跟着切换。
class FinishAware extends StatefulWidget {
  const FinishAware({
    super.key,
    required this.done,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
  });

  final bool done;
  final Widget child;
  final BorderRadius borderRadius;

  @override
  State<FinishAware> createState() => _FinishAwareState();
}

class _FinishAwareState extends State<FinishAware>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
      value: widget.done ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(FinishAware oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.done == oldWidget.done) return;
    if (widget.done) {
      _controller.forward(from: 0);
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final value = _controller.value;
        if (value == 0) return child!;
        final dim = Curves.easeOut.transform(value);
        return Stack(
          children: <Widget>[
            ColorFiltered(
              colorFilter: ColorFilter.matrix(_saturationMatrix(dim)),
              child: Opacity(opacity: 1 - 0.18 * dim, child: child),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: widget.borderRadius,
                    color: scheme.surface.withValues(alpha: 0.10 * dim),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 亮度保持的降饱和矩阵：saturation 从 1 落到 0.18。
List<double> _saturationMatrix(double amount) {
  const double lr = 0.2126;
  const double lg = 0.7152;
  const double lb = 0.0722;
  final double s = 1 - 0.82 * amount;
  final double sr = (1 - s) * lr;
  final double sg = (1 - s) * lg;
  final double sb = (1 - s) * lb;
  return <double>[
    sr + s, sg, sb, 0, 0, //
    sr, sg + s, sb, 0, 0, //
    sr, sg, sb + s, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}
