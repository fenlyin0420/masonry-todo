import 'package:markdown/markdown.dart' as md;

/// 行内片段：一段纯文本，以及它命中的语义标记。
/// 标记只表达“是什么”，具体样式由渲染层结合主题决定。
class MarkdownRun {
  const MarkdownRun(this.text, [this.tags = const <String>{}]);

  final String text;

  /// 命中的标记，取自 [MarkdownTag]：strong / em / code / del / link。
  final Set<String> tags;

  @override
  String toString() => 'MarkdownRun(${text.replaceAll('\n', r'\n')}, $tags)';
}

/// 渲染层认识的标记名。
abstract final class MarkdownTag {
  static const String strong = 'strong';
  static const String em = 'em';
  static const String code = 'code';
  static const String del = 'del';
  static const String link = 'link';
}

final md.Document _document = md.Document(
  extensionSet: md.ExtensionSet.gitHubFlavored,
  encodeHtml: false,
);

/// 卡片、列表这类只能塞几行的地方用：[source] 里的块级结构（标题、列表、引用、
/// 代码块）被压平成同一层文本，块与块之间换行，列表符号直接丢掉。
List<MarkdownRun> markdownRuns(String source) {
  if (source.trim().isEmpty) return const <MarkdownRun>[];
  final _RunCollector collector = _RunCollector();
  for (final md.Node node in _document.parseLines(source.split('\n'))) {
    collector.walkBlock(node);
  }
  return collector.finish();
}

/// 去掉标记后的纯文本，用于标题、占位判断、高度估算。
String markdownPlainText(String source) => runsText(markdownRuns(source));

/// 把所有片段拼回纯文本。
String runsText(List<MarkdownRun> runs) =>
    runs.map((MarkdownRun run) => run.text).join();

/// 丢掉开头 [skip] 个字符、最多保留 [take] 个字符，并清掉两端空白。
/// 卡片标题取自正文第一句时，预览需要从句子之后接着渲染，样式才不会串位。
List<MarkdownRun> sliceRuns(
  List<MarkdownRun> runs,
  int skip, {
  int? take,
}) {
  if (skip <= 0 && take == null) return runs;
  final List<MarkdownRun> kept = <MarkdownRun>[];
  int consumed = 0;
  int taken = 0;
  for (final MarkdownRun run in runs) {
    final String text = run.text;
    int start = 0;
    if (consumed < skip) {
      if (consumed + text.length <= skip) {
        consumed += text.length;
        continue;
      }
      start = skip - consumed;
      consumed = skip;
    }
    int end = text.length;
    if (take != null) {
      final int room = take - taken;
      if (room <= 0) break;
      end = start + room;
      if (end > text.length) end = text.length;
      taken += end - start;
    }
    if (end > start) {
      kept.add(MarkdownRun(text.substring(start, end), run.tags));
    }
  }
  return _trimRuns(kept);
}

List<MarkdownRun> _trimRuns(List<MarkdownRun> runs) {
  int first = 0;
  int last = runs.length - 1;
  while (first <= last && runs[first].text.trim().isEmpty) {
    first++;
  }
  while (last >= first && runs[last].text.trim().isEmpty) {
    last--;
  }
  final List<MarkdownRun> trimmed = <MarkdownRun>[];
  for (int i = first; i <= last; i++) {
    String text = runs[i].text;
    if (i == first) text = text.trimLeft();
    if (i == last) text = text.trimRight();
    if (text.isEmpty) continue;
    trimmed.add(MarkdownRun(text, runs[i].tags));
  }
  return trimmed;
}

/// 段落、标题、列表这些块级标签：在预览里只是分隔，不作结构渲染。
const Set<String> _blockTags = <String>{
  'p',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'ul',
  'ol',
  'li',
  'blockquote',
  'pre',
  'table',
  'thead',
  'tbody',
  'tr',
};

class _RunCollector {
  final List<MarkdownRun> _runs = <MarkdownRun>[];

  void _emit(String text, Set<String> tags) {
    if (text.isEmpty) return;
    _runs.add(MarkdownRun(text, tags));
  }

  /// 块与块之间换行：预览里保留原来的分行，但不带列表符号。
  void _gap() {
    if (_runs.isEmpty) return;
    if (_runs.last.text.endsWith('\n')) return;
    _emit('\n', const <String>{});
  }

  void walkBlock(md.Node node) {
    if (node is md.Text) {
      _emit(node.text, const <String>{});
      return;
    }
    if (node is! md.Element) return;
    if (_blockTags.contains(node.tag)) {
      _walkChildren(node, const <String>{});
      _gap();
      return;
    }
    walkInline(node, const <String>{});
    _gap();
  }

  void walkInline(md.Element node, Set<String> tags) {
    final Set<String> next = _tagsOf(node.tag, tags);
    _walkInlineChildren(node, next);
  }

  void _walkInlineChildren(md.Element node, Set<String> tags) {
    final List<md.Node>? children = node.children;
    if (children == null || children.isEmpty) {
      _emit(node.textContent, tags);
      return;
    }
    for (final md.Node child in children) {
      if (child is md.Text) {
        _emit(child.text, tags);
      } else if (child is md.Element) {
        switch (child.tag) {
          case 'br':
            _emit('\n', tags);
          case 'img':
            _emit(child.attributes['alt'] ?? '', tags);
          default:
            _walkInlineChildren(child, _tagsOf(child.tag, tags));
        }
      }
    }
  }

  void _walkChildren(md.Element node, Set<String> tags) {
    final List<md.Node>? children = node.children;
    if (children == null || children.isEmpty) {
      _emit(node.textContent, tags);
      return;
    }
    for (final md.Node child in children) {
      if (child is md.Text) {
        _emit(child.text, tags);
      } else if (child is md.Element) {
        if (child.tag == 'br') {
          _gap();
        } else if (_blockTags.contains(child.tag)) {
          _walkChildren(child, tags);
          _gap();
        } else {
          _walkInlineChildren(child, _tagsOf(child.tag, tags));
        }
      }
    }
  }

  Set<String> _tagsOf(String tag, Set<String> current) {
    final String? mark = switch (tag) {
      'strong' || 'b' => MarkdownTag.strong,
      'em' || 'i' => MarkdownTag.em,
      'code' => MarkdownTag.code,
      'del' || 's' => MarkdownTag.del,
      'a' => MarkdownTag.link,
      _ => null,
    };
    if (mark == null || current.contains(mark)) return current;
    return <String>{...current, mark};
  }

  /// 收尾：干掉纯空白片段，行内连续空格压成一个；换行保留，卡片预览与折叠高度都靠它。
  List<MarkdownRun> finish() {
    final List<MarkdownRun> result = <MarkdownRun>[];
    for (final MarkdownRun run in _runs) {
      final String text = run.text.replaceAll(RegExp(r'[ \t]+'), ' ');
      if (text.trim().isEmpty && (result.isEmpty || result.last.text.endsWith(' '))) {
        continue;
      }
      result.add(MarkdownRun(text, run.tags));
    }
    return _trimRuns(result);
  }
}
