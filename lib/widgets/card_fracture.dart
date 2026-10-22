import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 长按完成时盖在卡片上的碎裂：裂纹从撞击点往外长、边裂边加宽，
/// 缝里透出页面底色，看上去像卡片正被掰开。
///
/// 只画裂纹、不重绘卡片内容：每帧开销是一次 CustomPaint，
/// 卡片本身不必为了碎裂被复制成好几块。
class CardFracture extends StatefulWidget {
  const CardFracture({
    super.key,
    required this.seed,
    required this.progress,
    required this.borderRadius,
  });

  /// 同一个条目每次长按裂开的样子要一样，图案由这个种子决定。
  final int seed;

  /// 长按进度 0..1。
  final double progress;
  final BorderRadius borderRadius;

  @override
  State<CardFracture> createState() => _CardFractureState();
}

class _CardFractureState extends State<CardFracture> {
  late FracturePattern _pattern = FracturePattern.generate(widget.seed);

  @override
  void didUpdateWidget(CardFracture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seed != widget.seed) {
      _pattern = FracturePattern.generate(widget.seed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: CustomPaint(
          painter: _FracturePainter(
            pattern: _pattern,
            progress: widget.progress,
            seam: Theme.of(context).scaffoldBackgroundColor,
          ),
        ),
      ),
    );
  }
}

/// 一张卡片的裂纹图案。坐标归一化到 0..1，画的时候再乘实际尺寸，
/// 所以卡片长宽变了也不用重新生成。
class FracturePattern {
  FracturePattern._(this.impact, this.cracks);

  final Offset impact;
  final List<FractureCrack> cracks;

  factory FracturePattern.generate(int seed) {
    final math.Random random = math.Random(seed);
    // 撞击点压在卡片中间一带：太靠边的话裂纹大半截在卡片外面，看不出来。
    final Offset impact = Offset(
      0.3 + random.nextDouble() * 0.4,
      0.28 + random.nextDouble() * 0.36,
    );
    final List<FractureCrack> cracks = <FractureCrack>[];
    final List<List<Offset>> rays = _burst(
      cracks,
      impact,
      random,
      count: 5 + random.nextInt(3),
      startBase: 0,
      span: 0.26,
      weight: 1,
    );

    // 第二处撞击：第一处甩出去的一团，裂纹自己再裂一遍。
    final double jump = random.nextDouble() * math.pi * 2;
    final Offset impact2 = Offset(
      (impact.dx + math.cos(jump) * 0.26).clamp(0.12, 0.88).toDouble(),
      (impact.dy + math.sin(jump) * 0.24).clamp(0.12, 0.88).toDouble(),
    );
    _burst(
      cracks,
      impact2,
      random,
      count: 3 + random.nextInt(2),
      startBase: 0.34,
      span: 0.3,
      weight: 0.72,
    );

    // 环向裂纹：把相邻两道主裂纹的外段连起来，玻璃碎成块就是靠它。
    for (int i = 0; i < rays.length; i++) {
      if (random.nextDouble() < 0.3) continue;
      final List<Offset> from = rays[i];
      final List<Offset> to = rays[(i + 1) % rays.length];
      final Offset a = from[(from.length * 0.55).floor()];
      final Offset b = to[(to.length * 0.45).floor()];
      final Offset mid = Offset(
        (a.dx + b.dx) / 2 + (random.nextDouble() - 0.5) * 0.14,
        (a.dy + b.dy) / 2 + (random.nextDouble() - 0.5) * 0.14,
      );
      cracks.add(
        FractureCrack(
          points: <Offset>[a, mid, b],
          start: 0.5 + random.nextDouble() * 0.26,
          weight: 0.5,
        ),
      );
    }
    return FracturePattern._(impact, cracks);
  }

  /// 从一个点炸开一组裂纹，返回主裂纹的折线，供环向裂纹去连。
  static List<List<Offset>> _burst(
    List<FractureCrack> cracks,
    Offset from,
    math.Random random, {
    required int count,
    required double startBase,
    required double span,
    required double weight,
  }) {
    final List<List<Offset>> rays = <List<Offset>>[];
    final double phase = random.nextDouble() * math.pi * 2;
    for (int i = 0; i < count; i++) {
      final double angle =
          phase + i * math.pi * 2 / count + (random.nextDouble() - 0.5) * 0.5;
      // 主裂纹依次露出，不是几条一起冒出来。
      final double start = startBase + i / count * span;
      final List<Offset> main = _ray(
        from,
        angle,
        random,
        step: 0.15 + random.nextDouble() * 0.1,
      );
      cracks.add(FractureCrack(points: main, start: start, weight: weight));
      rays.add(main);

      // 分叉：从主裂纹中段斜着再裂一道，露得晚、细一点。
      if (random.nextDouble() < 0.75 && main.length > 2) {
        final int at = 1 + random.nextInt(main.length - 2);
        final double branchAngle =
            angle +
            (random.nextBool() ? 1 : -1) * (0.35 + random.nextDouble() * 0.5);
        cracks.add(
          FractureCrack(
            points: _ray(
              main[at],
              branchAngle,
              random,
              step: 0.09 + random.nextDouble() * 0.07,
              segments: 2 + random.nextInt(2),
            ),
            start: (start + 0.28).clamp(0.0, 0.82).toDouble(),
            weight: weight * 0.6,
          ),
        );
      }
    }
    return rays;
  }

