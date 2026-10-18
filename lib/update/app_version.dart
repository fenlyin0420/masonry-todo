/// 语义化版本四元组：major.minor.patch[.build]。
/// build 为 -1 表示版本串里没有第四段。
class VersionParts {
  const VersionParts(this.major, this.minor, this.patch, this.build);

  final int major;
  final int minor;
  final int patch;
  final int build;

  /// 解析形如 `v1.2.3` / `1.2.3.4` 的版本串。
  /// 少于两段、多于四段，或任何一段不是纯数字时返回 null。
  static VersionParts? tryParse(String raw) {
    final String text = raw.trim();
    final String body = (text.startsWith('v') || text.startsWith('V'))
        ? text.substring(1)
        : text;
    final List<String> segments = body.split('.');
    if (segments.length < 2 || segments.length > 4) return null;
    final List<int> ints = <int>[];
    for (final segment in segments) {
      final int? value = int.tryParse(segment.trim());
      if (value == null || value < 0) return null;
      ints.add(value);
    }
    return VersionParts(
      ints[0],
      ints[1],
      ints.length > 2 ? ints[2] : 0,
      ints.length > 3 ? ints[3] : -1,
    );
  }

  @override
  String toString() =>
      build < 0 ? '$major.$minor.$patch' : '$major.$minor.$patch.$build';
}

/// 判断 release 版本是否比 current 新。
///
/// 先比 major/minor/patch；三段相等且 release 带第四段（build）时，
/// 再比 build 号，否则视为同级，不算更新。
bool isReleaseNewer(VersionParts release, VersionParts current) {
  final int triple = _compareTriples(release, current);
  if (triple != 0) return triple > 0;
  if (release.build < 0 || current.build < 0) return false;
  return release.build > current.build;
}

int _compareTriples(VersionParts a, VersionParts b) {
  if (a.major != b.major) return a.major - b.major;
  if (a.minor != b.minor) return a.minor - b.minor;
  return a.patch - b.patch;
}

/// 从 package_info 的 versionName / buildNumber 拼出当前应用版本。
/// versionName 解析失败时返回 null（调用方跳过自动更新）。
VersionParts? currentAppVersion(String versionName, String? buildNumber) {
  final VersionParts? base = VersionParts.tryParse(versionName);
  if (base == null) return null;
  final int build = int.tryParse((buildNumber ?? '').trim()) ?? -1;
  return VersionParts(base.major, base.minor, base.patch, build);
}
