import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:masonry_todo/models/entry.dart';
import 'package:masonry_todo/store/note_image_store.dart';
import 'package:masonry_todo/store/entry_storage.dart';
import 'package:masonry_todo/store/entry_store.dart';

void main() {
  group('Note 带图片的序列化', () {
    test('toJson / fromJson 往返保留 image', () {
      final Note note = Note(
        id: '1',
        text: '看图',
        image: '12345-abcdef.jpg',
        createdAt: DateTime(2026, 10, 18),
      );
      final Note restored = Note.fromJson(note.toJson());
      expect(restored.image, '12345-abcdef.jpg');
      expect(restored.text, '看图');
    });

    test('无图时 json 不带 image 字段，读回兼容', () {
      final Note note = Note(
        id: '2',
        text: '没有图的旧记录',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(note.toJson().containsKey('image'), isFalse);
      expect(Note.fromJson(note.toJson()).image, isNull);
      expect(
        Note.fromJson(<String, dynamic>{
          'id': '3',
          'text': '旧',
          'createdAt': '2026-01-01T00:00:00.000',
        }).image,
        isNull,
      );
    });
  });

  group('addNote 图片', () {
    test('纯图片（无文字）可以发', () async {
      final EntryStore store = EntryStore(MemoryEntryStorage());
      await store.load();
      final Entry todo = store.create(title: '看图');
      final Note? note = store.addNote(
        todo.id,
        '',
        image: 'x.png',
        now: DateTime(2026, 10, 1),
      );
      expect(note, isNotNull);
      expect(note!.text, isEmpty);
      expect(note.image, 'x.png');
    });

    test('无文字也无图片被拒绝', () async {
      final EntryStore store = EntryStore(MemoryEntryStorage());
      await store.load();
      final Entry todo = store.create(title: '拒绝我');
      expect(store.addNote(todo.id, '', now: DateTime(2026, 10, 1)), isNull);
    });
  });

  group('NoteImageStore 文件流', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('masonry-images');
    });

    tearDown(() async {
      await tmp.delete(recursive: true);
    });

    NoteImageStore makeStore() =>
        NoteImageStore(directoryProvider: () async => tmp);

    File writePng(int width, int height) {
      final img.Image image = img.Image(
        width: width,
        height: height,
        format: img.Format.uint8,
      );
      for (int x = 0; x < width; x++) {
        image.setPixelRgb(x, 0, x % 256, (x + width) % 256, 80);
      }
      final File file = File('${tmp.path}/in.png');
      file.writeAsBytesSync(img.PngEncoder().encode(image));
      return file;
    }

    test('小图原样保留', () async {
      final NoteImageStore store = makeStore();
      final String name = await store.store(writePng(20, 20));
      expect(name.endsWith('.png'), isTrue);
      expect(await store.fileFor(name).then((file) => file.exists()), isTrue);
    });

    test('大图被压缩成 jpg 且尺寸不超过上限', () async {
      final NoteImageStore store = makeStore();
      final String name = await store.store(writePng(1700, 100));
      expect(name.endsWith('.jpg'), isTrue);
      final File file = await store.fileFor(name);
      final img.Image decoded = img.decodeImage(
        Uint8List.fromList(await file.readAsBytes()),
      )!;
      expect(decoded.width, lessThanOrEqualTo(NoteImageStore.maxSide));
      expect(decoded.height, lessThanOrEqualTo(NoteImageStore.maxSide));
    });

    test('gif 不经过解码压缩，原样保留', () async {
      final NoteImageStore store = makeStore();
      final File gif = File('${tmp.path}/in.gif');
      final List<int> raw = const [0x47, 0x49, 0x46, 0x38, 0x39, 0x61];
      gif.writeAsBytesSync(raw);
      final String name = await store.store(gif);
      expect(name.endsWith('.gif'), isTrue);
      expect(await store.fileFor(name).then((file) => file.readAsBytes()), raw);
    });

    test('deleteFile 清掉文件', () async {
      final NoteImageStore store = makeStore();
      final String name = await store.store(writePng(10, 10));
      await store.deleteFile(name);
      expect(await store.fileFor(name).then((file) => file.exists()), isFalse);
    });
  });
}
