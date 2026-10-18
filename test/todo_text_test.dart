import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_todo/models/todo.dart';
import 'package:masonry_todo/models/todo_text.dart';

void main() {
  Todo todoWith({String title = '', String body = ''}) => Todo(
    id: 'x',
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
      final Todo todo = todoWith(title: '买牛奶', body: '去超市。买两盒。');
      expect(displayTitle(todo), '买牛奶');
      expect(bodyPreview(todo), '去超市。买两盒。');
    });

    test('无标题时标题取第一句，预览从第二句起', () {
      final Todo todo = todoWith(body: '去超市。买两盒。');
      expect(displayTitle(todo), '去超市。');
      expect(bodyPreview(todo), '买两盒。');
    });

    test('标题正文都空时有占位标题、空预览', () {
      final Todo todo = todoWith();
      expect(displayTitle(todo), '未命名');
      expect(bodyPreview(todo), '');
    });
  });

  test('formatMinute 精确到分并补零', () {
    expect(formatMinute(DateTime(2026, 1, 2, 3, 4)), '2026-01-02 03:04');
  });
}
