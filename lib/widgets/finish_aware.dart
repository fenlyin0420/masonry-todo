import 'package:flutter/material.dart';

/// 完成态的视觉：整体压暗 + 一条划过的斜线。动画由 [done] 变化驱动。
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
      duration: const Duration(milliseconds: 560),
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
    final slashColor = scheme.onSurface.withValues(alpha: 0.55);
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final value = _controller.value;
        if (value == 0) return child!;
        final dim = Curves.easeOut.transform(value);
        final slash = Curves.easeInOutCubic.transform(
          ((value - 0.25) / 0.75).clamp(0.0, 1.0),
        );
        return Stack(
          children: <Widget>[
            Opacity(opacity: 1 - 0.45 * dim, child: child),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: widget.borderRadius,
                    color: Colors.black.withValues(alpha: 0.24 * dim),
                  ),
                ),
              ),
            ),
            if (slash > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _SlashPainter(
                      progress: slash,
                      color: slashColor,
                      strokeWidth: 2.2,
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

class _SlashPainter extends CustomPainter {
  const _SlashPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || size.isEmpty) return;
    final start = Offset(size.width * 0.14, size.height * 0.87);
    final end = Offset(size.width * 0.87, size.height * 0.13);
    final current = Offset.lerp(start, end, progress)!;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, current, paint);
  }

  @override
  bool shouldRepaint(_SlashPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}
