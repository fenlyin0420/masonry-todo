import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_todo/update/app_version.dart';
import 'package:masonry_todo/update/github_release.dart';
import 'package:masonry_todo/update/update_controller.dart';
import 'package:masonry_todo/widgets/update_watch.dart';

const MethodChannel _channel = MethodChannel('masonry_todo.updates');

/// 永不完成的 adapter：widget 测试里的下载永远停在 downloading，
/// 状态流转全部由测试手动驱动（dio 在 FakeAsync 区域里跑不通）。
class _StalledAdapter implements HttpClientAdapter {
  final Completer<ResponseBody> _completer = Completer<ResponseBody>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => _completer.future;

  @override
  void close({bool force = false}) {}
}

LatestRelease _release() {
  return LatestRelease.tryParse(<String, dynamic>{
    'tag_name': 'v1.2.0',
    'html_url':
        'https://github.com/fenlyin0420/masonry-todo/releases/tag/v1.2.0',
    'published_at': '2026-10-18T08:00:00Z',
    'assets': [
      <String, dynamic>{
        'name': 'masonry-todo-arm64-v8a.apk',
        'browser_download_url': 'http://127.0.0.1:9/masonry-todo-arm64-v8a.apk',
        'size': 1048576,
      },
    ],
  })!;
}

UpdateController _controller(
  TestDefaultBinaryMessengerBinding binding,
  Map<String, int> calls, {
  bool canInstall = true,
  required Directory dir,
}) {
  binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
    MethodCall call,
  ) async {
    calls[call.method] = (calls[call.method] ?? 0) + 1;
    switch (call.method) {
      case 'getUpdatesDir':
        return dir.path;
      case 'canInstall':
        return canInstall;
      default:
        return null;
    }
  });
  final Dio dio = Dio()..httpClientAdapter = _StalledAdapter();
  return UpdateController(
    currentVersion: const VersionParts(1, 1, 0, -1),
    abi: 'arm64-v8a',
    dio: dio,
    channel: _channel,
  );
}

Widget _app(UpdateController controller) {
  return MaterialApp(
    home: Scaffold(
      body: UpdateWatch(controller: controller, child: const SizedBox.expand()),
    ),
  );
}

Future<UpdateController> _showAvailable(
  WidgetTester tester,
  UpdateController c,
) async {
  final LatestRelease release = _release();
  c.state = UpdateState.available(
    release,
    pickApkForAbi(release, 'arm64-v8a')!,
  );
  await tester.pump();
  return c;
}

void main() {
  testWidgets('发现新版本弹窗；同版本去重；「稍后」清标记可再弹', (WidgetTester tester) async {
    final Map<String, int> calls = <String, int>{};
    final Directory dir = Directory.systemTemp.createTempSync('update_test');
    addTearDown(() async => dir.delete(recursive: true));
    final binding = tester.binding;
    final c = _controller(binding, calls, dir: dir);
    await tester.pumpWidget(_app(c));
    await tester.pump();

    await _showAvailable(tester, c);
    expect(find.text('发现新版本 1.2.0'), findsOneWidget);

    // 同一版本的状态变化被去重拦掉。
    final LatestRelease release = c.state.release!;
    final ReleaseAsset asset = c.state.asset!;
    c.state = UpdateState.available(release, asset);
    await tester.pump();
    expect(find.text('发现新版本 1.2.0'), findsOneWidget);

    await tester.tap(find.text('稍后'));
    await tester.pump();
    expect(find.text('发现新版本 1.2.0'), findsNothing);

    // 「稍后」清掉标记，同版本还能再弹。
    c.state = UpdateState.available(release, asset);
    await tester.pump();
    expect(find.text('发现新版本 1.2.0'), findsOneWidget);
  });

  testWidgets('点「下载更新」真的发起下载（B1 回归）', (WidgetTester tester) async {
    final Map<String, int> calls = <String, int>{};
    final Directory dir = Directory.systemTemp.createTempSync('update_test');
    addTearDown(() async => dir.delete(recursive: true));
    final binding = tester.binding;
    final c = _controller(binding, calls, dir: dir);
    await tester.pumpWidget(_app(c));
    await tester.pump();

    await _showAvailable(tester, c);
    await tester.tap(find.text('下载更新'));
    await tester.pump();

    // 进度框出现 + startDownload 真的被调用（曾经这里根本没接线）。
    expect(find.text('正在下载更新'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(c.state.kind, UpdateStateKind.downloading);
    expect(calls['getUpdatesDir'], isNotNull);
  });

  testWidgets('下载失败时进度弹窗自动关闭并提示重试（M1）', (WidgetTester tester) async {
    final Map<String, int> calls = <String, int>{};
    final Directory dir = Directory.systemTemp.createTempSync('update_test');
    addTearDown(() async => dir.delete(recursive: true));
    final binding = tester.binding;
    final c = _controller(binding, calls, dir: dir);
    await tester.pumpWidget(_app(c));
    await tester.pump();

    await _showAvailable(tester, c);
    await tester.tap(find.text('下载更新'));
    await tester.pump();
    expect(find.text('正在下载更新'), findsOneWidget);

    // 模拟 controller 把状态推到 failed。
    c.state = UpdateState.failed('下载失败，请重试');
    await tester.pumpAndSettle();
    expect(find.text('正在下载更新'), findsNothing);
    expect(find.text('下载失败，请重试'), findsOneWidget);
  });

  testWidgets('ready 时进度弹窗自动关闭并提示打开安装器（M1）', (WidgetTester tester) async {
    final Map<String, int> calls = <String, int>{};
    final Directory dir = Directory.systemTemp.createTempSync('update_test');
    addTearDown(() async => dir.delete(recursive: true));
    final binding = tester.binding;
    final c = _controller(binding, calls, dir: dir);
    await tester.pumpWidget(_app(c));
    await tester.pump();

    await _showAvailable(tester, c);
    await tester.tap(find.text('下载更新'));
    await tester.pump();

    c.state = UpdateState.ready('${dir.path}/masonry-todo-arm64-v8a.apk');
    await tester.pumpAndSettle();
    expect(find.text('正在下载更新'), findsNothing);
    expect(find.text('更新包已下载，正在打开安装器'), findsOneWidget);
  });

  testWidgets('没有安装权限时弹引导弹窗，带「重试」按钮（M6）', (WidgetTester tester) async {
    final Map<String, int> calls = <String, int>{};
    final Directory dir = Directory.systemTemp.createTempSync('update_test');
    addTearDown(() async => dir.delete(recursive: true));
    final binding = tester.binding;
    final c = _controller(binding, calls, canInstall: false, dir: dir);
    await tester.pumpWidget(_app(c));
    await tester.pump();

    await _showAvailable(tester, c);
    await tester.tap(find.text('下载更新'));
    await tester.pump();

    c.state = UpdateState.ready('${dir.path}/masonry-todo-arm64-v8a.apk');
    await tester.pumpAndSettle();
    expect(find.text('需要安装权限'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);
  });
}
