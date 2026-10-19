import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/entry.dart';

/// 首页展示形态。
enum ViewMode { grid, list }

/// 落盘的一份完整快照：所有条目 + 首页展示形态 + 当前标签页。
class AppSnapshot {
  const AppSnapshot({
    required this.entries,
    this.viewMode = ViewMode.grid,
    this.kind = EntryKind.todo,
  });

  final List<Entry> entries;
  final ViewMode viewMode;
  final EntryKind kind;

  factory AppSnapshot.fromJson(Map<String, dynamic> json) {
    final entries = <Entry>[];
    // v1.2 起字段叫 entries；旧版本写的是 todos，读的时候两者都认。
    final rawEntries = json['entries'] ?? json['todos'];
    if (rawEntries is List) {
      for (final raw in rawEntries) {
        if (raw is Map) {
          entries.add(Entry.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
    }
    return AppSnapshot(
      entries: entries,
      viewMode: json['viewMode'] == 'list' ? ViewMode.list : ViewMode.grid,
      kind: entryKindFromJson(json['kind']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': 2,
    'viewMode': viewMode == ViewMode.list ? 'list' : 'grid',
    'kind': kind.name,
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };
}

/// 载入时用了哪个兜底文件。非 null 说明主文件这次没用上、数据是救回来的，
/// 欠用户一句提示，不然他会以为数据没了。
enum RecoverySource {
  /// 上次保存写完了临时文件，还没走到改名就中断了。
  pending,

  /// 主文件读不出来或坏了，退回上一次成功保存的快照。
  backup,
}

/// 载入结果：快照本身，加上这次是否走了兜底。
class LoadResult {
  const LoadResult(this.snapshot, {this.recoveredFrom});

  final AppSnapshot snapshot;
  final RecoverySource? recoveredFrom;
}

abstract class EntryStorage {
  Future<LoadResult> load();
  Future<void> save(AppSnapshot snapshot);
}

/// JSON 文件存储。
///
/// 三层防护，都是为了进程被系统杀掉时还不丢数据：
/// - 写入先落 `todos.json.tmp` 再改名，主文件永远不会是半截 JSON；
/// - 改名之前把旧主文件轮转为 `todos.json.bak`，主文件坏掉还有上一份；
/// - 读取按 主文件 → 更新的 tmp → bak 依次退让，读不出来的文件改名留档。
class FileEntryStorage implements EntryStorage {
  FileEntryStorage({Future<Directory> Function()? directoryProvider})
    : _directoryProvider =
          directoryProvider ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directoryProvider;
  Future<File>? _file;

  Future<File> _resolve() => _file ??= () async {
    final base = await _directoryProvider();
    final dir = Directory('${base.path}/masonry_todo');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    // 目录与文件名沿用 1.x 的命名，升级时不搬数据。
    return File('${dir.path}/todos.json');
  }();

  @override
  Future<LoadResult> load() async {
    final file = await _resolve();
    final pending = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');

    final AppSnapshot? main = await _read(file);
    final AppSnapshot? tmp = await _read(pending, keepCorrupt: false);

    // 临时文件是上次保存写完、还没改名的那一份，只有不比主文件旧时才认，
    // 免得很久以前残留的一份把新数据顶掉。
    if (tmp != null && (main == null || !await _isOlder(pending, file))) {
      await _deleteQuietly(pending);
      return LoadResult(tmp, recoveredFrom: RecoverySource.pending);
    }
    if (main != null) {
      if (await pending.exists()) await _deleteQuietly(pending);
      return LoadResult(main);
    }
    final AppSnapshot? bak = await _read(backup);
    if (bak != null) {
      return LoadResult(bak, recoveredFrom: RecoverySource.backup);
    }
    return const LoadResult(AppSnapshot(entries: <Entry>[]));
  }

  @override
  Future<void> save(AppSnapshot snapshot) async {
    final file = await _resolve();
    final tmp = File('${file.path}.tmp');
    final bak = File('${file.path}.bak');
    await tmp.writeAsString(json.encode(snapshot.toJson()), flush: true);
    if (await file.exists()) {
      await file.rename(bak.path);
    }
    await tmp.rename(file.path);
  }

  /// 读一个文件并解析，不存在返回 null。
  /// 解析不了的：主文件与 bak 改名成 `.corrupt` 留档，临时文件是半截写入，直接删。
  Future<AppSnapshot?> _read(File file, {bool keepCorrupt = true}) async {
    if (!await file.exists()) return null;
    String raw;
    try {
      raw = await file.readAsString();
    } catch (error) {
      debugPrint('读取 ${file.path} 失败：$error');
      return null;
    }
    // 空文件是没写完的写入，当作不存在，但没必要改名留档。
    if (raw.trim().isEmpty) return null;

    AppSnapshot? snapshot;
    try {
      final decoded = json.decode(raw);
      if (decoded is Map) {
        snapshot = AppSnapshot.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (error) {
      debugPrint('解析 ${file.path} 失败：$error');
    }
    if (snapshot != null) return snapshot;

    if (keepCorrupt) {
      try {
        await file.rename('${file.path}.corrupt');
      } catch (_) {}
    } else {
      await _deleteQuietly(file);
    }
    return null;
  }

  Future<bool> _isOlder(File a, File b) async {
    try {
      final int first = (await a.stat()).modified.microsecondsSinceEpoch;
      final int second = (await b.stat()).modified.microsecondsSinceEpoch;
      return first < second;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// 内存实现，测试与预览用。
class MemoryEntryStorage implements EntryStorage {
  MemoryEntryStorage([this.snapshot = const AppSnapshot(entries: <Entry>[])]);

  AppSnapshot snapshot;
  int saveCount = 0;

  @override
  Future<LoadResult> load() async => LoadResult(snapshot);

  @override
  Future<void> save(AppSnapshot snapshot) async {
    this.snapshot = snapshot;
    saveCount++;
  }
}
