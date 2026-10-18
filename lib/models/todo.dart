/// 一条 todo 上挂的“楼层”内容：我对这个任务的看法、心得等。
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

/// 一个 todo：标题可为空，正文可选，完成状态与时间，以及若干条楼层记录。
class Todo {
  Todo({
    required this.id,
    required this.createdAt,
    this.title = '',
    this.body = '',
    this.done = false,
    this.doneAt,
    List<Note>? notes,
  }) : notes = notes ?? <Note>[];

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  bool done;
  DateTime? doneAt;
  final List<Note> notes;

  factory Todo.fromJson(Map<String, dynamic> json) {
    final notes = <Note>[];
    final rawNotes = json['notes'];
    if (rawNotes is List) {
      for (final raw in rawNotes) {
        if (raw is Map) {
          notes.add(Note.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
    }
    final rawDoneAt = json['doneAt'];
    return Todo(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      createdAt: parseDate(json['createdAt']),
      done: json['done'] == true,
      doneAt: rawDoneAt == null ? null : parseDate(rawDoneAt),
      notes: notes,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
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
