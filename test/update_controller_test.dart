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
/// API 能模拟限流（[apiStatus]），发布页能模拟 302 到某个 tag。
class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter({
    required this.body,
    this.downloadOk = false,
    this.stallDownload = false,
    this.apiStatus = 200,
    this.redirectTag,
    this.redirectStatus = HttpStatus.found,
  });

  final Map<String, dynamic> body;
  final bool downloadOk;
  final bool stallDownload;
  final int apiStatus;
  final String? redirectTag;
  final int redirectStatus;
  final Completer<ResponseBody> _stall = Completer<ResponseBody>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // 接口与发布页都在 /releases/latest 上，按域名区分。
    if (options.uri.host == 'api.github.com') {
      if (apiStatus != HttpStatus.ok) {
        return ResponseBody.fromString(
          jsonEncode(<String, dynamic>{
            'message': 'API rate limit exceeded',
          }),
          apiStatus,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['application/json'],
            'x-ratelimit-reset': <String>[
              '${DateTime.now().add(const Duration(minutes: 9)).millisecondsSinceEpoch ~/ 1000}',
            ],
          },
        );
      }
      // 带 JSON content-type，dio 才会自动反序列化成 Map。
      return ResponseBody.fromString(
        jsonEncode(body),
        HttpStatus.ok,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
        },
      );
    }
    if (options.uri.host == 'github.com') {
      return ResponseBody.fromBytes(
        <int>[],
        redirectStatus,
        headers: <String, List<String>>{
          if (redirectTag != null)
            'location': <String>[
              'https://github.com/fenlyin0420/masonry-todo/releases/tag/$redirectTag',
            ],
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
    return ResponseBody.fromBytes(<int>[1, 2, 3, 4], HttpStatus.ok);
  }

  @override
  void close({bool force = false}) {}
}

/// 每次只给两字节就断连，用来验证失败时保留 `.part` 与可重试。
class _PartialAdapter extends _JsonAdapter {
  _PartialAdapter({required super.body}) : super(apiStatus: HttpStatus.ok);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.host != '127.0.0.1') {
      return super.fetch(options, requestStream, cancelFuture);
    }
    return ResponseBody(_partialThenReset(), HttpStatus.ok);
  }

  /// 先给两字节，再模拟连接被重置。
  Stream<Uint8List> _partialThenReset() async* {
    yield Uint8List.fromList(<int>[1, 2]);
    throw const SocketException('连接被重置');
  }
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
    int attempts = 3,
  }) {
    return UpdateController(
      currentVersion: current,
      abi: abi,
      dio: Dio()..httpClientAdapter = adapter,
      channel: channel,
      downloadAttempts: attempts,
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

  test('startDownload 失败 → failed 并说清原因，不留 .tmp', () async {
    final c = controller(
      _JsonAdapter(body: releaseJson()),
    );
    await c.checkNow(); // available，_pendingAsset 已设好
    await c.startDownload();
    expect(c.state.kind, UpdateStateKind.failed);
    expect(c.state.data, contains('连不上 GitHub'));
    expect(c.userInitiated, isTrue);
    expect(
      dir.listSync().where((entity) => entity.path.endsWith('.tmp')).toList(),
      isEmpty,
    );
  });

  test('接口限流时改用发布页重定向，仍能发现新版本', () async {
    final c = controller(
      _JsonAdapter(
        body: releaseJson(),
        apiStatus: HttpStatus.forbidden,
        redirectTag: 'v1.2.0',
      ),
    );
    await c.checkNow(manual: true);

    expect(c.state.kind, UpdateStateKind.available);
    expect(c.state.release!.tagName, 'v1.2.0');
    expect(
      c.state.asset!.downloadUrl,
      'https://github.com/fenlyin0420/masonry-todo/releases/download/'
      'v1.2.0/masonry-todo-arm64-v8a.apk',
    );
  });

  test('限流且发布页也失败 → 提示限流和恢复时间', () async {
    final c = controller(
      _JsonAdapter(
        body: releaseJson(),
        apiStatus: HttpStatus.forbidden,
        redirectStatus: HttpStatus.internalServerError,
      ),
    );
    await c.checkNow(manual: true);

    expect(c.state.kind, UpdateStateKind.failed);
    expect(c.state.data, contains('限流'));
    expect(c.state.data, contains('分钟后恢复'));
  });

  test('下载中断保留 .part，重试从已有字节续上', () async {
    final c = controller(
      _PartialAdapter(body: releaseJson()),
      attempts: 1,
    );
    await c.checkNow(manual: true);
    await c.startDownload();

    expect(c.state.kind, UpdateStateKind.failed);
    expect(c.canRetryDownload, isTrue);
    final File part = File('${dir.path}/masonry-todo-arm64-v8a.apk.part');
    expect(part.existsSync(), isTrue);
    expect(await part.length(), 2);
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
