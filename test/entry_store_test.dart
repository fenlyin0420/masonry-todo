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

    store.addNote(entry.id, '先记一笔', now: DateTime(2026, 10, 18, 9, 20));
    store.setDone(entry.id, true, now: DateTime(2026, 10, 18, 9, 30));
    await store.flush();
    expect(storage.snapshot.entries.single.done, isTrue);
    expect(
      storage.snapshot.entries.single.doneAt,
      DateTime(2026, 10, 18, 9, 30),
    );

    store.addNote(entry.id, '其实可以下周再做', now: DateTime(2026, 10, 18, 9, 32));
    await store.flush();
    expect(storage.snapshot.entries.single.notes.last.text, '其实可以下周再做');

    store.delete(entry.id);
    await store.flush();
    expect(storage.snapshot.entries, isEmpty);
  });

  test('没写过感想的待办不允许完成', () async {
    final EntryStore store = EntryStore(MemoryEntryStorage());
    await store.load();
    final Entry entry = store.create(title: '直接想勾掉');

    expect(store.setDone(entry.id, true), isFalse, reason: '先写感想');
    expect(entry.done, isFalse);
    expect(entry.doneAt, isNull);

    store.addNote(entry.id, '想法');
    expect(store.setDone(entry.id, true), isTrue);
    expect(entry.done, isTrue);
  });

  test('列表顺序：未完成在前，已完成的沉底', () async {
    final EntryStore store = EntryStore(MemoryEntryStorage());
    await store.load();
    final Entry old = store.create(title: '旧的', now: DateTime(2026, 10, 1));
    final Entry fresh = store.create(title: '新的', now: DateTime(2026, 10, 2));
    store.addNote(fresh.id, '做完了', now: DateTime(2026, 10, 2, 1));
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

  test('楼层可以改文字、换图、删图，也可以整层删掉', () async {
    final MemoryEntryStorage storage = MemoryEntryStorage();
    final EntryStore store = EntryStore(storage);
    await store.load();
    final Entry entry = store.create(title: '有标题');
    final Note note = store.addNote(
      entry.id,
      '原来那句',
      image: 'a.png',
      now: DateTime(2026, 10, 18, 9, 32),
    )!;

    final Note? edited = store.updateNote(entry.id, note.id, text: '  改好了  ');
    await store.flush();
    expect(edited!.text, '改好了');
    expect(edited.image, 'a.png', reason: '没动图片就原样留着');
    expect(edited.createdAt, note.createdAt, reason: '改文字不挪时间');
    expect(storage.snapshot.entries.single.notes.single.text, '改好了');

    store.updateNote(
      entry.id,
      note.id,
      text: '换图',
      image: 'b.png',
      imageChanged: true,
    );
    expect(entry.notes.single.image, 'b.png');

    store.updateNote(entry.id, note.id, text: '纯文字', imageChanged: true);
    expect(entry.notes.single.image, isNull, reason: 'imageChanged 且无图就是删图');

    expect(
      store.updateNote(entry.id, note.id, text: '   '),
      isNull,
      reason: '没有图的时候不能把文字清空',
    );
    expect(entry.notes.single.text, '纯文字');

    expect(
      store.updateNote(
        entry.id,
        note.id,
        text: '某一层',
        image: 'c.png',
        imageChanged: true,
      ),
      isNotNull,
    );
    expect(
      store.updateNote(entry.id, note.id, text: '  ', imageChanged: true),
      isNull,
      reason: '文字和图片都空了不允许',
    );
    expect(entry.notes.single.text, '某一层');
    expect(entry.notes.single.image, 'c.png');

    final Note? removed = store.removeNote(entry.id, note.id);
    await store.flush();
    expect(removed!.image, 'c.png');
    expect(entry.notes, isEmpty);
    expect(storage.snapshot.entries.single.notes, isEmpty);
    expect(store.removeNote(entry.id, note.id), isNull);
  });

  test('待办与灵感的展示形态各记各的', () async {
    final MemoryEntryStorage storage = MemoryEntryStorage();
    final EntryStore store = EntryStore(storage);
    await store.load();
    store.setViewMode(ViewMode.list);
    store.setKind(EntryKind.idea);
    expect(store.viewMode, ViewMode.grid, reason: '灵感页不受待办页影响');
    await store.flush();

    final EntryStore reopened = EntryStore(storage);
    await reopened.load();
    expect(reopened.kind, EntryKind.idea);
    expect(reopened.viewModeOf(EntryKind.todo), ViewMode.list);
    expect(reopened.viewModeOf(EntryKind.idea), ViewMode.grid);

    reopened.setViewMode(ViewMode.list);
    reopened.setKind(EntryKind.todo);
    reopened.setViewMode(ViewMode.grid);
    await reopened.flush();

    final EntryStore again = EntryStore(storage);
    await again.load();
    expect(again.viewModeOf(EntryKind.todo), ViewMode.grid);
    expect(again.viewModeOf(EntryKind.idea), ViewMode.list);
  });

  test('JSON 文件存储可跨实例读回，坏文件会被备份', () async {
    final Directory dir = await Directory.systemTemp.createTemp('shiji_test');
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
    // 坏掉的主文件留档，数据从上一次成功保存的备份里救回来。
    expect(File('${file.path}.corrupt').existsSync(), isTrue);
    expect(broken.takeRecoveryNotice(), RecoverySource.backup);
    expect(broken.entries.single.title, '跨实例');
  });

  test('过滤器默认收起已完成，开关会落盘', () async {
    final MemoryEntryStorage storage = MemoryEntryStorage();
    final EntryStore store = EntryStore(storage);
    await store.load();
    final Entry kept = store.create(title: '还没做', now: DateTime(2026, 10, 1));
    final Entry finished = store.create(
      title: '做完了',
      now: DateTime(2026, 10, 2),
    );
    store.addNote(finished.id, '收尾了', now: DateTime(2026, 10, 2, 1));
    store.setDone(finished.id, true, now: DateTime(2026, 10, 3));

    expect(store.showCompleted, isFalse, reason: '默认隐藏已完成');
    expect(
      store.visibleEntries.map((Entry entry) => entry.id).toList(),
      <String>[kept.id],
    );
    expect(store.entries, hasLength(2), reason: 'entries 不受过滤器影响');
    expect(store.doneCount(), 1);

    store.setShowCompleted(true);
    expect(
      store.visibleEntries.map((Entry entry) => entry.id).toList(),
      <String>[kept.id, finished.id],
      reason: '打开后已完成的排在后面',
    );
    await store.flush();

    final EntryStore reopened = EntryStore(storage);
    await reopened.load();
    expect(reopened.showCompleted, isTrue);
    expect(reopened.doneCount(), 1);
    expect(reopened.doneCount(EntryKind.idea), 0);
  });

  test('拖动排序把顺序改写成优先级，并且落盘', () async {
    final MemoryEntryStorage storage = MemoryEntryStorage();
    final EntryStore store = EntryStore(storage);
    await store.load();
    final Entry older = store.create(title: '一', now: DateTime(2026, 10, 1));
    final Entry middle = store.create(title: '二', now: DateTime(2026, 10, 2));
    final Entry fresh = store.create(title: '三', now: DateTime(2026, 10, 3));
    expect(
      store.visibleEntries.map((Entry entry) => entry.title).toList(),
      <String>['三', '二', '一'],
      reason: '新建的排在最前面',
    );

    // 拖到底：第一项变成最低优先级。
    store.reorderVisible(0, 2);
    expect(
      store.visibleEntries.map((Entry entry) => entry.title).toList(),
      <String>['二', '一', '三'],
    );
    expect(fresh.rank, greaterThan(older.rank));

    // 拖到顶：最后一项变成最高优先级。
    store.reorderVisible(2, 0);
    expect(
      store.visibleEntries.map((Entry entry) => entry.title).toList(),
      <String>['三', '二', '一'],
    );
    await store.flush();
    final int saves = storage.saveCount;
    store.reorderVisible(1, 1);
    await store.flush();
    expect(storage.saveCount, saves, reason: '没挪动就不写盘');
    await store.flush();

    final EntryStore reopened = EntryStore(storage);
    await reopened.load();
    expect(
      reopened.visibleEntries.map((Entry entry) => entry.title).toList(),
      <String>['三', '二', '一'],
      reason: '优先级跟条目一起存',
    );

    // 新建的仍然插到最前面。
    reopened.create(title: '四', now: DateTime(2026, 10, 4));
    expect(
      reopened.visibleEntries.map((Entry entry) => entry.title).toList(),
      <String>['四', '三', '二', '一'],
    );
    expect(middle.done, isFalse);
  });

  test('旧数据没有 rank 时按 0 处理，快照读写会带上它', () {
    final Entry a = Entry.fromJson(<String, dynamic>{
      'id': 'a',
      'title': '早的',
      'createdAt': '2026-10-01T09:00:00.000',
    });
    final Entry b = Entry.fromJson(<String, dynamic>{
      'id': 'b',
      'title': '晚的',
      'createdAt': '2026-10-02T09:00:00.000',
    });
    expect(a.rank, 0);
    expect(b.rank, 0);
    final AppSnapshot snapshot = AppSnapshot(entries: <Entry>[a, b]);
    final Map<String, dynamic> json = snapshot.toJson();
    expect((json['entries'] as List<dynamic>).first, containsPair('rank', 0));
    expect(AppSnapshot.fromJson(json).showCompleted, isFalse);
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
      expect(snapshot.viewModeOf(EntryKind.todo), ViewMode.list);
      expect(
        snapshot.viewModeOf(EntryKind.idea),
        ViewMode.list,
        reason: '旧数据只有一个 viewMode，两边都沿用它',
      );
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
