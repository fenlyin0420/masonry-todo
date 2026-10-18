import 'app_version.dart';

/// GitHub Releases API `releases/latest` 的一个 release。
class LatestRelease {
  LatestRelease({
    required this.tagName,
    required this.htmlUrl,
    required this.assets,
  });

  final String tagName;
  final String htmlUrl;
  final List<ReleaseAsset> assets;

  VersionParts? get version {
    return VersionParts.tryParse(tagName);
  }

  /// 从 GitHub API 的 JSON 里解析。字段缺失时返回 null。
  static LatestRelease? tryParse(Map<String, dynamic> json) {
    final String? tag = json['tag_name'] as String?;
    final String? html = json['html_url'] as String?;
    if (tag == null || html == null) return null;
    final List<ReleaseAsset> assets = <ReleaseAsset>[];
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final raw in rawAssets) {
        if (raw is! Map) continue;
        final String? name = raw['name'] as String?;
        final String? url = raw['browser_download_url'] as String?;
        if (name == null || url == null) continue;
        assets.add(
          ReleaseAsset(
            name: name,
            downloadUrl: url,
            sizeBytes: (raw['size'] as num?)?.toInt(),
          ),
        );
      }
    }
    return LatestRelease(tagName: tag, htmlUrl: html, assets: assets);
  }
}

/// Release 上的一个下载附件。
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    this.sizeBytes,
  });

  final String name;
  final String downloadUrl;
  final int? sizeBytes;

  bool get isApk => name.endsWith('.apk');
}

/// 按设备 ABI 挑出该下载的 APK。
///
/// 新发布按架构拆包，附件名形如 `masonry-todo-arm64-v8a.apk`；
/// 老发布只有一个整包 `app-release.apk`，作为回退。
/// 已知 ABI 却在多包里找不到对应的那个时返回 null，
/// 免得静默下错包（装不上还得用户自己排查）。
ReleaseAsset? pickApkForAbi(LatestRelease release, String? abi) {
  final List<ReleaseAsset> apks = release.assets
      .where((asset) => asset.isApk)
      .toList();
  if (apks.isEmpty) return null;
  if (abi != null) {
    final String wanted = abi.replaceAll(RegExp(r'[-_]'), '').toLowerCase();
    for (final asset in apks) {
      final String suffix = asset.name.replaceFirst(
        RegExp(r'^masonry-todo-'),
        '',
      );
      final String normalized = suffix
          .replaceAll(RegExp(r'[-_]'), '')
          .replaceAll('.apk', '')
          .toLowerCase();
      if (normalized == wanted) return asset;
    }
    if (apks.length == 1) return apks.single;
    return null;
  }
  if (apks.length == 1) return apks.single;
  return apks.firstWhere(
    (asset) => asset.name == 'app-release.apk',
    orElse: () => apks.first,
  );
}
