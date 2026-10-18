import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_todo/widgets/hold_to_finish.dart';

void main() {
  testWidgets('禁用时轻点触发 onTap，不启动长按计时', (WidgetTester tester) async {
    int taps = 0;
    int finishes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 160,
              child: HoldToFinish(
                enabled: false,
                onFinish: () => finishes++,
                onTap: () => taps++,
                builder: (BuildContext context, double progress) {
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(HoldToFinish));
    await tester.pumpAndSettle();

    expect(taps, 1, reason: '已完成卡片点一下就应进详情');
    expect(finishes, 0, reason: '禁用时不该有长按完成');
  });

  testWidgets('启用时轻点只触发 onTap，满 3 秒才完成', (WidgetTester tester) async {
    int taps = 0;
    int finishes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 160,
              child: HoldToFinish(
                enabled: true,
                duration: const Duration(seconds: 3),
                onFinish: () => finishes++,
                onTap: () => taps++,
                builder: (BuildContext context, double progress) {
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(HoldToFinish));
    await tester.pump(const Duration(seconds: 4));
    expect(taps, 1, reason: '轻点应进详情');
    expect(finishes, 0, reason: '轻点不应标记完成');

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldToFinish)),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    expect(finishes, 0, reason: '不到 3 秒不应该完成');
    // 计时从第一帧开始，pump 推进后要补足 3 秒
    await tester.pump(const Duration(milliseconds: 3200));
    expect(finishes, 1, reason: '满 3 秒应标记完成');
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
