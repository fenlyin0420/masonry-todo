import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_todo/main.dart';
import 'package:masonry_todo/models/todo.dart';
import 'package:masonry_todo/store/todo_storage.dart';
import 'package:masonry_todo/store/todo_store.dart';

Future<TodoStore> pumpApp(
  WidgetTester tester, {
  MemoryTodoStorage? storage,
}) async {
  final TodoStore store = TodoStore(storage ?? MemoryTodoStorage());
  await store.load();
  await tester.pumpWidget(MasonryTodoApp(store: store));
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('空首页给出新建入口', (WidgetTester tester) async {
    await pumpApp(tester);
    expect(find.text('还没有 Todo'), findsOneWidget);
    expect(find.text('新建'), findsOneWidget);
  });

  testWidgets('新建页输入内容后「创建」才可用，点了能建出来', (WidgetTester tester) async {
    final TodoStore store = await pumpApp(tester);
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();

    final Finder createButton = find.widgetWithText(TextButton, '创建');
    expect(tester.widget<TextButton>(createButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, '买菜');
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(createButton).onPressed, isNotNull);

    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(store.todos.single.title, '买菜');
    expect(find.text('买菜'), findsOneWidget);
  });

  testWidgets('创建后卡片显示标题与正文预览', (WidgetTester tester) async {
    final TodoStore store = await pumpApp(tester);
    store.create(title: '买牛奶', body: '顺路去超市买两盒牛奶。再看看有没有鸡蛋。');
    await tester.pumpAndSettle();

    expect(find.text('买牛奶'), findsOneWidget);
    expect(find.textContaining('顺路去超市买两盒牛奶'), findsOneWidget);
    // 有标题时预览是完整正文
    expect(find.textContaining('再看看有没有鸡蛋'), findsOneWidget);
  });

  testWidgets('没有标题时卡片标题取正文第一句', (WidgetTester tester) async {
    final TodoStore store = await pumpApp(tester);
    store.create(body: '整理书架。把技术书按主题归类。');
    await tester.pumpAndSettle();

    expect(find.text('整理书架。'), findsWidgets);
    expect(find.text('把技术书按主题归类。'), findsOneWidget);
  });

  testWidgets('长按 3 秒把卡片标记完成', (WidgetTester tester) async {
    final TodoStore store = await pumpApp(tester);
    final todo = store.create(title: '长按完成我');
    await tester.pumpAndSettle();
    expect(todo.done, isFalse);

    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(find.text('长按完成我')));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(todo.done, isFalse, reason: '不到 3 秒不应该完成');
    // 计时从第一帧开始，pump 推进后要补足 3 秒
    await tester.pump(const Duration(milliseconds: 3200));
    expect(todo.done, isTrue);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.activeCount, 0);
  });

  testWidgets('进出详情页不会误触发完成', (WidgetTester tester) async {
    final TodoStore store = await pumpApp(tester);
    final todo = store.create(title: '点一下就进详情');
    await tester.pumpAndSettle();

    await tester.tap(find.text('点一下就进详情'));
    await tester.pumpAndSettle();
    expect(find.text('详情'), findsOneWidget);

    await tester.pageBack();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(todo.done, isFalse, reason: '轻点只应该进详情，不该标记完成');
    expect(find.text('点一下就进详情'), findsOneWidget);
  });

  testWidgets('松手会取消长按计时', (WidgetTester tester) async {
    final TodoStore store = await pumpApp(tester);
    final todo = store.create(title: '别完成我');
    await tester.pumpAndSettle();

    final TestGesture gesture =
        await tester.startGesture(tester.getCenter(find.text('别完成我')));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(todo.done, isFalse);
  });

  testWidgets('点击卡片进入详情，可以逐楼记录想法', (WidgetTester tester) async {
    final TodoStore store = await pumpApp(tester);
    store.create(title: '写周报', body: '总结这周的三件事');
    await tester.pumpAndSettle();

    await tester.tap(find.text('写周报'));
    await tester.pumpAndSettle();

    expect(find.text('详情'), findsOneWidget);
    expect(find.text('还没有记录，写下你对这个任务的想法'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '第三条其实可以下周再做');
    await tester.tap(find.byTooltip('发表'));
    await tester.pumpAndSettle();

    expect(find.text('第三条其实可以下周再做'), findsOneWidget);
    expect(store.todos.single.notes.length, 1);
  });

  testWidgets('列表模式点方框完成，再点取消完成', (WidgetTester tester) async {
    final TodoStore store = await pumpApp(tester);
    final todo = store.create(title: '列表里完成我');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('列表'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('列表里完成我'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('标记为已完成'));
    await tester.pumpAndSettle();
    expect(todo.done, isTrue);

    await tester.tap(find.bySemanticsLabel('标记为未完成'));
    await tester.pumpAndSettle();
    expect(todo.done, isFalse);
  });

  testWidgets('列表里误点完成可以撤销', (WidgetTester tester) async {
    final TodoStore store = await pumpApp(tester);
    final Todo todo = store.create(title: '误点就撤销');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('列表'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('标记为已完成'));
    await tester.pumpAndSettle();
    expect(todo.done, isTrue);
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(todo.done, isFalse);
  });

  testWidgets('删除只能从详情页走，且需要确认', (WidgetTester tester) async {
    final TodoStore store = await pumpApp(tester);
    store.create(title: '待删除的条目');
    await tester.pumpAndSettle();

    await tester.tap(find.text('待删除的条目'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除这条 Todo？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(store.todos.length, 1);

    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();

    expect(store.todos, isEmpty);
    expect(find.text('还没有 Todo'), findsOneWidget);
  });
}
