import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 下载结果：最终字节数与服务器声明的总大小（未知为 null）。
class DownloadResult {
  const DownloadResult({required this.bytes, this.totalBytes});

  final int bytes;
  final int? totalBytes;
}

/// 支持断点续传的下载器。
///
/// 下载过程写 `*.part`，失败或取消都不删：下一次 [fetch] 会用 `Range` 从已有
/// 字节接着下。服务器不认 Range（回 200）时清空重下，不会把新旧字节拼在一起；
/// 断线这类可重试的错误会自动重试，每轮都重新续上。
class ResumableDownloader {
  ResumableDownloader({
    required Dio dio,
    this.maxAttempts = 3,
    this.stallTimeout = const Duration(seconds: 30),
  }) : _dio = dio;

  final Dio _dio;

  /// 最多试几次；只有网络类错误会重试，HTTP 4xx 直接失败。
  final int maxAttempts;

  /// 多久没收到新字节就当连接已经死了。
  /// 掐断的连接在 dio 里可能一直不报错也不结束，没这个看门狗会永远卡在进度条上。
  final Duration stallTimeout;

  Future<DownloadResult> fetch({
    required String url,
    required File target,
    int? expectedBytes,
    CancelToken? cancelToken,
    void Function(int received, int? total)? onProgress,
  }) async {
    final File part = File('${target.path}.part');
    int have = await _length(part);
    // 上次下到一半但目标文件已经不完整，说明服务器换了包：重新开始。
    if (expectedBytes != null && have > expectedBytes) {
      await _delete(part);
      have = 0;
    }

    Object? lastError;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final _Transfer transfer = await _transfer(
          url: url,
          part: part,
          have: have,
          fallbackTotal: expectedBytes,
          cancelToken: cancelToken,
          onProgress: onProgress,
        );
        have = transfer.received;
        final int? total = transfer.total ?? expectedBytes;
        if (!transfer.finished || (total != null && have < total)) {
          throw DioException(
            requestOptions: RequestOptions(path: url),
            type: DioExceptionType.receiveTimeout,
            error: total == null ? '连接提前断开' : '连接提前断开（$have/$total）',
          );
        }
        await _delete(target);
        await part.rename(target.path);
        return DownloadResult(bytes: have, totalBytes: total);
      } on Object catch (error) {
        final DioException dioError = error is DioException
            ? error
            : DioException(
                requestOptions: RequestOptions(path: url),
                type: DioExceptionType.connectionError,
                error: error,
              );
        if (dioError.type == DioExceptionType.cancel) rethrow;
        lastError = dioError;
        have = await _length(part);
        if (attempt == maxAttempts || !_retryable(dioError)) break;
        debugPrint('下载中断，$attempt 次重试前从 $have 字节续传');
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        if (cancelToken?.isCancelled ?? false) rethrow;
      }
    }
    throw lastError ?? DioException(requestOptions: RequestOptions(path: url));
  }

  /// 4xx 是确定答案，重试没意义；超时、断连、5xx 才值得再试。
  bool _retryable(DioException error) {
    final int? status = error.response?.statusCode;
    if (status != null) return status >= 500 || status == 408 || status == 429;
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError ||
      DioExceptionType.unknown => true,
      _ => false,
    };
  }

  Future<_Transfer> _transfer({
    required String url,
    required File part,
    required int have,
    required int? fallbackTotal,
    CancelToken? cancelToken,
    void Function(int received, int? total)? onProgress,
  }) async {
    final Response<ResponseBody> response = await _dio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        receiveTimeout: const Duration(seconds: 30),
        headers: have > 0
            ? <String, Object>{'range': 'bytes=$have-'}
            : null,
        validateStatus: (int? status) =>
            status == 200 || status == 206 || status == 416,
      ),
    );

    final int status = response.statusCode ?? 0;
    if (status == 416) {
      // 断点已经到头：这份 .part 就是完整的。
      return _Transfer(received: have, total: have, finished: true);
    }

    final bool appending = status == 206 && have > 0;
    final int offset = appending ? have : 0;
    final int? total = _totalOf(response, offset) ?? fallbackTotal;
    final ResponseBody body = response.data!;

    final RandomAccessFile handle = await part.open(
      mode: appending ? FileMode.append : FileMode.write,
    );
    int received = offset;
    bool finished = false;
    try {
      // 没数据超过 [stallTimeout] 就当这轮残了：抛 TimeoutException → 外层重试并续传。
      final Stream<Uint8List> chunks = body.stream.timeout(
        stallTimeout,
        onTimeout: (EventSink<Uint8List> sink) {
          sink.addError(TimeoutException('下载卡住了', stallTimeout));
          sink.close();
        },
      );
      await for (final Uint8List chunk in chunks) {
        await handle.writeFrom(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      finished = true;
    } finally {
      await handle.close();
    }
    return _Transfer(received: received, total: total, finished: finished);
  }

  /// 总大小：优先 `content-range: bytes 100-999/1000` 的分母，其次 content-length。
  int? _totalOf(Response<ResponseBody> response, int offset) {
    final String? range = response.headers.value('content-range');
    if (range != null) {
      final int slash = range.lastIndexOf('/');
      if (slash >= 0) {
        final int? total = int.tryParse(range.substring(slash + 1).trim());
        if (total != null) return total;
      }
    }
    final int? length = response.data?.contentLength;
    if (length != null && length >= 0) return offset + length;
    return null;
  }

  Future<int> _length(File file) async {
    try {
      return await file.exists() ? await file.length() : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

class _Transfer {
  const _Transfer({
    required this.received,
    required this.total,
    required this.finished,
  });

  final int received;
  final int? total;

  /// 数据流是否干净地读到了结尾（不是被 RST 掐断）。
  final bool finished;
}
