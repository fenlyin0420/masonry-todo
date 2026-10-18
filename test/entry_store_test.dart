import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_todo/models/entry.dart';
import 'package:masonry_todo/store/entry_storage.dart';
import 'package:masonry_todo/store/entry_store.dart';

void main() {
  test('创建、完成、记录、删除都会通知并落盘', () async {
    final MemoryEntryStorage storage = MemoryEntryStorage();
    final EntryStore store = EntryStore(storage);
    await store.load();

    final Entry entry = store.create(title: '写周报', body: '三件事');
    await store.flush();
    expect(storage.snapshot.entries.single.title, '写周报');

    store.setDone(entry.id, true, now: DateTime(2026, 10, 18, 9, 30));
    await store.flush();
    expect(storage.snapshot.entries.single.done, isTrue);
    expect(
      storage.snapshot.entries.single.doneAt,
      DateTime(2026, 10, 18, 9, 30),
    );

    store.addNote(entry.id, '其实可以下周再做', now: DateTime(2026, 10, 18, 9, 32));
    await store.flush();
    expect(storage.snapshot.entries.single.notes.single.text, '其实可以下周再做');

    store.delete(entry.id);
    await store.flush();
    expect(storage.snapshot.entries, isEmpty);
  });

  test('列表顺序：未完成在前，已完成的沉底', () async {
    final EntryStore store = EntryStore(MemoryEntryStorage());
    await store.load();
    final Entry old = store.create(title: '旧的', now: DateTime(2026, 10, 1));
    final Entry fresh = store.create(title: '新的', now: DateTime(2026, 10, 2));
    store.setDone(fresh.id, true, now: DateTime(2026, 10, 3));

    expect(store.entries.map((entry) => entry.title).toList(), <String>[
      '旧的',
      '新的',
    ]);
    expect(store.activeCount(), 1);

    store.setDone(fresh.id, false);
    expect(store.entries.first.title, '新的');
    expect(old.done, isFalse);
  });

  test('待办与灵感分开，灵感没有完成状态', () async {
    final EntryStore store = EntryStore(MemoryEntryStorage());
    await store.load();
    store.create(title: '买牛奶', now: DateTime(2026, 10, 1));
    final Entry idea = store.create(
      kind: EntryKind.idea,
      title: '如果把清单做成砖墙？',
      now: DateTime(2026, 10, 2),
    );

    expect(store.entriesOf(EntryKind.todo).single.title, '买牛奶');
    expect(store.entriesOf(EntryKind.idea).single.title, '如果把清单做成砖墙？');
    expect(store.countOf(EntryKind.todo), 1);
    expect(store.countOf(EntryKind.idea), 1);
    expect(store.activeCount(), 1);
    expect(store.activeCount(EntryKind.idea), 0);

    store.setDone(idea.id, true);
    expect(idea.done, isFalse, reason: '灵感不接受完成操作');
    expect(idea.doneAt, isNull);

    store.setKind(EntryKind.idea);
    expect(store.visibleEntries.single.id, idea.id);
    expect(store.visibleEntries.single.isDone, isFalse);
  });

  test('编辑标题与正文保留楼层、类型和完成状态', () async {
    final MemoryEntryStorage storage = MemoryEntryStorage();
    final EntryStore store = EntryStore(storage);
    await store.load();
    final Entry entry = store.create(title: '旧标题', body: '旧正文');
    store.addNote(entry.id, '一条记录', now: DateTime(2026, 10, 1));
    store.setDone(entry.id, true, now: DateTime(2026, 10, 2));

    expect(store.update(entry.id, title: '新标题', body: '新正文'), isTrue);
    final Entry updated = store.byId(entry.id)!;
    expect(updated.title, '新标题');
    expect(updated.body, '新正文');
    expect(updated.done, isTrue);
    expect(updated.doneAt, DateTime(2026, 10, 2));
    expect(updated.notes.single.text, '一条记录');
    await store.flush();
    expect(storage.snapshot.entries.single.title, '新标题');

    expect(
      store.update(entry.id, title: '新标题', body: '新正文'),
      isFalse,
      reason: '内容没变就不用再落盘',
    );
  });

  test('空白记录不会入库', () async {
    final EntryStore store = EntryStore(MemoryEntryStorage());
    await store.load();
    final Entry entry = store.create(title: '有标题');
    expect(store.addNote(entry.id, '   '), isNull);
    expect(store.byId(entry.id)!.notes, isEmpty);
  });

  test('展示形态与当前标签页都会持久化', () async {
    final MemoryEntryStorage storage = MemoryEntryStorage();
    final EntryStore store = EntryStore(storage);
    await store.load();
    store.setViewMode(ViewMode.list);
    store.setKind(EntryKind.idea);
    await store.flush();

    final EntryStore reopened = EntryStore(storage);
    await reopened.load();
    expect(reopened.viewMode, ViewMode.list);
    expect(reopened.kind, EntryKind.idea);
  });

  test('JSON 文件存储可跨实例读回，坏文件会被备份', () async {
    final Directory dir = await Directory.systemTemp.createTemp(
      'shiji_test',
    );
    addTearDown(() => dir.delete(recursive: true));
    final FileEntryStorage storage = FileEntryStorage(
      directoryProvider: () async => dir,
    );

    final EntryStore store = EntryStore(storage);
    await store.load();
    final Entry entry = store.create(title: '跨实例', body: '正文一句话。第二句。');
    store.addNote(entry.id, '心得', now: DateTime(2026, 10, 18, 9, 32));
    await store.flush();

    final EntryStore reopened = EntryStore(
      FileEntryStorage(directoryProvider: () async => dir),
    );
    await reopened.load();
    final Entry reloaded = reopened.entries.single;
    expect(reloaded.title, '跨实例');
    expect(reloaded.notes.single.text, '心得');
    expect(reloaded.notes.single.createdAt, DateTime(2026, 10, 18, 9, 32));

    final File file = File('${dir.path}/masonry_todo/todos.json');
    await file.writeAsString('{ 不是 json');
    final EntryStore broken = EntryStore(
      FileEntryStorage(directoryProvider: () async => dir),
    );
    await broken.load();
    expect(broken.entries, isEmpty);
    expect(File('${file.path}.corrupt').existsSync(), isTrue);
  });

  group('旧数据兼容', () {
    test('v1 的 todos 字段、没有 kind 时按待办读取', () {
      final AppSnapshot snapshot = AppSnapshot.fromJson(<String, dynamic>{
        'version': 1,
        'viewMode': 'list',
        'todos': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': '1',
            'title': '旧待办',
            'body': '',
            'createdAt': '2026-10-01T09:00:00.000',
            'done': true,
            'doneAt': '2026-10-02T09:00:00.000',
            'notes': <Map<String, dynamic>>[],
          },
        ],
      });
      final Entry entry = snapshot.entries.single;
      expect(entry.kind, EntryKind.todo);
      expect(entry.isDone, isTrue);
      expect(entry.doneAt, DateTime(2026, 10, 2, 9));
      expect(snapshot.viewMode, ViewMode.list);
      expect(snapshot.kind, EntryKind.todo);
    });

    test('灵感的 done 字段被忽略，导出保留 kind', () {
      final Entry idea = Entry.fromJson(<String, dynamic>{
        'id': '2',
        'kind': 'idea',
        'title': '一个念头',
        'createdAt': '2026-10-01T09:00:00.000',
        'done': true,
        'doneAt': '2026-10-02T09:00:00.000',
      });
      expect(idea.isDone, isFalse);
      expect(idea.doneAt, isNull);
      expect(idea.toJson()['kind'], 'idea');

      final AppSnapshot snapshot = AppSnapshot(entries: <Entry>[idea]);
      expect(
        (snapshot.toJson()['entries'] as List<dynamic>).single,
        containsPair('kind', 'idea'),
      );
    });
  });
}
