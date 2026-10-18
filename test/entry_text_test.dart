import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_todo/models/entry.dart';
import 'package:masonry_todo/models/entry_text.dart';

void main() {
  Entry entryWith({
    String title = '',
    String body = '',
    EntryKind kind = EntryKind.todo,
  }) => Entry(
    id: 'x',
    kind: kind,
    title: title,
    body: body,
    createdAt: DateTime(2026, 10, 18, 9, 32),
  );

  group('firstSentence', () {
    test('取到第一个句末标点', () {
      expect(firstSentence('整理书架。把技术书归类。'), '整理书架。');
      expect(firstSentence('先看文档！再动手。'), '先看文档！');
      expect(firstSentence('第一行\n第二行'), '第一行');
    });

    test('没有句末标点时整段作为一句', () {
      expect(firstSentence('  洗澡  '), '洗澡');
    });

    test('过长且无标点时截断并加省略号', () {
      final String long = 'a' * 60;
      final String sentence = firstSentence(long);
      expect(sentence.endsWith('…'), isTrue);
      expect(sentence.length, 33);
    });

    test('空正文返回空串', () {
      expect(firstSentence('   '), '');
    });
  });

  group('displayTitle / bodyPreview', () {
    test('有标题时用标题，预览是完整正文', () {
      final Entry entry = entryWith(title: '买牛奶', body: '去超市。买两盒。');
      expect(displayTitle(entry), '买牛奶');
      expect(bodyPreview(entry), '去超市。买两盒。');
    });

    test('无标题时标题取第一句，预览从第二句起', () {
      final Entry entry = entryWith(body: '去超市。买两盒。');
      expect(displayTitle(entry), '去超市。');
      expect(bodyPreview(entry), '买两盒。');
    });

    test('待办标题正文都空时给待办占位标题', () {
      final Entry entry = entryWith();
      expect(displayTitle(entry), '未命名待办');
      expect(bodyPreview(entry), '');
    });

    test('灵感标题正文都空时给灵感占位标题', () {
      final Entry entry = entryWith(kind: EntryKind.idea);
      expect(displayTitle(entry), '未命名灵感');
    });
  });

  test('formatMinute 精确到分并补零', () {
    expect(formatMinute(DateTime(2026, 1, 2, 3, 4)), '2026-01-02 03:04');
  });

  group('formatCardTime', () {
    test('同年省掉年份', () {
      expect(
        formatCardTime(DateTime(2026, 10, 18, 9, 32), now: DateTime(2026, 12, 1)),
        '10-18 09:32',
      );
    });

    test('跨年保留年份', () {
      expect(
        formatCardTime(DateTime(2025, 10, 18, 9, 32), now: DateTime(2026, 12, 1)),
        '2025-10-18 09:32',
      );
    });
  });
}
