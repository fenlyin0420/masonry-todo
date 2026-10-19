import 'dart:convert';
import 'dart:typed_data';

import '../models/entry.dart';
import 'entry_storage.dart';
import 'note_image_store.dart';

/// 备份文件的格式标记与版本，导入时用来挡掉不是本应用导出的文件。
const String backupFormat = 'masonry_todo.backup';
const int backupVersion = 1;

/// 一份备份：条目快照 + 楼层图片字节。
/// 图片以 base64 塞在同一个 JSON 里，整包就是一个 `.json`，不用打 zip。
class BackupBundle {
  const BackupBundle({
    required this.snapshot,
    this.images = const <String, Uint8List>{},
  });

  final AppSnapshot snapshot;
  final Map<String, Uint8List> images;

  int get entryCount => snapshot.entries.length;
  int get imageCount => images.length;
}

/// 导出结果：备份文本 + 打包进去多少张图 + 哪些图在原机已经找不到。
/// [missingImages] 非空就要告诉用户，不然他会以为整包都带上了。
class BackupExport {
  const BackupExport({
    required this.text,
    required this.imageCount,
    this.missingImages = const <String>[],
  });

  final String text;
  final int imageCount;
  final List<String> missingImages;
}

/// 把快照和它引用到的图片编码成备份文本。
/// 引用到的图片文件不在磁盘上就跳过，不值得为一张丢了的图让整次导出失败；
/// 但会把名字记在 [BackupExport.missingImages] 里，由界面提示用户。
Future<BackupExport> encodeBackup(
  AppSnapshot snapshot,
  NoteImageStore images, {
  String? appVersion,
  DateTime? now,
}) async {
  final Map<String, String> encoded = <String, String>{};
  final List<String> missing = <String>[];
  for (final Entry entry in snapshot.entries) {
    for (final Note note in entry.notes) {
      final String? name = note.image;
      if (name == null || encoded.containsKey(name) || missing.contains(name)) {
        continue;
      }
      final Uint8List? bytes = await images.read(name);
      if (bytes == null) {
        missing.add(name);
        continue;
      }
      encoded[name] = base64Encode(bytes);
    }
  }
  final Map<String, dynamic> json = <String, dynamic>{
    'format': backupFormat,
    'version': backupVersion,
    'exportedAt': (now ?? DateTime.now()).toIso8601String(),
    'appVersion': ?appVersion,
    'snapshot': snapshot.toJson(),
    'images': encoded,
  };
  return BackupExport(
    text: const JsonEncoder.withIndent('  ').convert(json),
    imageCount: encoded.length,
    missingImages: missing,
  );
}

/// 解析备份文本。认两种：本应用导出的备份，以及直接拷来的 `todos.json`
/// （只有 `entries` / `todos` 字段）。其它一律抛 [FormatException]，
/// 文案直接能丢给用户看。
BackupBundle decodeBackup(String raw) {
  Object? decoded;
  try {
    decoded = json.decode(raw);
  } catch (_) {
    throw const FormatException('这个文件不是 JSON，可能选错了');
  }
  if (decoded is! Map) throw const FormatException('这个文件不是拾记的备份');

  final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);
  final bool wrapped = map['format'] == backupFormat;
  final Object? rawSnapshot = wrapped ? map['snapshot'] : map;
  if (rawSnapshot is! Map) throw const FormatException('这个文件里没有条目数据');

  final Map<String, dynamic> snapshot = Map<String, dynamic>.from(rawSnapshot);
  if (!snapshot.containsKey('entries') && !snapshot.containsKey('todos')) {
    throw const FormatException('这个文件里没有条目数据');
  }

  final Map<String, Uint8List> images = <String, Uint8List>{};
  final Object? rawImages = map['images'];
  if (wrapped && rawImages is Map) {
    rawImages.forEach((Object? key, Object? value) {
      if (key is! String || value is! String) return;
      try {
        images[key] = base64Decode(value);
      } catch (_) {
        // 单张图坏了不连累整包，条目照常导入。
      }
    });
  }

  return BackupBundle(
    snapshot: AppSnapshot.fromJson(snapshot),
    images: images,
  );
}
