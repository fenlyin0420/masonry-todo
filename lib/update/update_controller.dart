import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_version.dart';
import 'github_release.dart';
import 'resumable_download.dart';
import 'update_errors.dart';

/// 自动更新状态机。只在 Android 上启用（发布渠道只有 Android APK）。
///
/// 检查：[checkNow] 拉取 GitHub Releases 的 latest release，
/// 与当前版本比较；发现新版本则进入 [UpdateStateKind.available]。
/// 下载：[startDownload] 用 dio 流式写到临时文件，进度经
/// [downloadProgress]（0..1）逐帧通知；完成后进入 [UpdateStateKind.ready]，
/// 由 [install] 唤起系统安装器。
class UpdateController extends ChangeNotifier {
  UpdateController({
    required VersionParts currentVersion,
    String? abi,
    Dio? dio,
    MethodChannel? channel,
    String repo = 'fenlyin0420/masonry-todo',
    this.downloadAttempts = 3,
  }) : _currentVersion = currentVersion,
       _abi = abi,
       _dio = dio ?? Dio(),
       _ownsDio = dio == null,
       _channel = channel ?? const MethodChannel('masonry_todo.updates'),
       _repo = repo {
    _downloader = ResumableDownloader(dio: _dio, maxAttempts: downloadAttempts);
  }

  static const String apiBase = 'https://api.github.com';
  static const String webBase = 'https://github.com';

  /// 自动检查的最小间隔，免得反复启动反复打 GitHub 接口（未认证每小时只有 60 次）。
  static const Duration autoCheckInterval = Duration(minutes: 3);

  final VersionParts _currentVersion;
  final String? _abi;
  final Dio _dio;
  final bool _ownsDio;
  final MethodChannel _channel;
  final String _repo;

  /// 单次下载最多试几次，每轮都从已有 `.part` 续传。
  final int downloadAttempts;

  late final ResumableDownloader _downloader;
  DateTime? _lastCheckAt;

  UpdateState _state = UpdateState.idle();

  /// 当前状态；赋值会自动通知监听者，别漏通知。
  UpdateState get state => _state;

  set state(UpdateState value) {
    _state = value;
    _notify();
  }

  double downloadProgress = 0;

  /// 当前版本串，展示用。只取三段：split-per-abi 的 versionCode
  /// 会被 Flutter 加上 ABI 偏移（arm64 机型是 1000+build），展示会失真。
  String get currentVersionString =>
      '${_currentVersion.major}.${_currentVersion.minor}.${_currentVersion.patch}';

  /// 已下载好、等待安装的 APK 路径（未下载为 null）。
  String? get pendingApkPath => _pendingApkPath;

  /// 最近一次状态变化是否由用户主动触发（检查或下载）。
  /// 启动时的自动检查保持安静，用户操作则正常提示。
  bool userInitiated = false;

  /// 最近一次检查是否手动触发；手动检查时，
  /// 同一版本的「发现新版本」弹窗不再被去重拦掉。
  bool manualCheck = false;

  ReleaseAsset? _pendingAsset;
  String? _pendingApkPath;
  CancelToken? _downloadToken;

  /// 检查 GitHub 上的最新版本。失败不抛异常，进入 failed 状态。
  /// [manual] 标记是否用户主动触发，影响失败/最新提示的展示。
  Future<void> checkNow({bool manual = false}) async {
    // 启动时的自动检查在短时间内只做一次，省下接口额度给手动检查。
    final DateTime? last = _lastCheckAt;
    if (!manual &&
        last != null &&
        DateTime.now().difference(last) < autoCheckInterval) {
      return;
    }
    _lastCheckAt = DateTime.now();
    userInitiated = manual;
    manualCheck = manual;
    _pendingAsset = null;
    _pendingApkPath = null;
    state = UpdateState.checking();
    try {
      final LatestRelease release = await _fetchLatestRelease();
      final VersionParts? version = release.version;
      if (version == null) {
        state = UpdateState.failed('没读到可用的 Release');
        return;
      }
      if (!isReleaseNewer(version, _currentVersion)) {
        state = UpdateState.upToDate();
        return;
      }
      final ReleaseAsset? apk = pickApkForAbi(release, _abi);
      if (apk == null) {
        state = UpdateState.failed('这个 Release 上没有可用的 APK');
        return;
      }
      _pendingAsset = apk;
      state = UpdateState.available(release, apk);
    } catch (error) {
      debugPrint('检查更新失败：$error');
      state = UpdateState.failed(updateErrorMessage(error));
    }
  }

