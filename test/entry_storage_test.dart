import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_todo/models/entry.dart';
import 'package:masonry_todo/store/entry_storage.dart';
import 'package:masonry_todo/store/entry_store.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('masonry_storage_test');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  FileEntryStorage buildStorage() =>
      FileEntryStorage(directoryProvider: () async => root);

  File dataFile() => File('${root.path}/masonry_todo/todos.json');

  AppSnapshot snapshotOf(String title) => AppSnapshot(
    entries: <Entry>[
      Entry(id: '1', title: title, createdAt: DateTime(2026, 10, 18)),
    ],
  );

  Future<void> writeJson(File file, String title) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      json.encode(snapshotOf(title).toJson()),
      flush: true,
    );
  }

  Future<String?> titleOf(File file) async {
    final dynamic json_ = jsonDecode(await file.readAsString());
    return json_['entries'][0]['title'] as String?;
  }

  test('保存后能读回来，上一份快照留在 .bak', () async {
    final FileEntryStorage storage = buildStorage();
    await storage.save(snapshotOf('第一版'));
    await storage.save(snapshotOf('第二版'));

    final LoadResult loaded = await storage.load();
    expect(loaded.snapshot.entries.single.title, '第二版');
    expect(loaded.recoveredFrom, isNull);
    expect(await titleOf(File('${dataFile().path}.bak')), '第一版');
  });

  test('主文件坏了就退回 .bak，并把坏文件留档', () async {
    final FileEntryStorage storage = buildStorage();
    await storage.save(snapshotOf('第一版'));
    await storage.save(snapshotOf('第二版'));
    await dataFile().writeAsString('{ 这不是 json', flush: true);

    final LoadResult loaded = await storage.load();
    expect(loaded.recoveredFrom, RecoverySource.backup);
    expect(loaded.snapshot.entries.single.title, '第一版');
    expect(await File('${dataFile().path}.corrupt').exists(), isTrue);
  });

  test('主文件没写成但临时文件更新，就用临时文件', () async {
    final FileEntryStorage storage = buildStorage();
    await storage.save(snapshotOf('旧内容'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await writeJson(File('${dataFile().path}.tmp'), '新内容');

    final LoadResult loaded = await storage.load();
    expect(loaded.recoveredFrom, RecoverySource.pending);
    expect(loaded.snapshot.entries.single.title, '新内容');
    expect(await File('${dataFile().path}.tmp').exists(), isFalse);
  });

  test('比主文件旧的临时文件不会顶掉主文件', () async {
    final FileEntryStorage storage = buildStorage();
    await writeJson(File('${dataFile().path}.tmp'), '早先的残留');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await writeJson(dataFile(), '当前内容');

    final LoadResult loaded = await storage.load();
    expect(loaded.recoveredFrom, isNull);
    expect(loaded.snapshot.entries.single.title, '当前内容');
  });

  test('半截临时文件被丢弃，不污染结果', () async {
    final FileEntryStorage storage = buildStorage();
    await storage.save(snapshotOf('当前内容'));
    await writeJson(File('${dataFile().path}.tmp'), '半截');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await File('${dataFile().path}.tmp').writeAsString('{"entries": [', flush: true);

    final LoadResult loaded = await storage.load();
    expect(loaded.snapshot.entries.single.title, '当前内容');
    expect(await File('${dataFile().path}.tmp').exists(), isFalse);
  });

  test('首次启动没有文件时是空列表', () async {
    final LoadResult loaded = await buildStorage().load();
    expect(loaded.snapshot.entries, isEmpty);
    expect(loaded.recoveredFrom, isNull);
  });

  test('保存失败会记在 store 上，重试成功后清空', () async {
    final _FlakyStorage storage = _FlakyStorage();
    final EntryStore store = EntryStore(storage);
    await store.load();

    storage.failing = true;
    store.create(title: '写周报');
    await store.flush();
    expect(store.saveError, isNotNull);
    expect(storage.snapshot.entries, isEmpty);

    storage.failing = false;
    await store.retrySave();
    expect(store.saveError, isNull);
    expect(storage.snapshot.entries.single.title, '写周报');
  });

  test('从兜底恢复的提示只取一次', () async {
    final FileEntryStorage storage = buildStorage();
    await storage.save(snapshotOf('第一版'));
    await storage.save(snapshotOf('第二版'));
    await dataFile().writeAsString('坏掉', flush: true);

    final EntryStore store = EntryStore(storage);
    await store.load();
    expect(store.takeRecoveryNotice(), RecoverySource.backup);
    expect(store.takeRecoveryNotice(), isNull);
  });
}

/// 可以让写入失败的存储，用来验证失败上报与重试。
class _FlakyStorage implements EntryStorage {
  AppSnapshot snapshot = const AppSnapshot(entries: <Entry>[]);
  bool failing = false;

  @override
  Future<LoadResult> load() async => LoadResult(snapshot);

  @override
  Future<void> save(AppSnapshot next) async {
    if (failing) throw const FileSystemException('磁盘写满');
    snapshot = next;
  }
}
