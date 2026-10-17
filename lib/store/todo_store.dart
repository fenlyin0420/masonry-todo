import 'package:flutter/foundation.dart';

import '../models/todo.dart';
import 'todo_storage.dart';

/// 全应用唯一的数据源。任何改动都立即通知 UI，并异步落盘。
class TodoStore extends ChangeNotifier {
  TodoStore(this._storage);

  final TodoStorage _storage;
  final List<Todo> _todos = <Todo>[];
  ViewMode _viewMode = ViewMode.grid;
  bool _loaded = false;
  int _sequence = 0;
  Future<void> _pendingSave = Future<void>.value();

  bool get isLoaded => _loaded;
  ViewMode get viewMode => _viewMode;

  /// 未完成的在前（按创建时间新到旧），已完成的沉底（按完成时间新到旧）。
  List<Todo> get todos {
    final sorted = List<Todo>.of(_todos);
    sorted.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      if (a.done) {
        return (b.doneAt ?? b.createdAt).compareTo(a.doneAt ?? a.createdAt);
      }
      return b.createdAt.compareTo(a.createdAt);
    });
    return sorted;
  }

  int get activeCount => _todos.where((todo) => !todo.done).length;

  Todo? byId(String id) {
    for (final todo in _todos) {
      if (todo.id == id) return todo;
    }
    return null;
  }

  Future<void> load() async {
    final snapshot = await _storage.load();
    _todos
      ..clear()
      ..addAll(snapshot.todos);
    _viewMode = snapshot.viewMode;
    _loaded = true;
    notifyListeners();
  }

  String _newId(DateTime now) {
    _sequence++;
    return '${now.microsecondsSinceEpoch}-$_sequence';
  }

  Todo create({String title = '', String body = '', DateTime? now}) {
    final created = now ?? DateTime.now();
    final todo = Todo(
      id: _newId(created),
      title: title.trim(),
      body: body.trim(),
      createdAt: created,
    );
    _todos.add(todo);
    _persistAndNotify();
    return todo;
  }

  void setViewMode(ViewMode mode) {
    if (_viewMode == mode) return;
    _viewMode = mode;
    _persistAndNotify();
  }

  void setDone(String todoId, bool done, {DateTime? now}) {
    final todo = byId(todoId);
    if (todo == null || todo.done == done) return;
    todo.done = done;
    todo.doneAt = done ? (now ?? DateTime.now()) : null;
    _persistAndNotify();
  }

  Note? addNote(String todoId, String text, {DateTime? now}) {
    final content = text.trim();
    final todo = byId(todoId);
    if (todo == null || content.isEmpty) return null;
    final created = now ?? DateTime.now();
    final note = Note(
      id: _newId(created),
      text: content,
      createdAt: created,
    );
    todo.notes.add(note);
    _persistAndNotify();
    return note;
  }

  void delete(String todoId) {
    final before = _todos.length;
    _todos.removeWhere((todo) => todo.id == todoId);
    if (_todos.length == before) return;
    _persistAndNotify();
  }

  void _persistAndNotify() {
    notifyListeners();
    final snapshot = AppSnapshot(
      todos: List<Todo>.unmodifiable(_todos),
      viewMode: _viewMode,
    );
    _pendingSave = _pendingSave.then((_) => _storage.save(snapshot)).catchError(
      (Object error) {
        debugPrint('保存失败：$error');
      },
    );
  }

  /// 等待所有写入落盘。
  Future<void> flush() => _pendingSave;
}
