import 'dart:io';

import 'package:dio/dio.dart';

/// 把网络 / IO 异常翻成用户能看懂的一句话。
/// 更新失败时最要紧的是「为什么」，所以限流、超时、断连、存储满要分开说。
String updateErrorMessage(Object error) {
  if (error is DioException) {
    final int? status = error.response?.statusCode;
    if (status == 403 || status == 429) {
      return 'GitHub 接口限流了（同一网络每小时 60 次）${_retryAfter(error)}';
    }
    if (status == 404) return '没找到更新包，可能这次发布还没传完';
    if (status != null && status >= 500) {
      return 'GitHub 服务器出错（HTTP $status）';
    }
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return '连接 GitHub 超时，换个网络再试';
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return '连接卡住了，没等到数据，点重试可以接着下';
      case DioExceptionType.connectionError:
        return '连不上 GitHub，检查网络或代理';
      case DioExceptionType.cancel:
        return '已取消';
      case DioExceptionType.badCertificate:
        return 'HTTPS 证书校验失败，可能是网络被劫持';
      case DioExceptionType.badResponse:
        return 'GitHub 返回了异常响应${status == null ? '' : '（HTTP $status）'}';
      case DioExceptionType.unknown:
        break;
    }
    final Object? detail = error.error;
    if (detail is SocketException) return '连不上 GitHub：${detail.message}';
    if (detail != null) return '下载失败：$detail';
    return '下载失败，请重试';
  }
  if (error is FileSystemException) {
    return '写不进手机存储，检查剩余空间';
  }
  if (error is FormatException) {
    return 'GitHub 的返回看不懂，稍后再试';
  }
  return '更新失败：$error';
}

/// 限流恢复时间：优先用 `x-ratelimit-reset` 的秒级时间戳。
String _retryAfter(DioException error) {
  final Headers? headers = error.response?.headers;
  final String? raw = headers?.value('x-ratelimit-reset');
  final int? epoch = int.tryParse(raw ?? '');
  if (epoch == null) return '，过一会儿再试';
  final DateTime reset = DateTime.fromMillisecondsSinceEpoch(
    epoch * 1000,
  ).toLocal();
  final Duration wait = reset.difference(DateTime.now());
  if (wait.isNegative) return '，已经恢复，重试即可';
  final int minutes = (wait.inSeconds / 60).ceil();
  return '，约 $minutes 分钟后恢复';
}
