import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'models/entry.dart';
import 'store/backup.dart';
import 'store/entry_storage.dart';
import 'store/entry_store.dart';
import 'store/note_image_store.dart';
import 'widgets/store_scope.dart';

/// 导出备份：把条目与楼层图片打成一个 `.json`，交给系统文件对话框存到用户
/// 自己挑的位置（下载、网盘目录等）。这是唯一能扛过卸载、换机、清数据的出路。
Future<void> exportBackup(BuildContext context) async {
  final EntryStore store = StoreScope.of(context);
  final NoteImageStore images = NoteImageStore();

  BackupExport? backup;
  bool saved = false;
  try {
    final (BackupExport, bool) run = await _runBusy(
      context,
      '正在打包备份…',
      () async {
        await store.flush();
        final BackupExport bundle = await encodeBackup(
          AppSnapshot(
            entries: store.entries,
            viewMode: store.viewMode,
            kind: store.kind,
          ),
          images,
          appVersion: await _appVersion(),
        );
        final Uri? target = await FilePicker.saveFile(
          dialogTitle: '导出备份',
          fileName: _backupFileName(),
          mimeType: 'application/json',
          bytes: Uint8List.fromList(utf8.encode(bundle.text)),
        );
        return (bundle, target != null);
      },
    );
    backup = run.$1;
    // 用户在系统对话框里取消了。
    saved = run.$2;
  } catch (error) {
    debugPrint('导出备份失败：$error');
    if (context.mounted) _snack(context, '导出失败，换个大点的地方再试');
    return;
  }
  if (!saved || !context.mounted) return;
  _snack(context, _exportSummary(backup));
}

String _exportSummary(BackupExport backup) {
  if (backup.missingImages.isNotEmpty) {
    return '备份已保存，但有 ${backup.missingImages.length} 张图片在原机上找不到，没进备份';
  }
  if (backup.imageCount == 0) return '备份已保存';
  return '备份已保存，含 ${backup.imageCount} 张图片';
}

/// 导入备份：先落图片再合并条目，避免条目引用了不存在的图。
/// 合并规则见 [EntryStore.mergeImported]：本地有的条目不覆盖、只补齐。
Future<void> importBackup(BuildContext context) async {
  final EntryStore store = StoreScope.of(context);

  final BackupBundle bundle;
  try {
    final PlatformFile? picked = await FilePicker.pickFile(
      dialogTitle: '选择备份文件',
    );
    if (picked == null) return;
    final Uint8List bytes = await picked.readAsBytes();
    if (!context.mounted) return;
    bundle = await _runBusy(
      context,
      '正在读取备份…',
      () async => decodeBackup(utf8.decode(bytes, allowMalformed: true)),
    );
  } on FormatException catch (error) {
    if (context.mounted) _snack(context, error.message);
    return;
  } catch (error) {
    debugPrint('读取备份失败：$error');
    if (context.mounted) _snack(context, '读不了这个文件，换一个试试');
    return;
  }

  if (!context.mounted) return;
  if (bundle.entryCount == 0) {
    _snack(context, '这个备份里没有条目');
    return;
  }

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('导入备份'),
      content: Text(
        '备份里有 ${bundle.entryCount} 条记录'
        '${bundle.imageCount == 0 ? '' : '、${bundle.imageCount} 张图片'}。\n'
        '手机上没有的会补上；已有的条目以手机为准，只补齐缺的楼层。',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('导入'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final ImportOutcome outcome;
  int missingImages = 0;
  try {
    final ImportRun run = await _runBusy(context, '正在导入…', () async {
      final NoteImageStore images = NoteImageStore();
      for (final MapEntry<String, Uint8List> image in bundle.images.entries) {
        await images.restore(image.key, image.value);
      }
      final ImportOutcome result = store.mergeImported(bundle.snapshot.entries);
      await store.flush();
      // 备份里本来就没带的图（导出时那台机器上已经丢了）真实丢了几张。
      int missing = 0;
      for (final String name in _referencedImages(bundle.snapshot)) {
        if (await images.exists(name)) continue;
        missing++;
      }
      return ImportRun(outcome: result, missingImages: missing);
    });
    outcome = run.outcome;
    missingImages = run.missingImages;
  } catch (error) {
    debugPrint('导入备份失败：$error');
    if (context.mounted) _snack(context, '导入没走完，有些内容可能没进来');
    return;
  }
  if (context.mounted) {
    _snack(context, _summary(outcome, missingImages: missingImages));
  }
}

/// 导入结果与这次缺了多少张图。
class ImportRun {
  const ImportRun({required this.outcome, this.missingImages = 0});

  final ImportOutcome outcome;
  final int missingImages;
}

/// 快照里被楼层引用到的图片文件名。
Set<String> _referencedImages(AppSnapshot snapshot) {
  final Set<String> names = <String>{};
  for (final Entry entry in snapshot.entries) {
    for (final Note note in entry.notes) {
      final String? name = note.image;
      if (name != null) names.add(name);
    }
  }
  return names;
}

String _summary(ImportOutcome outcome, {int missingImages = 0}) {
  final List<String> parts = <String>[
    if (outcome.addedEntries > 0) '导入 ${outcome.addedEntries} 条',
    if (outcome.addedNotes > 0) '补齐 ${outcome.addedNotes} 层记录',
    if (outcome.updatedEntries > 0) '更新 ${outcome.updatedEntries} 条状态',
  ];
  final String head = parts.isEmpty ? '备份里的内容手机上都已有' : '已${parts.join('，')}';
  if (missingImages == 0) return head;
  return '$head；有 $missingImages 张图片在备份里没有数据';
}

String _backupFileName([DateTime? now]) {
  final DateTime time = now ?? DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return 'shiji-backup-${time.year}${two(time.month)}${two(time.day)}'
      '-${two(time.hour)}${two(time.minute)}.json';
}

Future<String?> _appVersion() async {
  try {
    final PackageInfo info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  } catch (_) {
    return null;
  }
}

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
}

/// 跑一段可能要几秒的活，期间挡一层不可关闭的「正在…」，做完自动收起。
Future<T> _runBusy<T>(
  BuildContext context,
  String label,
  Future<T> Function() action,
) async {
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
  final Completer<void> closed = Completer<void>();
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext inner) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: <Widget>[
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(label)),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      if (!closed.isCompleted) closed.complete();
    }),
  );
  try {
    return await action();
  } finally {
    if (!closed.isCompleted) {
      if (navigator.mounted) navigator.pop();
      await closed.future;
    }
  }
}
