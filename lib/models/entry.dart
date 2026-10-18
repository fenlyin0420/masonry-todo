/// 条目的两种形态：待办有完成状态，灵感只是记录。
enum EntryKind { todo, idea }

/// 解析持久化的类型字段。旧数据没有 kind，一律当作待办。
EntryKind entryKindFromJson(Object? raw) {
  return raw == EntryKind.idea.name ? EntryKind.idea : EntryKind.todo;
}

/// 一条条目上挂的“楼层”内容：我对它的看法、心得等。
/// [image] 是随楼附带的图片在存储目录里的相对文件名（可为动图）。
class Note {
  Note({
    required this.id,
    required this.text,
    required this.createdAt,
    this.image,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final String? image;

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: (json['id'] as String?) ?? '',
      text: (json['text'] as String?) ?? '',
      createdAt: parseDate(json['createdAt']),
      image: json['image'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    if (image != null) 'image': image,
  };
}

/// 一条待办或灵感：标题可为空，正文可选，若干条楼层记录。
/// 只有待办使用 [done] / [doneAt]；灵感的这两个字段恒为 false / null。
class Entry {
  Entry({
    required this.id,
    required this.createdAt,
    this.kind = EntryKind.todo,
    this.title = '',
    this.body = '',
    this.done = false,
    this.doneAt,
    List<Note>? notes,
  }) : notes = notes ?? <Note>[];

  final String id;
  final EntryKind kind;
  final String title;
  final String body;
  final DateTime createdAt;

  bool done;
  DateTime? doneAt;
  final List<Note> notes;

  bool get isTodo => kind == EntryKind.todo;

  /// 灵感永远不算“完成”，避免调用方漏判 kind。
  bool get isDone => isTodo && done;

  factory Entry.fromJson(Map<String, dynamic> json) {
    final notes = <Note>[];
    final rawNotes = json['notes'];
    if (rawNotes is List) {
      for (final raw in rawNotes) {
        if (raw is Map) {
          notes.add(Note.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
    }
    final kind = entryKindFromJson(json['kind']);
    final bool done = kind == EntryKind.todo && json['done'] == true;
    final rawDoneAt = json['doneAt'];
    return Entry(
      id: (json['id'] as String?) ?? '',
      kind: kind,
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      createdAt: parseDate(json['createdAt']),
      done: done,
      doneAt: done && rawDoneAt != null ? parseDate(rawDoneAt) : null,
      notes: notes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'kind': kind.name,
    'title': title,
    'body': body,
    'createdAt': createdAt.toIso8601String(),
    'done': done,
    'doneAt': doneAt?.toIso8601String(),
    'notes': notes.map((note) => note.toJson()).toList(),
  };
}

DateTime parseDate(Object? raw) {
  if (raw is String) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toLocal();
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}
