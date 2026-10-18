import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_version.dart';
import 'github_release.dart';

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
  }) : _currentVersion = currentVersion,
       _abi = abi,
       _dio = dio ?? Dio(),
       _ownsDio = dio == null,
       _channel = channel ?? const MethodChannel('masonry_todo.updates'),
       _repo = repo;

  static const String apiBase = 'https://api.github.com';

  final VersionParts _currentVersion;
  final String? _abi;
  final Dio _dio;
  final bool _ownsDio;
  final MethodChannel _channel;
  final String _repo;

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
    userInitiated = manual;
    manualCheck = manual;
    _pendingAsset = null;
    _pendingApkPath = null;
    state = UpdateState.checking();
    try {
      final Map<String, dynamic> json = await _fetchLatestReleaseJson();
      final LatestRelease? release = LatestRelease.tryParse(json);
      final VersionParts? version = release?.version;
      if (release == null || version == null) {
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
      state = UpdateState.failed('网络不通，检查更新失败');
    }
  }

  Future<Map<String, dynamic>> _fetchLatestReleaseJson() async {
    final Response<dynamic> response = await _dio.get<dynamic>(
      '$apiBase/repos/$_repo/releases/latest',
      options: Options(
        receiveTimeout: const Duration(seconds: 20),
        headers: <String, Object>{'accept': 'application/vnd.github+json'},
      ),
    );
    final Object? data = response.data;
    if (data is! Map) throw const FormatException('Release 响应格式不对');
    return Map<String, dynamic>.from(data);
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
    String? tmpPath;
    try {
      final String? dir = await _channel.invokeMethod<String>('getUpdatesDir');
      if (dir == null) {
        throw PlatformException(code: 'NO_DIR', message: '没有下载目录');
      }
      final String name = asset.name.substring(asset.name.lastIndexOf('/') + 1);
      tmpPath = '$dir/$name.tmp';
      final String finalPath = '$dir/$name';
      await _sweepDir(dir);
      await _dio.download(
        asset.downloadUrl,
        tmpPath,
        cancelToken: _downloadToken,
        onReceiveProgress: (int received, int total) {
          if (total > 0) {
            downloadProgress = received / total;
            _notify();
          }
        },
      );
      final File tmp = File(tmpPath);
      if (!await tmp.exists()) {
        throw FileSystemException('下载没有落盘', tmpPath);
      }
      final File finalFile = File(finalPath);
      if (await finalFile.exists()) await finalFile.delete();
      await tmp.rename(finalFile.path);
      _pendingApkPath = finalPath;
      downloadProgress = 1;
      state = UpdateState.ready(finalPath);
    } catch (error) {
      final bool cancelled =
          error is DioException && error.type == DioExceptionType.cancel;
      debugPrint(cancelled ? '取消下载更新' : '下载更新失败：$error');
      state = cancelled ? UpdateState.idle() : UpdateState.failed('下载失败，请重试');
    } finally {
      _downloadToken = null;
      // 失败或取消时清掉半个临时文件，别留在目录里。
      if (tmpPath != null) {
        try {
          final File tmp = File(tmpPath);
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
      }
    }
  }

  /// 用户取消正在进行的下载。
  void cancelDownload() {
    _downloadToken?.cancel();
  }

  /// 下载前清掉目录里的旧 APK 和临时文件，避免每次升级留 ~20MB 累积。
  Future<void> _sweepDir(String dir) async {
    try {
      final Directory dirObj = Directory(dir);
      if (!await dirObj.exists()) return;
      await for (final FileSystemEntity entity in dirObj.list(
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final String path = entity.path;
        if (path.endsWith('.tmp') || path.endsWith('.apk')) {
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
  Future<void> install() async {
    final String? path = _pendingApkPath;
    if (path == null) return;
    await _channel.invokeMethod<void>('installApk', <String, String>{
      'path': path,
    });
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
