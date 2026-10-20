import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_todo/markdown/inline_markdown.dart';
import 'package:masonry_todo/models/entry.dart';
import 'package:masonry_todo/models/entry_text.dart';

void main() {
  group('markdownPlainText', () {
    test('去掉行内标记，只留文字', () {
      expect(markdownPlainText('**粗体** 与 *斜体*'), '粗体 与 斜体');
      expect(markdownPlainText('用 `flutter test` 跑测试'), '用 flutter test 跑测试');
      expect(markdownPlainText('~~作废~~ 保留'), '作废 保留');
      expect(markdownPlainText('看 [文档](https://example.com) 再说'), '看 文档 再说');
    });

    test('去掉块级标记，块与块之间保留换行', () {
      expect(markdownPlainText('# 标题'), '标题');
      expect(markdownPlainText('- 买菜\n- 洗衣服'), '买菜\n洗衣服');
      expect(markdownPlainText('> 引用一句'), '引用一句');
      expect(markdownPlainText('```\nfinal a = 1;\n```'), 'final a = 1;');
      expect(
        markdownPlainText('写文档。\n\n1. 跑测试\n2. 打 tag'),
        '写文档。\n跑测试\n打 tag',
      );
    });

    test('普通文本原样返回', () {
      expect(markdownPlainText('去超市。买两盒。'), '去超市。买两盒。');
      expect(markdownPlainText('  '), '');
    });
  });

  group('markdownRuns', () {
    Set<String> tagsOf(List<MarkdownRun> runs, String text) => runs
        .firstWhere((MarkdownRun run) => run.text == text)
        .tags;

    test('每段文字带上自己的语义标记', () {
      final List<MarkdownRun> runs = markdownRuns(
        '**粗** *斜* `码` ~~删~~ [链](https://example.com)',
      );
      expect(tagsOf(runs, '粗'), contains(MarkdownTag.strong));
      expect(tagsOf(runs, '斜'), contains(MarkdownTag.em));
      expect(tagsOf(runs, '码'), contains(MarkdownTag.code));
      expect(tagsOf(runs, '删'), contains(MarkdownTag.del));
      expect(tagsOf(runs, '链'), contains(MarkdownTag.link));
    });

    test('嵌套标记叠加', () {
      final List<MarkdownRun> runs = markdownRuns('**粗 *斜* 粗**');
      expect(tagsOf(runs, '斜'), containsAll(<String>[
        MarkdownTag.strong,
        MarkdownTag.em,
      ]));
    });
  });

  group('sliceRuns', () {
    test('跳过开头若干字符后接着渲染，样式跟着走', () {
      final List<MarkdownRun> runs = markdownRuns('**去超市。** 买两盒。');
      final List<MarkdownRun> tail = sliceRuns(runs, 4);
      expect(runsText(tail), '买两盒。');
      expect(tail.single.tags, isEmpty);
    });

    test('只取前若干字符', () {
      final List<MarkdownRun> runs = markdownRuns('去买牛奶和面包');
      expect(runsText(sliceRuns(runs, 0, take: 4)), '去买牛奶');
    });

    test('越界时给空结果，两端空白清掉', () {
      expect(sliceRuns(markdownRuns('短'), 99), isEmpty);
      expect(runsText(sliceRuns(markdownRuns(' 留白 '), 0)), '留白');
    });
  });

  group('卡片标题与预览', () {
    Entry entryWith({String title = '', String body = ''}) => Entry(
      id: 'x',
      title: title,
      body: body,
      createdAt: DateTime(2026, 10, 18, 9, 32),
    );

    test('标题里的标记不进标题文本', () {
      final Entry entry = entryWith(title: '**买牛奶**', body: '去超市。');
      expect(displayTitle(entry), '买牛奶');
    });

    test('标题取自正文第一句时带标记，预览跳过这一句', () {
      final Entry entry = entryWith(body: '**去超市。** 买两盒 `牛奶`。');
      expect(displayTitle(entry), '去超市。');
      expect(previewSlice(entry).skip, 4);
      final List<MarkdownRun> preview = sliceRuns(
        markdownRuns(entry.body),
        previewSlice(entry).skip,
      );
      expect(runsText(preview), '买两盒 牛奶。');
    });

    test('有标题时预览就是整段正文', () {
      final Entry entry = entryWith(title: '买牛奶', body: '去超市。买两盒。');
      expect(previewSlice(entry), (visible: true, skip: 0));
    });

    test('正文只有一句时没有预览可显示', () {
      final Entry entry = entryWith(body: '去超市。');
      expect(previewSlice(entry).visible, isFalse);
    });
  });
}
