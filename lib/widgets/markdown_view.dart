import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../markdown/inline_markdown.dart';

/// 卡片、列表行里的行内 Markdown：只认粗体、斜体、行内代码、删除线、链接。
/// 块级结构已经在 [markdownRuns] 里压平，所以能直接塞进限行数的 [Text]。
class MarkdownText extends StatelessWidget {
  const MarkdownText(
    this.source, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
    this.skipChars = 0,
    this.takeChars,
    this.textAlign,
  });

  final String source;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;

  /// 从纯文本的第几个字符开始渲染（标题已经取走正文第一句时用）。
  final int skipChars;

  /// 最多渲染多少个字符，null 表示一直到底。
  final int? takeChars;

  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final List<MarkdownRun> runs = sliceRuns(
      markdownRuns(source),
      skipChars,
      take: takeChars,
    );
    if (runs.isEmpty) return const SizedBox.shrink();
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          for (final MarkdownRun run in runs)
            TextSpan(text: run.text, style: _runStyle(context, run.tags)),
        ],
      ),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }

  /// 标记只表达语义，具体样式这里结合主题补上，行距与颜色跟随外层 [style]。
  static TextStyle? _runStyle(BuildContext context, Set<String> tags) {
    if (tags.isEmpty) return null;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    TextStyle style = const TextStyle();
    if (tags.contains(MarkdownTag.strong)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.w700));
    }
    if (tags.contains(MarkdownTag.em)) {
      style = style.merge(const TextStyle(fontStyle: FontStyle.italic));
    }
    if (tags.contains(MarkdownTag.del)) {
      style = style.merge(
        const TextStyle(decoration: TextDecoration.lineThrough),
      );
    }
    if (tags.contains(MarkdownTag.code)) {
      style = style.merge(
        TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: const <String>['Menlo', 'Courier New'],
          backgroundColor: scheme.surfaceContainerHighest,
        ),
      );
    }
    if (tags.contains(MarkdownTag.link)) {
      style = style.merge(
        TextStyle(
          color: scheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: scheme.primary.withValues(alpha: 0.5),
        ),
      );
    }
    return style;
  }
}

/// 详情页里的块级 Markdown：段落、标题、列表、引用、代码块、分割线都保留结构。
class MarkdownView extends StatelessWidget {
  const MarkdownView(this.data, {super.key, this.style});

  final String data;

  /// 正文字体，来自外层主题；行距等排版也由这里定。
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: data,
      shrinkWrap: true,
      styleSheet: markdownStyleSheet(context, body: style),
    );
  }
}

/// 按 App 主题拼一份 Markdown 样式表：正文行高与原来手写 Text 时一致，
/// 代码块、引用、分割线只借用主题色，不额外引入配色。
MarkdownStyleSheet markdownStyleSheet(
  BuildContext context, {
  TextStyle? body,
}) {
  final ThemeData theme = Theme.of(context);
  final ColorScheme scheme = theme.colorScheme;
  final TextStyle? base = (body ?? theme.textTheme.bodyMedium)?.copyWith(
    height: 1.6,
  );
  TextStyle? heading(TextStyle? source) => source?.copyWith(
    fontWeight: FontWeight.w700,
    height: 1.35,
    color: scheme.onSurface,
  );

  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: base,
    a: base?.copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary.withValues(alpha: 0.5),
    ),
    em: const TextStyle(fontStyle: FontStyle.italic),
    strong: const TextStyle(fontWeight: FontWeight.w700),
    del: TextStyle(
      decoration: TextDecoration.lineThrough,
      decorationColor: scheme.onSurfaceVariant,
    ),
    code: TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const <String>['Menlo', 'Courier New'],
      backgroundColor: scheme.surfaceContainerHighest,
      color: scheme.onSurface,
    ),
    h1: heading(theme.textTheme.titleLarge),
    h2: heading(theme.textTheme.titleMedium),
    h3: heading(theme.textTheme.titleSmall),
    h4: heading(theme.textTheme.titleSmall),
    h5: heading(theme.textTheme.bodyLarge),
    h6: heading(theme.textTheme.bodyMedium),
    h1Padding: const EdgeInsets.only(top: 6, bottom: 2),
    h2Padding: const EdgeInsets.only(top: 6, bottom: 2),
    h3Padding: const EdgeInsets.only(top: 4, bottom: 2),
    h4Padding: const EdgeInsets.only(top: 4, bottom: 2),
    h5Padding: const EdgeInsets.only(top: 4, bottom: 2),
    h6Padding: const EdgeInsets.only(top: 4, bottom: 2),
    blockSpacing: 8,
    listIndent: 20,
    listBullet: base,
    listBulletPadding: const EdgeInsets.only(right: 6),
    blockquote: base?.copyWith(color: scheme.onSurfaceVariant),
    blockquotePadding: const EdgeInsets.fromLTRB(10, 2, 8, 2),
    blockquoteDecoration: BoxDecoration(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(8),
      border: Border(
        left: BorderSide(
          color: scheme.primary.withValues(alpha: 0.5),
          width: 3,
        ),
      ),
    ),
    codeblockPadding: const EdgeInsets.all(10),
    codeblockDecoration: BoxDecoration(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: scheme.outlineVariant)),
    ),
    tableBorder: TableBorder.all(color: scheme.outlineVariant),
    tableHead: base?.copyWith(fontWeight: FontWeight.w600),
    tableBody: base,
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
  );
}
