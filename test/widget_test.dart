import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_todo/main.dart';
import 'package:masonry_todo/models/entry.dart';
import 'package:masonry_todo/pages/detail_page.dart';
import 'package:masonry_todo/store/entry_storage.dart';
import 'package:masonry_todo/store/entry_store.dart';
import 'package:masonry_todo/widgets/entry_card.dart';
import 'package:masonry_todo/widgets/entry_row.dart';
import 'package:masonry_todo/widgets/markdown_view.dart';
import 'package:masonry_todo/widgets/store_scope.dart';

Future<EntryStore> pumpApp(
  WidgetTester tester, {
  MemoryEntryStorage? storage,
}) async {
  final EntryStore store = EntryStore(storage ?? MemoryEntryStorage());
  await store.load();
  await tester.pumpWidget(ShijiApp(store: store));
  await tester.pumpAndSettle();
  return store;
}

Future<void> openIdeaTab(WidgetTester tester) async {
  await tester.tap(find.text('灵感'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('空首页给出两个标签与新建入口', (WidgetTester tester) async {
    await pumpApp(tester);
    expect(find.text('拾记'), findsOneWidget);
    expect(find.text('还没有待办'), findsWidgets);
    expect(find.text('新建待办'), findsOneWidget);

    await openIdeaTab(tester);
    expect(find.text('还没有灵感'), findsWidgets);
    expect(find.text('记灵感'), findsOneWidget);
  });

  testWidgets('新建页输入内容后「创建」才可用，点了能建出来', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    await tester.tap(find.text('新建待办'));
    await tester.pumpAndSettle();

    final Finder createButton = find.widgetWithText(TextButton, '创建');
    expect(tester.widget<TextButton>(createButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, '买菜');
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(createButton).onPressed, isNotNull);

    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(store.entries.single.title, '买菜');
    expect(find.text('买菜'), findsOneWidget);
  });

  testWidgets('新建页写了内容直接返回也会保存', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    await tester.tap(find.text('新建待办'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '别忘了带钥匙');
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(store.entries.single.title, '别忘了带钥匙');
    expect(find.text('别忘了带钥匙'), findsOneWidget);
    expect(find.text('已保存到待办'), findsOneWidget);
  });

  testWidgets('新建页什么都没写就返回不会留下空条目', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    await tester.tap(find.text('新建待办'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(store.entries, isEmpty);
  });

  testWidgets('灵感通过标签页新建，且与待办分开显示', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    store.create(title: '买牛奶');
    await tester.pumpAndSettle();
    await openIdeaTab(tester);

    await tester.tap(find.text('记灵感'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '把卡片做成砖墙');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '创建'));
    await tester.pumpAndSettle();

    expect(store.entriesOf(EntryKind.idea).single.title, '把卡片做成砖墙');
    expect(find.text('把卡片做成砖墙'), findsOneWidget);
    expect(find.text('买牛奶'), findsNothing);

    await tester.tap(find.text('待办'));
    await tester.pumpAndSettle();
    expect(find.text('买牛奶'), findsOneWidget);
    expect(find.text('把卡片做成砖墙'), findsNothing);
  });

  testWidgets('创建后卡片显示标题与正文预览', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    store.create(title: '买牛奶', body: '顺路去超市买两盒牛奶。再看看有没有鸡蛋。');
    await tester.pumpAndSettle();

    expect(find.text('买牛奶'), findsOneWidget);
    expect(find.textContaining('顺路去超市买两盒牛奶'), findsOneWidget);
    // 有标题时预览是完整正文
    expect(find.textContaining('再看看有没有鸡蛋'), findsOneWidget);
  });

  testWidgets('没有标题时卡片标题取正文第一句', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    store.create(body: '整理书架。把技术书按主题归类。');
    await tester.pumpAndSettle();

    expect(find.text('整理书架。'), findsWidgets);
    expect(find.text('把技术书按主题归类。'), findsOneWidget);
  });

  testWidgets('卡片把 Markdown 标记转成文字，不显示符号', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    store.create(body: '**加粗** 标题。正文 `代码`。');
    await tester.pumpAndSettle();

    expect(find.text('加粗 标题。'), findsWidgets);
    expect(find.text('正文 代码。'), findsOneWidget);
    expect(find.textContaining('**', findRichText: true), findsNothing);
    expect(find.textContaining('`', findRichText: true), findsNothing);
  });

  testWidgets('详情页正文与楼层按 Markdown 渲染', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    final Entry entry = store.create(
      title: '写周报',
      body: '# 周报\n\n- 完成 A\n- 完成 B\n\n> 引用一句\n\n**重点**：交付',
    );
    store.addNote(entry.id, '补充 `flutter test` 与 ~~作废~~');
    await tester.pumpAndSettle();

    await tester.tap(find.text('写周报'));
    await tester.pumpAndSettle();

    expect(find.textContaining('完成 A', findRichText: true), findsOneWidget);
    expect(find.textContaining('完成 B', findRichText: true), findsOneWidget);
    expect(find.textContaining('引用一句', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('flutter test', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('作废', findRichText: true), findsOneWidget);
    // 标记符号不该出现在页面上了。
    expect(find.textContaining('#', findRichText: true), findsNothing);
    expect(find.textContaining('**', findRichText: true), findsNothing);
    expect(find.textContaining('~~', findRichText: true), findsNothing);
    expect(find.textContaining('`', findRichText: true), findsNothing);
  });

  testWidgets('长按 3 秒把卡片标记完成', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    final Entry entry = store.create(title: '长按完成我');
    store.addNote(entry.id, '做完才发现其实很简单');
    await tester.pumpAndSettle();
    expect(entry.done, isFalse);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('长按完成我')),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    expect(entry.done, isFalse, reason: '不到 3 秒不应该完成');
    // 计时从第一帧开始，pump 推进后要补足 3 秒
    await tester.pump(const Duration(milliseconds: 3200));
    expect(entry.done, isTrue);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.activeCount(), 0);
    // 完成的卡片默认收起来，打开过滤器才看得到完成时间。
    expect(find.textContaining('完成于'), findsNothing);
    await tester.tap(find.byTooltip('显示已完成'));
    await tester.pumpAndSettle();
    expect(find.textContaining('完成于'), findsOneWidget);
  });

  testWidgets('没写感想时长按完成会被拦下并给出提示', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    final Entry entry = store.create(title: '先写感想');
    await tester.pumpAndSettle();

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('先写感想')),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump(const Duration(milliseconds: 3200));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(entry.done, isFalse, reason: '没有楼层不能完成');
    expect(find.text('先写一条感想，再把它完成'), findsOneWidget);

    await tester.tap(find.text('去写'));
    await tester.pumpAndSettle();
    expect(find.text('待办详情'), findsOneWidget);
  });

  testWidgets('灵感卡片长按不会被标记完成', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    final Entry idea = store.create(kind: EntryKind.idea, title: '一个念头');
    await tester.pumpAndSettle();
    await openIdeaTab(tester);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('一个念头')),
    );
    await tester.pump(const Duration(milliseconds: 3200));
    expect(idea.done, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('进出详情页不会误触发完成', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    final Entry entry = store.create(title: '点一下就进详情');
    await tester.pumpAndSettle();

    await tester.tap(find.text('点一下就进详情'));
    await tester.pumpAndSettle();
    expect(find.text('待办详情'), findsOneWidget);

    await tester.pageBack();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(entry.done, isFalse, reason: '轻点只应该进详情，不该标记完成');
    expect(find.text('点一下就进详情'), findsOneWidget);
  });

  testWidgets('松手会取消长按计时', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    final Entry entry = store.create(title: '别完成我');
    await tester.pumpAndSettle();

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('别完成我')),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(entry.done, isFalse);
  });

  testWidgets('点击卡片进入详情，可以逐楼记录想法', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    store.create(title: '写周报', body: '总结这周的三件事');
    await tester.pumpAndSettle();

    await tester.tap(find.text('写周报'));
    await tester.pumpAndSettle();

    expect(find.text('待办详情'), findsOneWidget);
    expect(find.text('还没有记录，写下你对这个任务的记录'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '第三条其实可以下周再做');
    // 发送键随输入内容重建，点之前先让重建落帧
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('发表'));
    await tester.pumpAndSettle();

    expect(find.text('第三条其实可以下周再做'), findsOneWidget);
    expect(store.entries.single.notes.length, 1);
  });

  testWidgets('长按楼层可以改文字，也可以删掉这一层', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    final Entry entry = store.create(title: '写周报');
    store.addNote(entry.id, '原来那句');
    await tester.pumpAndSettle();

    await tester.tap(find.text('写周报'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('原来那句'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑这一层'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '改好了');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('改好了'), findsOneWidget);
    expect(entry.notes.single.text, '改好了');

    await tester.longPress(find.text('改好了'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除这一层'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();
    expect(entry.notes, isEmpty);
    expect(store.entries.single.notes, isEmpty);
  });

  testWidgets('评论楼层过长时按整行折叠，点「查看详情」展开', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    final Entry entry = store.create(title: '长评论');
    final String longText = '这是一条很长的评论。' * 60;
    store.addNote(entry.id, longText);
    await tester.pumpAndSettle();

    await tester.tap(find.text('长评论'));
    await tester.pumpAndSettle();

    expect(find.text('查看详情'), findsOneWidget);
    expect(find.text('收起'), findsNothing);

    // 折叠靠外层裁切实现：Markdown 内容本身按完整高度排版，被裁到阈值以内。
    double clippedHeight() {
      final Finder clips = find.ancestor(
        of: find.byType(MarkdownView),
        matching: find.byType(ClipRect),
      );
      return clips
          .evaluate()
          .map(
            (Element element) =>
                tester.getSize(find.byWidget(element.widget)).height,
          )
          .reduce(min);
    }

    expect(find.byType(MarkdownView), findsOneWidget);
    expect(clippedHeight(), lessThanOrEqualTo(120));
    // 折叠后仍然占满大半预算，不是把内容全裁没了。
    expect(clippedHeight(), greaterThan(90));

    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();
    expect(find.text('收起'), findsOneWidget);
    expect(find.text('查看详情'), findsNothing);
    expect(tester.getSize(find.byType(MarkdownView)).height, greaterThan(120));

    await tester.tap(find.text('收起'));
    await tester.pumpAndSettle();
    expect(find.text('查看详情'), findsOneWidget);
    expect(clippedHeight(), lessThanOrEqualTo(120));
  });

  testWidgets('短评论与主楼都不给折叠开关', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    final Entry entry = store.create(
      title: '主楼再长也不折叠',
      body: '这是一段很长的正文。' * 60,
    );
    store.addNote(entry.id, '两行就够。');
    await tester.pumpAndSettle();

    await tester.tap(find.text('主楼再长也不折叠'));
    await tester.pumpAndSettle();

    expect(find.text('查看详情'), findsNothing);
    expect(find.text('收起'), findsNothing);
  });

  testWidgets('详情页可以编辑标题，返回首页后生效', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    final Entry entry = store.create(title: '旧标题');
    await tester.pumpAndSettle();

    await tester.tap(find.text('旧标题'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑待办'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '新标题');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    expect(store.byId(entry.id)!.title, '新标题');
    expect(find.text('新标题'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('新标题'), findsOneWidget);
  });

  testWidgets('编辑页直接返回也会保存改动', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    final Entry entry = store.create(title: '改一半');
    await tester.pumpAndSettle();

    await tester.tap(find.text('改一半'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '改好了');
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(store.byId(entry.id)!.title, '改好了');
    expect(find.text('已保存到待办'), findsOneWidget);
  });

  testWidgets('灵感详情显示灵感状态，没有完成操作', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    store.create(kind: EntryKind.idea, title: '一个念头');
    await tester.pumpAndSettle();
    await openIdeaTab(tester);

    await tester.tap(find.text('一个念头'));
    await tester.pumpAndSettle();
    expect(find.text('灵感详情'), findsOneWidget);
    expect(find.text('灵感'), findsOneWidget);
    expect(find.text('已完成'), findsNothing);

    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑灵感'), findsOneWidget);
  });

  testWidgets('窄屏下详情页的时间行不溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final EntryStore store = EntryStore(MemoryEntryStorage());
    await store.load();
    final Entry entry = store.create(title: 'test', body: '特');
    store.addNote(entry.id, '一条感想');
    store.setDone(entry.id, true);

    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(home: DetailPage(entryId: entry.id)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('列表模式点方框完成，再点取消完成', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    final Entry entry = store.create(title: '列表里完成我');
    store.addNote(entry.id, '记一下');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('列表'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('列表里完成我'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('标记为已完成'));
    await tester.pumpAndSettle();
    expect(entry.done, isTrue);
    expect(find.text('列表里完成我'), findsNothing, reason: '完成的行默认收起来');

    await tester.tap(find.byTooltip('显示已完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('标记为未完成'));
    await tester.pumpAndSettle();
    expect(entry.done, isFalse);

    await tester.tap(find.byTooltip('隐藏已完成'));
    await tester.pumpAndSettle();
    expect(find.text('列表里完成我'), findsOneWidget);
  });

  testWidgets('过滤器默认收起已完成，全部做完时给出展开入口', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    final Entry entry = store.create(title: '唯一一项');
    store.addNote(entry.id, '记一下');
    await tester.pumpAndSettle();
    expect(store.showCompleted, isFalse, reason: '默认隐藏已完成');

    store.setDone(entry.id, true);
    await tester.pumpAndSettle();
    expect(find.text('唯一一项'), findsNothing);
    expect(find.text('未完成的都做完了'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '显示已完成'));
    await tester.pumpAndSettle();
    expect(store.showCompleted, isTrue);
    expect(find.text('唯一一项'), findsOneWidget);
  });

  testWidgets('列表拖动排序改变优先级，卡片形态按同一顺序摆放', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    store.create(title: '先建的第一项', now: DateTime(2026, 10, 1));
    store.create(title: '后建的第二项', now: DateTime(2026, 10, 2));
    store.create(title: '最后建的第三项', now: DateTime(2026, 10, 3));
    await tester.pumpAndSettle();
    expect(
      store.visibleEntries.map((Entry entry) => entry.title).toList(),
      <String>['最后建的第三项', '后建的第二项', '先建的第一项'],
      reason: '新建的排在最前面',
    );

    await tester.tap(find.byTooltip('列表'));
    await tester.pumpAndSettle();

    // 第一行按住往下拖过第二行：拖动落点就是新的优先级。
    final Rect first = tester.getRect(find.text('最后建的第三项'));
    final Rect second = tester.getRect(find.text('后建的第二项'));
    final TestGesture gesture = await tester.startGesture(first.center);
    await tester.pump(const Duration(milliseconds: 600));
    for (int i = 1; i <= 6; i++) {
      await gesture.moveTo(
        Offset(
          first.center.dx,
          first.center.dy + (second.center.dy - first.center.dy) * i / 6,
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      store.visibleEntries.map((Entry entry) => entry.title).toList(),
      <String>['后建的第二项', '最后建的第三项', '先建的第一项'],
      reason: '拖过第二行，让出了第一优先级',
    );

    // 卡片形态按同一顺序摆：行优先，先左后右，再下一行。
    await tester.tap(find.byTooltip('卡片'));
    await tester.pumpAndSettle();
    final List<Offset> cards = <Offset>[
      for (final Entry entry in store.visibleEntries)
        tester.getCenter(find.widgetWithText(EntryCard, entry.title)),
    ];
    expect(cards, hasLength(3));
    expect(cards[0].dx, lessThan(cards[1].dx), reason: '第一个在左列，第二个在右列');
    expect(cards[2].dx, moreOrLessEquals(cards[0].dx), reason: '第三个回到左列');
    expect(cards[0].dy, lessThan(cards[2].dy), reason: '第三个在下一行');
  });

  testWidgets('列表里误点完成可以撤销', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    final Entry entry = store.create(title: '误点就撤销');
    store.addNote(entry.id, '记一下');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('列表'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('标记为已完成'));
    await tester.pumpAndSettle();
    expect(entry.done, isTrue);
    expect(find.text('撤销'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(entry.done, isFalse);
  });

  testWidgets('撤销条幅到时会自己消失，不会赖在屏幕上', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    store.create(title: '完成就该收条幅');
    store.addNote(store.entries.single.id, '记一下');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('列表'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('标记为已完成'));
    await tester.pumpAndSettle();
    expect(find.text('撤销'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('撤销'), findsNothing);
  });

  testWidgets('删除只能从详情页走，且需要确认', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    store.create(title: '待删除的条目');
    await tester.pumpAndSettle();

    await tester.tap(find.text('待删除的条目'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除这条待办？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(store.entries.length, 1);

    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();

    expect(store.entries, isEmpty);
    expect(find.text('还没有待办'), findsWidgets);
  });

  testWidgets('待办与灵感各记一套卡片／列表设置', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    store.create(title: '一件待办');
    store.create(kind: EntryKind.idea, title: '一个念头');
    await tester.pumpAndSettle();
    expect(find.byType(EntryCard), findsOneWidget);

    await tester.tap(find.byTooltip('列表'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryRow), findsOneWidget);

    await openIdeaTab(tester);
    expect(find.byType(EntryCard), findsOneWidget, reason: '待办切成列表不该带走灵感页的卡片');

    await tester.tap(find.byTooltip('列表'));
    await tester.pumpAndSettle();
    expect(find.byType(EntryRow), findsOneWidget);

    await tester.tap(find.text('待办'));
    await tester.pumpAndSettle();
    expect(store.viewModeOf(EntryKind.todo), ViewMode.list);
    expect(store.viewModeOf(EntryKind.idea), ViewMode.list);
    expect(find.byType(EntryRow), findsOneWidget);
  });

  testWidgets('左右滑动切换待办与灵感', (WidgetTester tester) async {
    final EntryStore store = await pumpApp(tester);
    store.create(title: '买牛奶');
    store.create(kind: EntryKind.idea, title: '一个念头');
    await tester.pumpAndSettle();
    expect(find.text('买牛奶'), findsOneWidget);

    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(store.kind, EntryKind.idea);
    expect(find.text('一个念头'), findsOneWidget);
    expect(find.text('买牛奶'), findsNothing);

    await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    expect(store.kind, EntryKind.todo);
    expect(find.text('买牛奶'), findsOneWidget);
    expect(find.text('一个念头'), findsNothing);
  });

  testWidgets('首页备份菜单里有导出与导入', (WidgetTester tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('备份'));
    await tester.pumpAndSettle();

    expect(find.text('导出备份'), findsOneWidget);
    expect(find.text('导入备份'), findsOneWidget);
  });

  testWidgets('窄屏下首页标题与备份入口不溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpApp(tester);
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('备份'), findsOneWidget);
  });
}
