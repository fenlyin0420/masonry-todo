import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:masonry_todo/models/entry.dart';
import 'package:masonry_todo/store/backup.dart';
import 'package:masonry_todo/store/entry_storage.dart';
import 'package:masonry_todo/store/entry_store.dart';
import 'package:masonry_todo/store/note_image_store.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('masonry_backup_test');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  NoteImageStore buildImages() =>
      NoteImageStore(directoryProvider: () async => root);

  Entry entryWithImage() => Entry(
    id: 'e1',
    title: '带图的记录',
    createdAt: DateTime(2026, 10, 18, 9),
    notes: <Note>[
      Note(
        id: 'n1',
        text: '看图',
        image: 'n1.jpg',
        createdAt: DateTime(2026, 10, 18, 9, 5),
      ),
    ],
  );

  test('导出带图片，解析回来条目与图片都还在', () async {
    final NoteImageStore images = buildImages();
    await images.restore('n1.jpg', Uint8List.fromList(<int>[7, 8, 9]));

    final BackupExport backup = await encodeBackup(
      AppSnapshot(entries: <Entry>[entryWithImage()]),
      images,
      appVersion: '1.3.1+6',
      now: DateTime(2026, 10, 18, 9, 30),
    );
    expect(backup.text, contains('"format": "masonry_todo.backup"'));
    expect(backup.imageCount, 1);
    expect(backup.missingImages, isEmpty);

    final BackupBundle bundle = decodeBackup(backup.text);
    expect(bundle.entryCount, 1);
    expect(bundle.imageCount, 1);
    expect(bundle.snapshot.entries.single.notes.single.image, 'n1.jpg');
    expect(bundle.images['n1.jpg'], orderedEquals(<int>[7, 8, 9]));
  });

  test('图片文件丢了也能导出，但要报出没进备份的那几张', () async {
    final BackupExport backup = await encodeBackup(
      AppSnapshot(entries: <Entry>[entryWithImage()]),
      buildImages(),
    );
    final BackupBundle bundle = decodeBackup(backup.text);
    expect(bundle.snapshot.entries.single.notes.single.image, 'n1.jpg');
    expect(bundle.images, isEmpty);
    expect(backup.imageCount, 0);
    expect(backup.missingImages, <String>['n1.jpg']);
  });

  test('真实流程：压缩后的图能整包搬到新机器', () async {
    // 走一遍生产路径：原图 → NoteImageStore.store() 压缩落盘 → 导出 → 导入。
    final Directory source = await Directory.systemTemp.createTemp('photo');
    addTearDown(() => source.delete(recursive: true));
    final File original = File('${source.path}/photo.png');
    await original.writeAsBytes(
      img.encodePng(img.Image(width: 40, height: 30)..clear(img.ColorRgb8(10, 120, 200))),
      flush: true,
    );

    final NoteImageStore phone = NoteImageStore(
      directoryProvider: () async => root,
    );
    final String stored = await phone.store(original);
    final Uint8List storedBytes = (await phone.read(stored))!;

    final Entry entry = Entry(
      id: 'e1',
      title: '带图',
      createdAt: DateTime(2026, 10, 18),
      notes: <Note>[
        Note(
          id: 'n1',
          text: '看图',
          image: stored,
          createdAt: DateTime(2026, 10, 18, 9, 5),
        ),
      ],
    );
    final BackupExport backup = await encodeBackup(
      AppSnapshot(entries: <Entry>[entry]),
      phone,
    );
    expect(backup.imageCount, 1);

    // 新机器：空目录，只有备份文件。
    final Directory fresh = await Directory.systemTemp.createTemp('fresh');
    addTearDown(() => fresh.delete(recursive: true));
    final NoteImageStore other = NoteImageStore(
      directoryProvider: () async => fresh,
    );
    final BackupBundle bundle = decodeBackup(backup.text);
    for (final MapEntry<String, Uint8List> image in bundle.images.entries) {
      expect(await other.restore(image.key, image.value), isTrue);
    }

    expect(await other.exists(stored), isTrue);
    expect(await other.read(stored), orderedEquals(storedBytes));
  });

  test('直接拷来的 todos.json 也能导入', () {
    final String raw = json.encode(<String, dynamic>{
      'version': 1,
      'todos': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'x',
          'title': '旧数据',
          'createdAt': '2026-10-18T00:00:00.000',
        },
      ],
    });
    final BackupBundle bundle = decodeBackup(raw);
    expect(bundle.snapshot.entries.single.title, '旧数据');
    expect(bundle.images, isEmpty);
  });

  test('不是备份的文件给出能看懂的错误', () {
    for (final String raw in <String>['不是 json', '{"a": 1}', '[1, 2]']) {
      expect(
        () => decodeBackup(raw),
        throwsA(
          isA<FormatException>().having(
            (FormatException error) => error.message,
            'message',
            isNotEmpty,
          ),
        ),
      );
    }
  });

  test('导入合并：新条目补上，同一条目以本地为准', () async {
    final EntryStore store = EntryStore(MemoryEntryStorage());
    await store.load();
    final Entry local = store.create(
      title: '手机上改过的标题',
      now: DateTime(2026, 10, 1),
    );
    store.addNote(local.id, '本地楼层', now: DateTime(2026, 10, 2));
    final String localNoteId = local.notes.single.id;

    final Entry fromBackup = Entry(
      id: local.id,
      title: '备份里的旧标题',
      createdAt: DateTime(2026, 10, 1),
      done: true,
      doneAt: DateTime(2026, 10, 3),
      notes: <Note>[
        Note(
          id: localNoteId,
          text: '本地楼层',
          createdAt: DateTime(2026, 10, 2),
        ),
        Note(
          id: 'n-new',
          text: '备份里的另一层',
          createdAt: DateTime(2026, 10, 4),
        ),
      ],
    );
    final Entry onlyInBackup = Entry(
      id: 'e2',
      title: '备份独有',
      createdAt: DateTime(2026, 9, 1),
    );

    final ImportOutcome outcome = store.mergeImported(<Entry>[
      fromBackup,
      onlyInBackup,
    ]);
    await store.flush();

    expect(outcome.addedEntries, 1);
    expect(outcome.addedNotes, 1);
    expect(outcome.updatedEntries, 1);

    final Entry merged = store.byId(local.id)!;
    expect(merged.title, '手机上改过的标题');
    expect(merged.notes.length, 2);
    expect(merged.done, isTrue);
    expect(merged.doneAt, DateTime(2026, 10, 3));
    expect(store.byId('e2')!.title, '备份独有');
  });

  test('重复导入同一份备份是空操作', () async {
    final EntryStore store = EntryStore(MemoryEntryStorage());
    await store.load();
    final Entry onlyInBackup = Entry(
      id: 'e2',
      title: '备份独有',
      createdAt: DateTime(2026, 9, 1),
    );
    store.mergeImported(<Entry>[onlyInBackup]);

    final ImportOutcome again = store.mergeImported(<Entry>[onlyInBackup]);
    expect(again.isEmpty, isTrue);
  });

  test('导入图片不覆盖同名文件，也不写到目录外', () async {
    final NoteImageStore images = buildImages();
    expect(await images.restore('a.jpg', Uint8List.fromList(<int>[1, 2, 3])), isTrue);
    expect(await images.restore('a.jpg', Uint8List.fromList(<int>[9])), isFalse);
    expect(await images.read('a.jpg'), orderedEquals(<int>[1, 2, 3]));
    expect(await images.restore('../evil.jpg', Uint8List.fromList(<int>[1])), isFalse);
  });
}
