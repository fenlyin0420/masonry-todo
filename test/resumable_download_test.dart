import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_todo/update/resumable_download.dart';

void main() {
  late _AbortServer server;
  late Directory dir;
  late Uint8List payload;
  late Dio dio;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('masonry_resume_test');
    // 内容做成不可压缩的花样，拼错位置能立刻看出来。
    payload = Uint8List.fromList(
      List<int>.generate(320 * 1024, (int index) => (index % 251) + 1),
    );
    server = _AbortServer(payload);
    dio = Dio();
  });

  tearDown(() async {
    dio.close();
    await server.stop();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  File target() => File('${dir.path}/masonry-todo-arm64-v8a.apk');

  ResumableDownloader downloader({int attempts = 3}) => ResumableDownloader(
    dio: dio,
    maxAttempts: attempts,
    stallTimeout: const Duration(milliseconds: 400),
  );

  test('断线后自动续传，最终文件与源一致', () async {
    await server.start(abortAfter: 64 * 1024);
    final List<double> progress = <double>[];

    final DownloadResult result = await downloader().fetch(
      url: server.url,
      target: target(),
      expectedBytes: payload.length,
      onProgress: (int received, int? total) =>
          progress.add(received / (total ?? payload.length)),
    );

    expect(result.bytes, payload.length);
    expect(await target().readAsBytes(), payload);
    expect(File('${target().path}.part').existsSync(), isFalse);
    expect(server.rangeRequests, greaterThan(0));
    // 进度必须一路向前，不能因为重试回到 0。
    for (int i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
    }
  });

  test('服务器不认 Range 时从头下，不会把两段拼坏', () async {
    await server.start(abortAfter: 64 * 1024, ignoreRange: true);

    final DownloadResult result = await downloader().fetch(
      url: server.url,
      target: target(),
      expectedBytes: payload.length,
    );

    expect(result.bytes, payload.length);
    expect(await target().readAsBytes(), payload);
  });

  test('取消会保留 .part，下一次接着下', () async {
    // 慢一点，好在下载中途取消（全部下完要 10 块 × 50ms）。
    await server.start(chunkDelayMs: 50);
    final CancelToken token = CancelToken();

    final Future<DownloadResult> running = downloader().fetch(
      url: server.url,
      target: target(),
      expectedBytes: payload.length,
      cancelToken: token,
    );
    await Future<void>.delayed(const Duration(milliseconds: 130));
    token.cancel();

    await expectLater(
      running,
      throwsA(
        isA<DioException>().having(
          (DioException error) => error.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );

    final File part = File('${target().path}.part');
    expect(part.existsSync(), isTrue);
    final int partial = await part.length();
    expect(partial, greaterThan(0));
    expect(partial, lessThan(payload.length));
  });

  test('已有半截文件时从那个位置继续请求', () async {
    await server.start();
    final File part = File('${target().path}.part');
    await part.writeAsBytes(payload.sublist(0, 100 * 1024), flush: true);

    final DownloadResult result = await downloader().fetch(
      url: server.url,
      target: target(),
      expectedBytes: payload.length,
    );

    expect(result.bytes, payload.length);
    expect(await target().readAsBytes(), payload);
    expect(server.rangeRequests, 1);
  });

  test('连接卡住不报错时，看门狗会掐断并重试', () async {
    // 第一次请求只发一小段就装死，不发 FIN 也不报错。
    await server.start(stallAfter: 32 * 1024, stallFor: const Duration(seconds: 5));

    final DownloadResult result = await downloader().fetch(
      url: server.url,
      target: target(),
      expectedBytes: payload.length,
    );

    expect(result.bytes, payload.length);
    expect(await target().readAsBytes(), payload);
  });

  test('重试用尽后抛出，并保留 .part', () async {
    await server.start(abortAfter: 32 * 1024, alwaysAbort: true);

    await expectLater(
      downloader(attempts: 2).fetch(
        url: server.url,
        target: target(),
        expectedBytes: payload.length,
      ),
      throwsA(isA<DioException>()),
    );
    final File part = File('${target().path}.part');
    expect(part.existsSync(), isTrue);
    expect(await part.length(), greaterThan(0));
  });
}

/// 手写 HTTP 服务端：能按需断线、装死、忽略 Range。
/// 用 [ServerSocket] 而不是 `HttpServer`，才能精确控制何时掐掉连接。
class _AbortServer {
  _AbortServer(this.payload);

  final Uint8List payload;
  ServerSocket? _socket;
  bool _aborted = false;
  int rangeRequests = 0;

  Future<void> start({
    int? abortAfter,
    bool alwaysAbort = false,
    bool ignoreRange = false,
    int chunkDelayMs = 0,
    int? stallAfter,
    Duration? stallFor,
  }) async {
    _socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _socket!.listen((Socket client) {
      final List<int> buffer = <int>[];
      bool handled = false;
      client.listen(
        (Uint8List data) {
          if (handled) return;
          buffer.addAll(data);
          if (!String.fromCharCodes(buffer).contains('\r\n\r\n')) return;
          handled = true;
          _respond(
            client,
            String.fromCharCodes(buffer),
            abortAfter: abortAfter,
            alwaysAbort: alwaysAbort,
            ignoreRange: ignoreRange,
            chunkDelayMs: chunkDelayMs,
            stallAfter: stallAfter,
            stallFor: stallFor,
          );
        },
        onError: (_) {},
        cancelOnError: true,
      );
    });
  }

  String get url => 'http://127.0.0.1:${_socket!.port}/app.apk';

  Future<void> stop() async {
    await _socket?.close();
    _socket = null;
  }

  Future<void> _respond(
    Socket client,
    String request, {
    int? abortAfter,
    bool alwaysAbort = false,
    bool ignoreRange = false,
    int chunkDelayMs = 0,
    int? stallAfter,
    Duration? stallFor,
  }) async {
    int start = 0;
    if (!ignoreRange) {
      final RegExpMatch? match = RegExp(
        r'range:\s*bytes=(\d+)-',
        caseSensitive: false,
      ).firstMatch(request);
      if (match != null) start = int.parse(match.group(1)!);
    }
    if (start > 0) rangeRequests++;

    final StringBuffer head = StringBuffer()
      ..write(
        start > 0
            ? 'HTTP/1.1 206 Partial Content\r\n'
            : 'HTTP/1.1 200 OK\r\n',
      )
      ..write('content-length: ${payload.length - start}\r\n')
      ..write('connection: close\r\n')
      ..write('accept-ranges: bytes\r\n');
    if (start > 0) {
      head.write(
        'content-range: bytes $start-${payload.length - 1}/${payload.length}\r\n',
      );
    }
    head.write('\r\n');

    try {
      client.add(head.toString().codeUnits);
      await client.flush();

      if (stallAfter != null && !_aborted) {
        _aborted = true;
        client.add(payload.sublist(start, start + stallAfter));
        await client.flush();
        // 装死：不关 socket、不再发数据，模拟网络被黑洞。
        await Future<void>.delayed(stallFor ?? const Duration(seconds: 3));
        client.destroy();
        return;
      }

      const int chunk = 32 * 1024;
      int sent = 0;
      for (int offset = start; offset < payload.length; offset += chunk) {
        if (abortAfter != null &&
            sent >= abortAfter &&
            (alwaysAbort || !_aborted)) {
          _aborted = true;
          await client.flush();
          client.destroy();
          return;
        }
        final int end = min(offset + chunk, payload.length);
        client.add(payload.sublist(offset, end));
        sent += end - offset;
        await client.flush();
        if (chunkDelayMs > 0) {
          await Future<void>.delayed(Duration(milliseconds: chunkDelayMs));
        }
      }
      await client.flush();
      await client.close();
    } catch (_) {
      client.destroy();
    }
  }
}
