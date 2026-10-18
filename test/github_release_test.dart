import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_todo/update/github_release.dart';

Map<String, dynamic> releaseJson({
  String tag = 'v1.1.0',
  List<List<String>> assets = const [],
}) {
  return <String, dynamic>{
    'tag_name': tag,
    'html_url': 'https://github.com/fenlyin0420/masonry-todo/releases/tag/$tag',
    'published_at': '2026-10-18T08:00:00Z',
    'assets': [
      for (final List<String> asset in assets)
        <String, dynamic>{
          'name': asset.first,
          'browser_download_url': 'https://github.com/download/$asset.first',
          'size': 1024,
        },
    ],
  };
}

void main() {
  group('LatestRelease.tryParse', () {
    test('正常 Release 解析出标签与资产', () {
      final release = LatestRelease.tryParse(
        releaseJson(
          assets: [
            const ['masonry-todo-arm64_v8a.apk'],
          ],
        ),
      )!;
      expect(release.tagName, 'v1.1.0');
      expect(release.version, isNotNull);
      expect(release.assets.single.name, 'masonry-todo-arm64_v8a.apk');
      expect(release.assets.single.downloadUrl, isNotNull);
    });

    test('缺 tag 或 html_url 判无效', () {
      expect(LatestRelease.tryParse(<String, dynamic>{}), isNull);
      final Map<String, dynamic> noTag = releaseJson();
      noTag.remove('tag_name');
      expect(LatestRelease.tryParse(noTag), isNull);
      final Map<String, dynamic> noHtml = releaseJson();
      noHtml.remove('html_url');
      expect(LatestRelease.tryParse(noHtml), isNull);
    });

    test('资产字段残缺的条目被跳过', () {
      final Map<String, dynamic> json = releaseJson(
        assets: [
          const ['masonry-todo-arm64_v8a.apk'],
        ],
      );
      final List<dynamic> assets = (json['assets'] as List)
        ..first = <String, dynamic>{'name': '无下载链接.apk'};
      json['assets'] = assets;
      final release = LatestRelease.tryParse(json)!;
      expect(release.assets, isEmpty);
      expect(release.version, isNotNull);
    });
  });

  group('pickApkForAbi', () {
    LatestRelease splitRelease() {
      return LatestRelease.tryParse(
        releaseJson(
          assets: [
            const ['masonry-todo-arm64_v8a.apk'],
            const ['masonry-todo-armeabi_v7a.apk'],
            const ['SHA256SUMS'],
          ],
        ),
      )!;
    }

    test('按设备架构选对应包', () {
      expect(
        pickApkForAbi(splitRelease(), 'arm64-v8a')!.name,
        'masonry-todo-arm64_v8a.apk',
      );
      expect(
        pickApkForAbi(splitRelease(), 'armeabi-v7a')!.name,
        'masonry-todo-armeabi_v7a.apk',
      );
      // 下划线与大小写写法都能对上
      expect(
        pickApkForAbi(splitRelease(), 'arm64_V8A')!.name,
        'masonry-todo-arm64_v8a.apk',
      );
    });

    test('拿不到架构时选第一个 APK', () {
      expect(
        pickApkForAbi(splitRelease(), null)!.name,
        'masonry-todo-arm64_v8a.apk',
      );
    });

    test('老版本只有一个 fat 包时退回它', () {
      final release = LatestRelease.tryParse(
        releaseJson(
          assets: [
            const ['app-release.apk'],
          ],
        ),
      )!;
      expect(pickApkForAbi(release, 'arm64-v8a')!.name, 'app-release.apk');
      expect(pickApkForAbi(release, null)!.name, 'app-release.apk');
    });

    test('多包且无架构信息时优先 app-release.apk', () {
      final release = LatestRelease.tryParse(
        releaseJson(
          assets: [
            const ['masonry-todo-arm64_v8a.apk'],
            const ['app-release.apk'],
          ],
        ),
      )!;
      expect(pickApkForAbi(release, null)!.name, 'app-release.apk');
    });

    test('没有 APK 返回 null', () {
      final release = LatestRelease.tryParse(
        releaseJson(
          assets: [
            const ['source.zip'],
          ],
        ),
      )!;
      expect(pickApkForAbi(release, 'arm64-v8a'), isNull);
      expect(pickApkForAbi(release, null), isNull);
    });

    test('已知架构不在多包里时返回 null，不静默选错包', () {
      expect(pickApkForAbi(splitRelease(), 'x86_64'), isNull);
      // 单包不受影响
      final single = LatestRelease.tryParse(
        releaseJson(
          assets: [
            const ['masonry-todo-arm64_v8a.apk'],
          ],
        ),
      )!;
      expect(
        pickApkForAbi(single, 'x86_64')!.name,
        'masonry-todo-arm64_v8a.apk',
      );
    });
  });
}
