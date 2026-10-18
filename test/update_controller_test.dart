import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_todo/update/app_version.dart';
import 'package:masonry_todo/update/update_controller.dart';

const MethodChannel channel = MethodChannel('masonry_todo.updates');

Map<String, dynamic> releaseJson({
  String tag = 'v1.2.0',
  List<String> assetNames = const ['masonry-todo-arm64-v8a.apk'],
}) {
  return <String, dynamic>{
    'tag_name': tag,
    'html_url': 'https://github.com/fenlyin0420/masonry-todo/releases/tag/$tag',
    'published_at': '2026-10-18T08:00:00Z',
    'assets': [
      for (final String name in assetNames)
        <String, dynamic>{
          'name': name,
          'browser_download_url': 'http://127.0.0.1:9/$name',
          'size': 4,
        },
    ],
  };
}

/// Releases API 返回 [body]；APK 下载 URL 按配置成功/失败/卡住。
class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter({
    required this.body,
    this.downloadOk = false,
    this.stallDownload = false,
  });

  final Map<String, dynamic> body;
  final bool downloadOk;
  final bool stallDownload;
  final Completer<ResponseBody> _stall = Completer<ResponseBody>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path.endsWith('/releases/latest')) {
      // 带 JSON content-type，dio 才会自动反序列化成 Map。
      return ResponseBody.fromString(
        jsonEncode(body),
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    if (stallDownload) return _stall.future;
    if (!downloadOk) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromBytes(<int>[1, 2, 3, 4], 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('update_ctrl_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          switch (call.method) {
            case 'getUpdatesDir':
              return dir.path;
            case 'canInstall':
              return true;
            default:
              return null;
          }
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await dir.delete(recursive: true);
  });

  UpdateController controller(
    _JsonAdapter adapter, {
    String? abi = 'arm64-v8a',
    VersionParts current = const VersionParts(1, 1, 0, -1),
  }) {
    return UpdateController(
      currentVersion: current,
      abi: abi,
      dio: Dio()..httpClientAdapter = adapter,
      channel: channel,
    );
  }

  test('checkNow 发现新版本 → available 并选中匹配的包', () async {
    final c = controller(_JsonAdapter(body: releaseJson()));
    await c.checkNow();
    expect(c.state.kind, UpdateStateKind.available);
    expect(c.state.asset!.name, 'masonry-todo-arm64-v8a.apk');
    expect(c.currentVersionString, '1.1.0');
  });

  test('checkNow 版本不新 → upToDate', () async {
    final c = controller(_JsonAdapter(body: releaseJson(tag: 'v1.1.0')));
    await c.checkNow();
    expect(c.state.kind, UpdateStateKind.upToDate);
  });

  test('checkNow 已知架构不在多包里 → failed', () async {
    final c = controller(
      _JsonAdapter(
        body: releaseJson(
          assetNames: const [
            'masonry-todo-arm64-v8a.apk',
            'masonry-todo-armeabi-v7a.apk',
          ],
        ),
      ),
      abi: 'x86_64',
    );
    await c.checkNow();
    expect(c.state.kind, UpdateStateKind.failed);
    expect(c.state.data, '这个 Release 上没有可用的 APK');
  });

  test('startDownload 成功 → ready，文件落盘，旧包被清掉', () async {
    await File('${dir.path}/stale.apk').writeAsString('old');
    final c = controller(_JsonAdapter(body: releaseJson(), downloadOk: true));
    await c.checkNow(); // available，_pendingAsset 已设好
    await c.startDownload();
    expect(c.state.kind, UpdateStateKind.ready);
    expect(c.pendingApkPath, '${dir.path}/masonry-todo-arm64-v8a.apk');
    final File file = File(c.pendingApkPath!);
    expect(await file.readAsBytes(), <int>[1, 2, 3, 4]);
    expect(File('${dir.path}/stale.apk').existsSync(), isFalse);
  });

  test('startDownload 失败 → failed，不留临时文件', () async {
    final c = controller(_JsonAdapter(body: releaseJson()));
    await c.checkNow(); // available，_pendingAsset 已设好
    await c.startDownload();
    expect(c.state.kind, UpdateStateKind.failed);
    expect(c.state.data, '下载失败，请重试');
    expect(c.userInitiated, isTrue);
    expect(
      dir.listSync().where((entity) => entity.path.endsWith('.tmp')).toList(),
      isEmpty,
    );
  });

  test('cancelDownload → 回到 idle 而不是 failed', () async {
    final c = controller(
      _JsonAdapter(body: releaseJson(), stallDownload: true),
    );
    await c.checkNow(); // available，_pendingAsset 已设好
    final Future<void> downloading = c.startDownload();
    // 给下载一点时间走到 dio，再取消。
    await Future<void>.delayed(const Duration(milliseconds: 50));
    c.cancelDownload();
    await downloading;
    expect(c.state.kind, UpdateStateKind.idle);
  });

  test('openInstallSettings 吞掉 PlatformException', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          if (call.method == 'openInstallSettings') {
            throw PlatformException(code: 'NO_PAGE');
          }
          return null;
        });
    final c = controller(_JsonAdapter(body: releaseJson()));
    await c.openInstallSettings(); // 不抛异常即通过
  });
}
