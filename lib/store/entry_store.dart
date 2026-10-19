import 'package:flutter/foundation.dart';

import '../models/entry.dart';
import 'entry_storage.dart';

/// 导入合并的结果，用来给用户一句人话。
class ImportOutcome {
  const ImportOutcome({
    this.addedEntries = 0,
    this.addedNotes = 0,
    this.updatedEntries = 0,
  });

  final int addedEntries;
  final int addedNotes;
  final int updatedEntries;

  bool get isEmpty => addedEntries == 0 && addedNotes == 0 && updatedEntries == 0;
}

/// 全应用唯一的数据源。任何改动都立即通知 UI，并异步落盘。
class EntryStore extends ChangeNotifier {
  EntryStore(this._storage);

  final EntryStorage _storage;
  final List<Entry> _entries = <Entry>[];
  ViewMode _viewMode = ViewMode.grid;
  EntryKind _kind = EntryKind.todo;
  bool _loaded = false;
  int _sequence = 0;
  Future<void> _pendingSave = Future<void>.value();
  RecoverySource? _recovery;
  Object? _saveError;

  bool get isLoaded => _loaded;
  ViewMode get viewMode => _viewMode;

  /// 最近一次落盘失败的原因；成功后自动清空。非 null 时得让用户知道，
  /// 否则他以为改动已经存进手机了。
  Object? get saveError => _saveError;

  /// 取走一次性的「本次是从兜底文件恢复的」提示，取完即清。
  RecoverySource? takeRecoveryNotice() {
    final RecoverySource? recovery = _recovery;
    _recovery = null;
    return recovery;
  }

  /// 首页当前所在标签页。
  EntryKind get kind => _kind;

  /// 当前标签页的条目：待办里未完成的在前（新到旧），已完成的沉底
  /// （按完成时间新到旧）；灵感按创建时间新到旧。
  List<Entry> get entries {
    final sorted = List<Entry>.of(_entries);
    sorted.sort((a, b) {
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      if (a.isDone) {
        return (b.doneAt ?? b.createdAt).compareTo(a.doneAt ?? a.createdAt);
      }
      return b.createdAt.compareTo(a.createdAt);
    });
    return sorted;
  }

  /// 某一类条目，排序与 [entries] 一致。
  List<Entry> entriesOf(EntryKind kind) {
    return entries.where((entry) => entry.kind == kind).toList();
  }

  /// 首页列表要展示的条目（当前标签页）。
  List<Entry> get visibleEntries => entriesOf(_kind);

  /// 待办里未完成的条数；灵感没有完成状态，恒为 0。
  int activeCount([EntryKind kind = EntryKind.todo]) {
    if (kind == EntryKind.idea) return 0;
    return _entries.where((entry) => entry.isTodo && !entry.done).length;
  }

  int countOf(EntryKind kind) {
    return _entries.where((entry) => entry.kind == kind).length;
  }