  /// 先问 API；被限流、连不上或返回看不懂时，改用发布页的重定向地址，
  /// 那条路不消耗接口额度，也能拿到版本号。
  Future<LatestRelease> _fetchLatestRelease() async {
    Object? apiError;
    try {
      return await _fetchLatestReleaseJson();
    } catch (error) {
      apiError = error;
      debugPrint('GitHub 接口检查失败（$error），改用发布页重定向');
      if (error is DioException &&
          error.type == DioExceptionType.cancel) {
        rethrow;
      }
    }
    try {
      return await _fetchFromReleasePage();
    } catch (error) {
      debugPrint('发布页检查也失败：$error');
      throw apiError;
    }
  }

  Future<LatestRelease> _fetchLatestReleaseJson() async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '$apiBase/repos/$_repo/releases/latest',
      options: Options(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        headers: <String, Object>{'accept': 'application/vnd.github+json'},
      ),
    );
    final Object? data = response.data;
    if (data is! Map) throw const FormatException('Release 响应格式不对');
    final LatestRelease? release = LatestRelease.tryParse(
      Map<String, dynamic>.from(data),
    );
    if (release == null) throw const FormatException('Release 响应格式不对');
    return release;
  }

  /// `GET https://github.com/<repo>/releases/latest` 会 302 到 `/tag/vX.Y.Z`。
  /// 拿到 tag 后按命名约定拼下载地址：`releases/download/<tag>/<asset>`。
  Future<LatestRelease> _fetchFromReleasePage() async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '$webBase/$_repo/releases/latest',
      options: Options(
        followRedirects: false,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        validateStatus: (int? status) =>
            status != null && status >= 200 && status < 400,
      ),
    );
    final String? tag =
        tagFromPath(response.headers.value('location')) ??
        tagFromPath(response.realUri.toString());
    if (tag == null) throw const FormatException('发布页没给出 tag');

    final List<ReleaseAsset> assets = <ReleaseAsset>[];
    final String? abi = _abi;
    if (abi != null) {
      final String name = 'masonry-todo-$abi.apk';
      assets.add(
        ReleaseAsset(
          name: name,
          downloadUrl: '$webBase/$_repo/releases/download/$tag/$name',
        ),
      );
    }
    return LatestRelease(
      tagName: tag,
      htmlUrl: '$webBase/$_repo/releases/tag/$tag',
      assets: assets,
    );
  }

  /// 从 `.../releases/tag/v1.4.0` 里取出 `v1.4.0`。
  static String? tagFromPath(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final Uri? uri = Uri.tryParse(raw);
    if (uri == null) return null;
    final List<String> segments = uri.pathSegments;
    final int index = segments.lastIndexOf('tag');
    if (index < 0 || index + 1 >= segments.length) return null;
    final String tag = segments[index + 1];
    return tag.isEmpty ? null : tag;
  }

  /// 下载已发现的新版 APK。进度写入 [downloadProgress] 并通知。
  /// 完成进入 ready 状态；失败进入 failed；用户取消回到 idle。
  Future<void> startDownload() async {
    // 正常路径下 _pendingAsset 由 checkNow 设好；
    // 回退到 state 里的 asset，让外部驱动状态的调用方也能触发下载。
    final ReleaseAsset? asset = _pendingAsset ?? state.asset;
    if (asset == null) return;
    userInitiated = true;
    state = UpdateState.downloading();
    downloadProgress = 0;
    _notify();
    _downloadToken = CancelToken();
    try {
      final String? dir = await _channel.invokeMethod<String>('getUpdatesDir');
      if (dir == null) {
        throw PlatformException(code: 'NO_DIR', message: '没有下载目录');
      }
      final String name = asset.name.substring(asset.name.lastIndexOf('/') + 1);
      final String finalPath = '$dir/$name';
      // 只清与当前包无关的残留，当前包的 `.part` 留着续传。
      await _sweepDir(dir, keepName: name);
      final DownloadResult result = await _downloader.fetch(
        url: asset.downloadUrl,
        target: File(finalPath),
        expectedBytes: asset.sizeBytes,
        cancelToken: _downloadToken,
        onProgress: (int received, int? total) {
          final int? size = total ?? asset.sizeBytes;
          if (size == null || size <= 0) return;
          final double value = (received / size).clamp(0.0, 1.0);
          if (value == downloadProgress) return;
          downloadProgress = value;
          _notify();
        },
      );
      _pendingApkPath = finalPath;
      downloadProgress = 1;
      state = UpdateState.ready(finalPath);
      debugPrint('更新包已就绪：$finalPath（${result.bytes} 字节）');
    } catch (error) {
      final bool cancelled =
          error is DioException && error.type == DioExceptionType.cancel;
      debugPrint(cancelled ? '取消下载更新' : '下载更新失败：$error');
      // 取消或失败都保留 `.part`，下次接着下。
      state = cancelled
          ? UpdateState.idle()
          : UpdateState.failed(updateErrorMessage(error));
    } finally {
      _downloadToken = null;
    }
  }

  /// 已发现但还没下的包；失败后重试要用它。
  bool get canRetryDownload => _pendingAsset != null;

  /// 下载失败后重试：沿用上次选中的包，从 `.part` 续传，不重新检查更新。
  Future<void> retryDownload() async {
    if (_pendingAsset == null) return;
    await startDownload();
  }

  /// 用户取消正在进行的下载。
  void cancelDownload() {
    _downloadToken?.cancel();
  }

  /// 下载前清掉目录里与本次下载无关的旧 APK 和残留分片，
  /// 避免每次升级留 ~20MB 累积；当前包自己的 `.part` 不动，留着续传。
  Future<void> _sweepDir(String dir, {String? keepName}) async {
    try {
      final Directory dirObj = Directory(dir);
      if (!await dirObj.exists()) return;
      final String? keepPart = keepName == null ? null : '$dir/$keepName.part';
      await for (final FileSystemEntity entity in dirObj.list(
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final String path = entity.path;
        if (path == keepPart) continue;
        if (path.endsWith('.tmp') ||
            path.endsWith('.part') ||
            path.endsWith('.apk')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// 当前设备是否已授予安装第三方应用的权限（Android 8+）。
  Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// 引导用户去系统设置里授予「安装未知应用」权限。
  Future<void> openInstallSettings() async {
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } on PlatformException catch (error) {
      debugPrint('打开安装设置失败：$error');
    }
  }

  /// 唤起系统安装器安装 [pendingApkPath] 指向的 APK。
  /// 原生侧抛错（权限、FileProvider 配置、安装器缺失）时进入 failed，不静默。
  Future<void> install() async {
    final String? path = _pendingApkPath;
    if (path == null) return;
    try {
      await _channel.invokeMethod<void>('installApk', <String, String>{
        'path': path,
      });
    } on PlatformException catch (error) {
      debugPrint('唤起安装器失败：$error');
      state = UpdateState.failed(
        error.message == null || error.message!.isEmpty
            ? '打不开安装器，可能是安装权限没给'
            : '打不开安装器：${error.message}',
      );
    }
  }

  void _notify() => notifyListeners();

  @override
  void dispose() {
    if (_ownsDio) _dio.close();
    super.dispose();
  }
}

/// 更新状态。available 携带 release 与选中的 apk；
/// ready 的 [data] 是 APK 落盘路径；failed 的 [data] 是错误文案。
class UpdateState {
  const UpdateState.idle()
    : kind = UpdateStateKind.idle,
      release = null,
      asset = null,
      data = null;
  const UpdateState.checking()
    : kind = UpdateStateKind.checking,
      release = null,
      asset = null,
      data = null;
  const UpdateState.upToDate()
    : kind = UpdateStateKind.upToDate,
      release = null,
      asset = null,
      data = null;
  const UpdateState.available(this.release, this.asset)
    : kind = UpdateStateKind.available,
      data = null;
  const UpdateState.downloading()
    : kind = UpdateStateKind.downloading,
      release = null,
      asset = null,
      data = null;
  const UpdateState.ready(String apkPath)
    : kind = UpdateStateKind.ready,
      release = null,
      asset = null,
      data = apkPath;
  const UpdateState.failed(String message)
    : kind = UpdateStateKind.failed,
      release = null,
      asset = null,
      data = message;

  final UpdateStateKind kind;
  final LatestRelease? release;
  final ReleaseAsset? asset;
  final Object? data;
}

enum UpdateStateKind {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  ready,
  failed,
}
