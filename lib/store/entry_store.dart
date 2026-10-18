import 'package:flutter/foundation.dart';

import '../models/entry.dart';
import 'entry_storage.dart';

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

  bool get isLoaded => _loaded;
  ViewMode get viewMode => _viewMode;

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
    final snapshot = await _storage.load();
    _entries
      ..clear()
      ..addAll(snapshot.entries);
    _viewMode = snapshot.viewMode;
    _kind = snapshot.kind;
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
    final snapshot = AppSnapshot(
      entries: List<Entry>.unmodifiable(_entries),
      viewMode: _viewMode,
      kind: _kind,
    );
    _pendingSave = _pendingSave
        .then((_) => _storage.save(snapshot))
        .catchError((Object error) {
          debugPrint('保存失败：$error');
        });
  }

  /// 等待所有写入落盘。
  Future<void> flush() => _pendingSave;
}
