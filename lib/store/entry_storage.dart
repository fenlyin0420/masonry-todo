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

abstract class EntryStorage {
  Future<AppSnapshot> load();
  Future<void> save(AppSnapshot snapshot);
}

/// JSON 文件存储：写入临时文件再 rename，避免半截文件。
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
  Future<AppSnapshot> load() async {
    final file = await _resolve();
    if (!await file.exists()) return const AppSnapshot(entries: <Entry>[]);
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const AppSnapshot(entries: <Entry>[]);
      final decoded = json.decode(raw);
      if (decoded is! Map) return const AppSnapshot(entries: <Entry>[]);
      return AppSnapshot.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      debugPrint('读取 todos.json 失败：$error');
      // 坏文件留个备份，别让下一次保存把它悄悄覆盖掉。
      try {
        await file.rename('${file.path}.corrupt');
      } catch (_) {}
      return const AppSnapshot(entries: <Entry>[]);
    }
  }

  @override
  Future<void> save(AppSnapshot snapshot) async {
    final file = await _resolve();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(json.encode(snapshot.toJson()), flush: true);
    await tmp.rename(file.path);
  }
}

/// 内存实现，测试与预览用。
class MemoryEntryStorage implements EntryStorage {
  MemoryEntryStorage([this.snapshot = const AppSnapshot(entries: <Entry>[])]);

  AppSnapshot snapshot;
  int saveCount = 0;

  @override
  Future<AppSnapshot> load() async => snapshot;

  @override
  Future<void> save(AppSnapshot snapshot) async {
    this.snapshot = snapshot;
    saveCount++;
  }
}
