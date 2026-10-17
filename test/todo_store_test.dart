import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_todo/models/todo.dart';
import 'package:masonry_todo/store/todo_storage.dart';
import 'package:masonry_todo/store/todo_store.dart';

void main() {
  test('创建、完成、记录、删除都会通知并落盘', () async {
    final MemoryTodoStorage storage = MemoryTodoStorage();
    final TodoStore store = TodoStore(storage);
    await store.load();

    final Todo todo = store.create(title: '写周报', body: '三件事');
    await store.flush();
    expect(storage.snapshot.todos.single.title, '写周报');

    store.setDone(todo.id, true, now: DateTime(2026, 10, 18, 9, 30));
    await store.flush();
    expect(storage.snapshot.todos.single.done, isTrue);
    expect(storage.snapshot.todos.single.doneAt, DateTime(2026, 10, 18, 9, 30));

    store.addNote(todo.id, '其实可以下周再做', now: DateTime(2026, 10, 18, 9, 32));
    await store.flush();
    expect(storage.snapshot.todos.single.notes.single.text, '其实可以下周再做');

    store.delete(todo.id);
    await store.flush();
    expect(storage.snapshot.todos, isEmpty);
  });

  test('列表顺序：未完成在前，已完成的沉底', () async {
    final TodoStore store = TodoStore(MemoryTodoStorage());
    await store.load();
    final Todo old = store.create(title: '旧的', now: DateTime(2026, 10, 1));
    final Todo fresh = store.create(title: '新的', now: DateTime(2026, 10, 2));
    store.setDone(fresh.id, true, now: DateTime(2026, 10, 3));

    expect(store.todos.map((todo) => todo.title).toList(), <String>['旧的', '新的']);
    expect(store.activeCount, 1);

    store.setDone(fresh.id, false);
    expect(store.todos.first.title, '新的');
    expect(old.done, isFalse);
  });

  test('空白记录不会入库', () async {
    final TodoStore store = TodoStore(MemoryTodoStorage());
    await store.load();
    final Todo todo = store.create(title: '有标题');
    expect(store.addNote(todo.id, '   '), isNull);
    expect(store.byId(todo.id)!.notes, isEmpty);
  });

  test('展示形态也会持久化', () async {
    final MemoryTodoStorage storage = MemoryTodoStorage();
    final TodoStore store = TodoStore(storage);
    await store.load();
    store.setViewMode(ViewMode.list);
    await store.flush();

    final TodoStore reopened = TodoStore(storage);
    await reopened.load();
    expect(reopened.viewMode, ViewMode.list);
  });

  test('JSON 文件存储可跨实例读回，坏文件会被备份', () async {
    final Directory dir = await Directory.systemTemp.createTemp('masonry_todo_test');
    addTearDown(() => dir.delete(recursive: true));
    final FileTodoStorage storage = FileTodoStorage(directoryProvider: () async => dir);

    final TodoStore store = TodoStore(storage);
    await store.load();
    final Todo todo = store.create(title: '跨实例', body: '正文一句话。第二句。');
    store.addNote(todo.id, '心得', now: DateTime(2026, 10, 18, 9, 32));
    await store.flush();

    final TodoStore reopened = TodoStore(
      FileTodoStorage(directoryProvider: () async => dir),
    );
    await reopened.load();
    final Todo reloaded = reopened.todos.single;
    expect(reloaded.title, '跨实例');
    expect(reloaded.notes.single.text, '心得');
    expect(reloaded.notes.single.createdAt, DateTime(2026, 10, 18, 9, 32));

    final File file = File('${dir.path}/masonry_todo/todos.json');
    await file.writeAsString('{ 不是 json');
    final TodoStore broken = TodoStore(
      FileTodoStorage(directoryProvider: () async => dir),
    );
    await broken.load();
    expect(broken.todos, isEmpty);
    expect(File('${file.path}.corrupt').existsSync(), isTrue);
  });
}
