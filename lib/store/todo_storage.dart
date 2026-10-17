import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/todo.dart';

/// 首页展示形态。
enum ViewMode { grid, list }

/// 落盘的一份完整快照：所有 todo + 首页展示形态。
class AppSnapshot {
  const AppSnapshot({required this.todos, this.viewMode = ViewMode.grid});

  final List<Todo> todos;
  final ViewMode viewMode;

  factory AppSnapshot.fromJson(Map<String, dynamic> json) {
    final todos = <Todo>[];
    final rawTodos = json['todos'];
    if (rawTodos is List) {
      for (final raw in rawTodos) {
        if (raw is Map) {
          todos.add(Todo.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
    }
    return AppSnapshot(
      todos: todos,
      viewMode: json['viewMode'] == 'list' ? ViewMode.list : ViewMode.grid,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'viewMode': viewMode == ViewMode.list ? 'list' : 'grid',
        'todos': todos.map((todo) => todo.toJson()).toList(),
      };
}

abstract class TodoStorage {
  Future<AppSnapshot> load();
  Future<void> save(AppSnapshot snapshot);
}

/// JSON 文件存储：写入临时文件再 rename，避免半截文件。
class FileTodoStorage implements TodoStorage {
  FileTodoStorage({Future<Directory> Function()? directoryProvider})
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
        return File('${dir.path}/todos.json');
      }();

  @override
  Future<AppSnapshot> load() async {
    final file = await _resolve();
    if (!await file.exists()) return const AppSnapshot(todos: <Todo>[]);
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const AppSnapshot(todos: <Todo>[]);
      final decoded = json.decode(raw);
      if (decoded is! Map) return const AppSnapshot(todos: <Todo>[]);
      return AppSnapshot.fromJson(Map<String, dynamic>.from(decoded));
    } catch (error) {
      debugPrint('读取 todos.json 失败：$error');
      // 坏文件留个备份，别让下一次保存把它悄悄覆盖掉。
      try {
        await file.rename('${file.path}.corrupt');
      } catch (_) {}
      return const AppSnapshot(todos: <Todo>[]);
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
class MemoryTodoStorage implements TodoStorage {
  MemoryTodoStorage([this.snapshot = const AppSnapshot(todos: <Todo>[])]);

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
