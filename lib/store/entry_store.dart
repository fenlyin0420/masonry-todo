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

  bool get isEmpty =>
      addedEntries == 0 && addedNotes == 0 && updatedEntries == 0;
}

/// 全应用唯一的数据源。任何改动都立即通知 UI，并异步落盘。
class EntryStore extends ChangeNotifier {
  EntryStore(this._storage);

  final EntryStorage _storage;
  final List<Entry> _entries = <Entry>[];
  ViewMode _todoViewMode = ViewMode.grid;
  ViewMode _ideaViewMode = ViewMode.grid;
  EntryKind _kind = EntryKind.todo;
  bool _showCompleted = false;
  bool _loaded = false;
  int _sequence = 0;
  Future<void> _pendingSave = Future<void>.value();
  RecoverySource? _recovery;
  Object? _saveError;

  bool get isLoaded => _loaded;

  /// 当前标签页的展示形态。待办与灵感各记各的。
  ViewMode get viewMode => viewModeOf(_kind);

  ViewMode viewModeOf(EntryKind kind) =>
      kind == EntryKind.idea ? _ideaViewMode : _todoViewMode;

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

  /// 待办页是否把已完成的也列出来。默认收起：完成过的任务不该占着优先级列表。
  bool get showCompleted => _showCompleted;

  /// 当前标签页的完整顺序：未完成在前（按优先级），已完成的沉底
  /// （同样按优先级，没排过的按完成时间新到旧）；灵感按优先级、再按创建时间。
  /// 优先级见 [Entry.rank]。
  List<Entry> get entries {
    final sorted = List<Entry>.of(_entries);
    sorted.sort(_compare);
    return sorted;
  }

  static int _compare(Entry a, Entry b) {
    if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
    if (a.rank != b.rank) return a.rank.compareTo(b.rank);
    if (a.isDone) {
      final int byDone = (b.doneAt ?? b.createdAt).compareTo(
        a.doneAt ?? a.createdAt,
      );
      if (byDone != 0) return byDone;
    }
    return b.createdAt.compareTo(a.createdAt);
  }

  /// 某一类条目，排序与 [entries] 一致。
  List<Entry> entriesOf(EntryKind kind) {
    return entries.where((entry) => entry.kind == kind).toList();
  }

  /// 首页列表要展示的条目（当前标签页），按过滤器筛掉已完成的。
  /// 灵感没有完成状态，过滤器对它是空操作。
  List<Entry> get visibleEntries => visibleEntriesOf(_kind);

  /// 指定标签页要展示的条目，规则同 [visibleEntries]。
  List<Entry> visibleEntriesOf(EntryKind kind) {
    final List<Entry> list = entriesOf(kind);
    if (_showCompleted || kind == EntryKind.idea) return list;
    return list.where((entry) => !entry.isDone).toList();
  }

  /// 当前标签页已完成的条数，用来在列表被过滤空的时候说清还藏了多少。
  int doneCount([EntryKind kind = EntryKind.todo]) {
    if (kind == EntryKind.idea) return 0;
    return _entries.where((entry) => entry.isTodo && entry.isDone).length;
  }

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
    _todoViewMode = snapshot.todoViewMode;
    _ideaViewMode = snapshot.ideaViewMode;
    _kind = snapshot.kind;
    _showCompleted = snapshot.showCompleted;
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
      rank: _minRank() - 1,
    );
    _entries.add(entry);
    _persistAndNotify();
    return entry;
  }

  /// 比现有任何条目都小的 rank，新建的排在最上面。
  int _minRank() {
    if (_entries.isEmpty) return 0;
    int min = _entries.first.rank;
    for (final entry in _entries) {
      if (entry.rank < min) min = entry.rank;
    }
    return min;
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
      rank: entry.rank,
      notes: entry.notes,
    );
    final index = _entries.indexWhere((item) => item.id == id);
    _entries[index] = updated;
    _persistAndNotify();
    return true;
  }

  /// 只改当前标签页的展示形态，另一边的设置不动。
  void setViewMode(ViewMode mode) {
    if (viewModeOf(_kind) == mode) return;
    if (_kind == EntryKind.idea) {
      _ideaViewMode = mode;
    } else {
      _todoViewMode = mode;
    }
    _persistAndNotify();
  }

  /// 当前状态的完整快照：落盘、导出备份都用它。
  AppSnapshot get snapshot => AppSnapshot(
    entries: List<Entry>.unmodifiable(entries),
    todoViewMode: _todoViewMode,
    ideaViewMode: _ideaViewMode,
    kind: _kind,
    showCompleted: _showCompleted,
  );

  void setKind(EntryKind kind) {
    if (_kind == kind) return;
    _kind = kind;
    _persistAndNotify();
  }

  /// 切换「显示已完成」。只影响待办页的列表，不改动任何条目。
  void setShowCompleted(bool value) {
    if (_showCompleted == value) return;
    _showCompleted = value;
    _persistAndNotify();
  }

  /// 拖动排序：把当前可见列表里第 [oldIndex] 项放到 [newIndex]
  /// （ReorderableListView 的 onReorderItem 语义，newIndex 已扣掉移出位）。
  /// 新位置即优先级：从拖完的顺序重新编 rank，被过滤器藏起来的条目
  /// 保持原相对顺序排在后面。
  void reorderVisible(int oldIndex, int newIndex) {
    final List<Entry> shown = List<Entry>.of(visibleEntries);
    if (oldIndex < 0 || oldIndex >= shown.length) return;
    int target = newIndex.clamp(0, shown.length - 1);
    if (target == oldIndex) return;

    final Entry moved = shown.removeAt(oldIndex);
    shown.insert(target, moved);

    final Set<String> shownIds = shown.map((entry) => entry.id).toSet();
    final List<Entry> merged = <Entry>[
      ...shown,
      for (final Entry entry in entriesOf(_kind))
        if (!shownIds.contains(entry.id)) entry,
    ];
    for (int i = 0; i < merged.length; i++) {
      merged[i].rank = i;
    }
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

  /// 改一层的正文与图片：图片只在 [imageChanged] 为真时才动，此时 [image] 为 null 表示去掉图。
  /// 改完文字与图片都为空时拒绝，返回 null 表示没改动。
  Note? updateNote(
    String entryId,
    String noteId, {
    required String text,
    String? image,
    bool imageChanged = false,
  }) {
    final entry = byId(entryId);
    if (entry == null) return null;
    final int index = entry.notes.indexWhere((Note note) => note.id == noteId);
    if (index < 0) return null;
    final Note before = entry.notes[index];
    final String content = text.trim();
    final String? nextImage = imageChanged ? image : before.image;
    if (content.isEmpty && nextImage == null) return null;
    final Note updated = Note(
      id: before.id,
      text: content,
      createdAt: before.createdAt,
      image: nextImage,
    );
    entry.notes[index] = updated;
    _persistAndNotify();
    return updated;
  }

  /// 删掉一层，返回被删的那一层：调用方据此清理它的图片文件。
  Note? removeNote(String entryId, String noteId) {
    final entry = byId(entryId);
    if (entry == null) return null;
    final int index = entry.notes.indexWhere((Note note) => note.id == noteId);
    if (index < 0) return null;
    final Note removed = entry.notes.removeAt(index);
    _persistAndNotify();
    return removed;
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
    final AppSnapshot frozen = snapshot;
    _pendingSave = _pendingSave.then((_) => _write(frozen));
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
      final Set<String> known = local.notes.map((Note note) => note.id).toSet();
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
