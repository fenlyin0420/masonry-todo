import 'todo.dart';

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
String displayTitle(Todo todo) {
  final title = todo.title.trim();
  if (title.isNotEmpty) return title;
  final sentence = firstSentence(todo.body);
  return sentence.isEmpty ? '未命名' : sentence;
}

/// 卡片正文预览：若标题取自正文第一句，预览就从第二句开始，避免重复。
String bodyPreview(Todo todo) {
  final body = todo.body.trim();
  if (body.isEmpty) return '';
  if (todo.title.trim().isNotEmpty) return body;
  final sentence = firstSentence(body);
  if (sentence.isEmpty) return '';
  return body.substring(sentence.length).trim();
}

String _two(int value) => value.toString().padLeft(2, '0');

/// 精确到分的时间，例如 2026-10-18 09:32。
String formatMinute(DateTime time) {
  final local = time.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}';
}