  static List<Offset> _ray(
    Offset from,
    double angle,
    math.Random random, {
    required double step,
    int segments = 4,
  }) {
    final List<Offset> points = <Offset>[from];
    Offset current = from;
    double heading = angle;
    for (int i = 0; i < segments; i++) {
      // 每段偏一点，裂出来的是一条折线而不是直线。
      heading += (random.nextDouble() - 0.5) * 0.55;
      current += Offset(math.cos(heading) * step, math.sin(heading) * step);
      points.add(current);
    }
    return points;
  }
}

/// 一条裂纹：折线 + 露出门槛 + 粗细权重。
class FractureCrack {
  const FractureCrack({
    required this.points,
    required this.start,
    required this.weight,
  });

  final List<Offset> points;
  final double start;
  final double weight;
}

class _FracturePainter extends CustomPainter {
  const _FracturePainter({
    required this.pattern,
    required this.progress,
    required this.seam,
  });

  final FracturePattern pattern;
  final double progress;
  final Color seam;

  @override
  void paint(Canvas canvas, Size size) {
    final double p = progress.clamp(0.0, 1.0);
    if (p <= 0 || size.isEmpty) return;
    final Rect rect = Offset.zero & size;

    // 撞击点周围先压暗一块，卡片不只是被画了几条线，而是被撞得发虚。
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(
            pattern.impact.dx * 2 - 1,
            pattern.impact.dy * 2 - 1,
          ),
          radius: 1.1,
          colors: <Color>[
            Colors.black.withValues(alpha: 0.12 * p * p),
            Colors.transparent,
          ],
          stops: const <double>[0, 1],
        ).createShader(rect),
    );

    // 裂缝里看到的是压暗的底色：直接用页面底色的话，浅色卡片上根本看不出
    // 是「裂开」还是「画了条线」。
    final Paint gap = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Color.lerp(seam, Colors.black, 0.26 + 0.22 * p)!;
    final Paint shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.black.withValues(alpha: 0.14 + 0.3 * p);
    final Paint highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.45 * p);

    for (final FractureCrack crack in pattern.cracks) {
      final double t = ((p - crack.start) / (1 - crack.start)).clamp(0.0, 1.0);
      if (t <= 0) continue;
      // 二次缓入缓出：裂纹刚冒头时慢慢延伸，越到后面裂得越快。
      final Path? path = _partial(crack.points, t * t * (3 - 2 * t), size);
      if (path == null) continue;

      // 缝先画宽一点（页面底色），再在中间压一道暗线、旁边提一道高光：
      // 三层叠起来就是「裂开一条缝」，而不是在卡片上画了根线。
      // 刚裂出来的那几像素要细，一边裂一边加宽，否则短段看上去像抹了一笔。
      final double grow = 0.35 + 0.65 * t;
      gap.strokeWidth = (1 + 3.4 * p) * crack.weight * grow;
      shadow.strokeWidth = (0.7 + 0.9 * p) * crack.weight * grow;
      highlight.strokeWidth = 0.9 * crack.weight * grow;

      canvas.drawPath(path, gap);
      canvas.drawPath(path, shadow);
      canvas.save();
      canvas.translate(0.8, 0.8);
      canvas.drawPath(path, highlight);
      canvas.restore();
    }
  }

  /// 只画折线的前 [fraction] 段，用来让裂纹一点点长出来。
  Path? _partial(List<Offset> points, double fraction, Size size) {
    if (points.length < 2 || fraction <= 0) return null;
    final List<Offset> scaled = <Offset>[
      for (final Offset point in points)
        Offset(point.dx * size.width, point.dy * size.height),
    ];
    double total = 0;
    for (int i = 1; i < scaled.length; i++) {
      total += (scaled[i] - scaled[i - 1]).distance;
    }
    final double target = total * fraction;
    if (target <= 0) return null;

    final Path path = Path()..moveTo(scaled.first.dx, scaled.first.dy);
    double walked = 0;
    for (int i = 1; i < scaled.length; i++) {
      final double segment = (scaled[i] - scaled[i - 1]).distance;
      if (segment <= 0) continue;
      if (walked + segment <= target) {
        path.lineTo(scaled[i].dx, scaled[i].dy);
        walked += segment;
        continue;
      }
      final Offset end = Offset.lerp(
        scaled[i - 1],
        scaled[i],
        (target - walked) / segment,
      )!;
      path.lineTo(end.dx, end.dy);
      break;
    }
    return path;
  }

  @override
  bool shouldRepaint(_FracturePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.pattern != pattern ||
      oldDelegate.seam != seam;
}
