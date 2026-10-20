import '../markdown/inline_markdown.dart';
import 'entry.dart';

const List<String> _sentenceEnders = <String>[
  '。',
  '！',
  '？',
  '；',
  '!',
  '?',
  ';',
  '.',
  '\n',
];

/// 取正文的第一句（含结尾标点）。没有句末标点时整段作为一句，过长则截断。
String firstSentence(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return '';

  var cut = trimmed.length;
  for (final ender in _sentenceEnders) {
    final index = trimmed.indexOf(ender);
    if (index >= 0 && index < cut) cut = index;
  }
  if (cut < trimmed.length) {
    return trimmed.substring(0, cut + 1).trim();
  }
  if (trimmed.length <= 32) return trimmed;
  return '${trimmed.substring(0, 32)}…';
}

/// 卡片标题：有标题用标题，没有标题取正文第一句，都为空时给个占位。
/// Markdown 标记在这里去掉，标题按纯文本显示。
String displayTitle(Entry entry) {
  final title = markdownPlainText(entry.title).trim();
  if (title.isNotEmpty) return title;
  final sentence = firstSentence(markdownPlainText(entry.body));
  if (sentence.isNotEmpty) return sentence;
  return entry.isTodo ? '未命名待办' : '未命名灵感';
}

/// 卡片正文预览的纯文本：若标题取自正文第一句，预览就从第二句开始，避免重复。
String bodyPreview(Entry entry) {
  final body = markdownPlainText(entry.body).trim();
  if (body.isEmpty) return '';
  if (entry.title.trim().isNotEmpty) return body;
  final sentence = firstSentence(body);
  if (sentence.isEmpty) return '';
  return body.substring(sentence.length).trim();
}

/// 卡片预览要用的一段：要不要显示，以及从正文第几个纯文本字符开始渲染。
/// 渲染用的是原始 Markdown 文本，所以 [skip] 是纯文本下标；
/// 一次解析既算出空不空，也算出取句位置，卡片不用把正文解析两遍。
({bool visible, int skip}) previewSlice(Entry entry) {
  if (entry.body.trim().isEmpty) return (visible: false, skip: 0);
  if (entry.title.trim().isNotEmpty) return (visible: true, skip: 0);
  final plain = markdownPlainText(entry.body);
  final sentence = firstSentence(plain);
  if (sentence.isEmpty) return (visible: false, skip: 0);
  final skip = plain.length - plain.trimLeft().length + sentence.length;
  return (visible: skip < plain.trimRight().length, skip: skip);
}

String _two(int value) => value.toString().padLeft(2, '0');

/// 精确到分的时间，例如 2026-10-18 09:32。
String formatMinute(DateTime time) {
  final local = time.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

/// 卡片上的短时间：同年省掉年份，例如 10-18 09:32。
String formatCardTime(DateTime time, {DateTime? now}) {
  final local = time.toLocal();
  final current = (now ?? DateTime.now()).toLocal();
  final String minute = '${_two(local.hour)}:${_two(local.minute)}';
  if (local.year == current.year) {
    return '${_two(local.month)}-${_two(local.day)} $minute';
  }
  return '${local.year}-${_two(local.month)}-${_two(local.day)} $minute';
}
