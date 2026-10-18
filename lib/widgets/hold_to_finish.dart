import 'package:flutter/material.dart';

/// 长按计时：按住满 [duration] 触发 [onFinish]，松手、滑动或指针丢失都会取消，
/// 没触发完成的松手则算一次轻点（[onTap]）。
///
/// 触感反馈交给 [onFinish] 的调用方：完成待办和普通操作的手感不一样。
/// 直接用指针事件而不是 tap 手势竞技场：竞技场里 onTapUp 不保证到达
/// （比如按住期间 widget 被重建、指针路径失效），会让计时器无人取消地跑完。
class HoldToFinish extends StatefulWidget {
  const HoldToFinish({
    super.key,
    required this.enabled,
    required this.onFinish,
    required this.builder,
    this.onTap,
    this.duration = const Duration(seconds: 3),
    this.moveTolerance = 12,
  });

  final bool enabled;
  final VoidCallback onFinish;
  final VoidCallback? onTap;
  final Duration duration;
  final double moveTolerance;
  final Widget Function(BuildContext context, double progress) builder;

  @override
  State<HoldToFinish> createState() => HoldToFinishState();
}

class HoldToFinishState extends State<HoldToFinish>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int? _pointer;
  Offset _origin = Offset.zero;
  bool _moved = false;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _controller.addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(HoldToFinish oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pointer != null) _abort();
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _fired) return;
    _fired = true;
    widget.onFinish();
  }

  void _handleDown(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    _origin = event.position;
    _moved = false;
    if (widget.enabled) _controller.forward(from: 0);
  }

  void _handleMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _moved) return;
    if ((event.position - _origin).distance > widget.moveTolerance) {
      _moved = true;
      _abort();
    }
  }

  void _handleUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final bool fired = _fired;
    final bool moved = _moved;
    _abort();
    if (!fired && !moved) widget.onTap?.call();
  }

  void _handleCancel(PointerCancelEvent event) {
    if (event.pointer == _pointer) _abort();
  }

  void _abort() {
    _pointer = null;
    _fired = false;
    _moved = false;
    _controller.stop();
    if (_controller.value != 0) _controller.value = 0;
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handleDown,
      onPointerMove: _handleMove,
      onPointerUp: _handleUp,
      onPointerCancel: _handleCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, _) =>
            widget.builder(context, _controller.value),
      ),
    );
  }
}