  Entry? byId(String id) {
    for (final entry in _entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  Future<void> load() async {
    final LoadResult result = await _storage.load();
    final AppSnapshot snapshot = result.snapshot;
    _entries
      ..clear()
      ..addAll(snapshot.entries);
    _viewMode = snapshot.viewMode;
    _kind = snapshot.kind;
    _recovery = result.recoveredFrom;
    _loaded = true;
    notifyListeners();
  }

  String _newId(DateTime now) {
    _sequence++;
    return '${now.microsecondsSinceEpoch}-$_sequence';
  }

  Entry create({
    EntryKind kind = EntryKind.todo,
    String title = '',
    String body = '',
    DateTime? now,
  }) {
    final created = now ?? DateTime.now();
    final entry = Entry(
      id: _newId(created),
      kind: kind,
      title: title.trim(),
      body: body.trim(),
      createdAt: created,
    );
    _entries.add(entry);
    _persistAndNotify();
    return entry;
  }

  /// 改写标题与正文；id、类型、完成状态和楼层记录都不动。
  /// 内容确实变了才落盘并返回 true。
  bool update(String id, {required String title, required String body}) {
    final entry = byId(id);
    if (entry == null) return false;
    final String nextTitle = title.trim();
    final String nextBody = body.trim();
    if (entry.title == nextTitle && entry.body == nextBody) return false;
    final updated = Entry(
      id: entry.id,
      kind: entry.kind,
      title: nextTitle,
      body: nextBody,
      createdAt: entry.createdAt,
      done: entry.done,
      doneAt: entry.doneAt,
      notes: entry.notes,
    );
    final index = _entries.indexWhere((item) => item.id == id);
    _entries[index] = updated;
    _persistAndNotify();
    return true;
  }

  void setViewMode(ViewMode mode) {
    if (_viewMode == mode) return;
    _viewMode = mode;
    _persistAndNotify();
  }

  void setKind(EntryKind kind) {
    if (_kind == kind) return;
    _kind = kind;
    _persistAndNotify();
  }

  /// 灵感没有完成状态，调用会被忽略。
  void setDone(String entryId, bool done, {DateTime? now}) {
    final entry = byId(entryId);
    if (entry == null || !entry.isTodo || entry.done == done) return;
    entry.done = done;
    entry.doneAt = done ? (now ?? DateTime.now()) : null;
    _persistAndNotify();
  }

  Note? addNote(String entryId, String text, {String? image, DateTime? now}) {
    final content = text.trim();
    final entry = byId(entryId);
    if (entry == null || (content.isEmpty && image == null)) return null;
    final created = now ?? DateTime.now();
    final note = Note(
      id: _newId(created),
      text: content,
      createdAt: created,
      image: image,
    );
    entry.notes.add(note);
    _persistAndNotify();
    return note;
  }

  void delete(String entryId) {
    final before = _entries.length;
    _entries.removeWhere((entry) => entry.id == entryId);
    if (_entries.length == before) return;
    _persistAndNotify();
  }

  void _persistAndNotify() {
    notifyListeners();
    _persist();
  }

  /// 把当前状态排进写入队列；快照在这里定住，后面的改动各排各的。
  void _persist() {
    final snapshot = AppSnapshot(
      entries: List<Entry>.unmodifiable(_entries),
      viewMode: _viewMode,
      kind: _kind,
    );
    _pendingSave = _pendingSave.then((_) => _write(snapshot));
  }

  Future<void> _write(AppSnapshot snapshot) async {
    try {
      await _storage.save(snapshot);
      if (_saveError == null) return;
      _saveError = null;
      notifyListeners();
    } catch (error) {
      debugPrint('保存失败：$error');
      _saveError = error;
      notifyListeners();
    }
  }

  /// 导入合并的结果，用来给用户一句人话。
  ImportOutcome mergeImported(List<Entry> incoming) {
    int addedEntries = 0;
    int addedNotes = 0;
    int updatedEntries = 0;

    for (final Entry source in incoming) {
      final Entry? local = byId(source.id);
      if (local == null) {
        _entries.add(source);
        addedEntries++;
        addedNotes += source.notes.length;
        continue;
      }

      // 同一条目本地是用户后来改的，标题正文本地为准；只把本地缺的补上。
      bool touched = false;
      final Set<String> known = local.notes
          .map((Note note) => note.id)
          .toSet();
      for (final Note note in source.notes) {
        if (!known.add(note.id)) continue;
        local.notes.add(note);
        addedNotes++;
        touched = true;
      }

      if (source.isDone) {
        final DateTime sourceDoneAt = source.doneAt ?? source.createdAt;
        final DateTime? localDoneAt = local.doneAt;
        if (!local.isDone ||
            localDoneAt == null ||
            sourceDoneAt.isAfter(localDoneAt)) {
          local.done = true;
          local.doneAt = source.doneAt;
          touched = true;
        }
      }

      if (touched) updatedEntries++;
    }

    if (addedEntries > 0 || addedNotes > 0 || updatedEntries > 0) {
      _persistAndNotify();
    }
    return ImportOutcome(
      addedEntries: addedEntries,
      addedNotes: addedNotes,
      updatedEntries: updatedEntries,
    );
  }

  /// 保存失败后重试：再写一次当前状态。
  Future<void> retrySave() {
    _persist();
    return flush();
  }

  /// 等待所有写入落盘；切后台、退出前调用，别把排队中的改动留给进程被杀。
  Future<void> flush() => _pendingSave;
}
