import 'package:flutter_test/flutter_test.dart';
import 'package:masonry_todo/update/app_version.dart';

void main() {
  group('VersionParts.tryParse', () {
    test('标准三段版本', () {
      final VersionParts parts = VersionParts.tryParse('1.1.0')!;
      expect(
        [parts.major, parts.minor, parts.patch, parts.build],
        <int>[1, 1, 0, -1],
      );
      expect(parts.toString(), '1.1.0');
    });

    test('v 前缀与四段版本（第四段是构建号）', () {
      final VersionParts parts = VersionParts.tryParse('v1.2.3.4')!;
      expect(
        [parts.major, parts.minor, parts.patch, parts.build],
        <int>[1, 2, 3, 4],
      );
      expect(parts.toString(), '1.2.3.4');
    });

    test('两段版本补零', () {
      final VersionParts parts = VersionParts.tryParse('1.2')!;
      expect(
        [parts.major, parts.minor, parts.patch, parts.build],
        <int>[1, 2, 0, -1],
      );
    });

    test('非版本返回 null', () {
      expect(VersionParts.tryParse('1'), isNull);
      expect(VersionParts.tryParse('latest'), isNull);
      expect(VersionParts.tryParse('a.b.c'), isNull);
      expect(VersionParts.tryParse('1.2.3.4.5'), isNull);
      expect(VersionParts.tryParse('1.1.0+2'), isNull);
    });
  });

  group('isReleaseNewer', () {
    VersionParts v(int major, int minor, int patch, [int build = -1]) =>
        VersionParts(major, minor, patch, build);

    test('版本三元组更大就算新', () {
      expect(isReleaseNewer(v(1, 1, 0), v(1, 0, 0)), isTrue);
      expect(isReleaseNewer(v(2, 0, 0), v(1, 9, 9)), isTrue);
    });

    test('三元组相同、双方都没有构建号：不视为更新', () {
      expect(isReleaseNewer(v(1, 0, 0), v(1, 0, 0)), isFalse);
    });

    test('三元组相同、构建号更大才算新', () {
      expect(isReleaseNewer(v(1, 0, 0, 5), v(1, 0, 0, 3)), isTrue);
      expect(isReleaseNewer(v(1, 0, 0, 3), v(1, 0, 0, 5)), isFalse);
      expect(isReleaseNewer(v(1, 0, 0, 5), v(1, 0, 0, 5)), isFalse);
    });

    test('任一方缺构建号：不视为更新', () {
      expect(isReleaseNewer(v(1, 0, 0), v(1, 0, 0, 9)), isFalse);
      expect(isReleaseNewer(v(1, 0, 0, 9), v(1, 0, 0)), isFalse);
    });

    test('三元组不同时构建号不参与比较', () {
      expect(isReleaseNewer(v(1, 0, 1, 0), v(1, 0, 0, 9)), isTrue);
    });
  });

  group('currentAppVersion', () {
    test('versionName + buildNumber 拼出四元组', () {
      final VersionParts parts = currentAppVersion('1.1.0', '2')!;
      expect(
        [parts.major, parts.minor, parts.patch, parts.build],
        <int>[1, 1, 0, 2],
      );
    });

    test('没有构建号时为 -1', () {
      final VersionParts parts = currentAppVersion('1.1.0', null)!;
      expect(parts.build, -1);
    });

    test('versionName 不是版本时返回 null', () {
      expect(currentAppVersion('latest', '1'), isNull);
    });
  });
}
