import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/update/native_update.dart';

void main() {
  group('isNativeUpdateNewer', () {
    test('detects higher major minor and patch versions', () {
      expect(isNativeUpdateNewer('1.0.0', '0.9.9'), isTrue);
      expect(isNativeUpdateNewer('0.8.0', '0.7.9'), isTrue);
      expect(isNativeUpdateNewer('0.7.1', '0.7.0'), isTrue);
    });

    test('treats equal or older versions as not updateable', () {
      expect(isNativeUpdateNewer('0.7.0', '0.7.0'), isFalse);
      expect(isNativeUpdateNewer('0.7', '0.7.0'), isFalse);
      expect(isNativeUpdateNewer('0.6.9', '0.7.0'), isFalse);
    });

    test('ignores build metadata and prerelease suffixes', () {
      expect(isNativeUpdateNewer('0.8.0+42', '0.7.0+1'), isTrue);
      expect(isNativeUpdateNewer('0.8.0-beta.1', '0.8.0'), isFalse);
    });

    test('rejects empty and malformed versions', () {
      expect(isNativeUpdateNewer('', '0.7.0'), isFalse);
      expect(isNativeUpdateNewer('latest', '0.7.0'), isFalse);
      expect(isNativeUpdateNewer('0.8.0', ''), isFalse);
    });
  });

  group('isNativeBuildNewer', () {
    test('uses Android build numbers as the update ordering key', () {
      expect(isNativeBuildNewer(125, 124), isTrue);
      expect(isNativeBuildNewer(125, 125), isFalse);
      expect(isNativeBuildNewer(124, 125), isFalse);
    });
  });

  group('NativeUpdateManifest', () {
    const sha =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

    test('parses a signed-by-release hash manifest', () {
      final manifest = NativeUpdateManifest.tryParse(<String, Object?>{
        'schemaVersion': 1,
        'platform': 'android',
        'channel': 'github',
        'versionName': '0.8.50',
        'versionCode': 125,
        'apkUrl':
            'https://github.com/zsh-a/NaviWealth/releases/download/v0.8.50/app.apk',
        'sha256': sha,
        'size': 1234,
        'releaseNotes': <String>['Fix voice startup'],
      });

      expect(manifest, isNotNull);
      expect(manifest!.versionKey, '0.8.50+125');
      expect(manifest.sizeBytes, 1234);
      expect(manifest.releaseNotes, ['Fix voice startup']);
    });

    test('rejects non-GitHub downloads and malformed hashes', () {
      expect(
        NativeUpdateManifest.tryParse(<String, Object?>{
          'versionName': '0.8.50',
          'versionCode': 125,
          'apkUrl': 'https://example.com/app.apk',
          'sha256': sha,
        }),
        isNull,
      );
      expect(
        NativeUpdateManifest.tryParse(<String, Object?>{
          'versionName': '0.8.50',
          'versionCode': 125,
          'apkUrl':
              'https://github.com/zsh-a/NaviWealth/releases/download/v0.8.50/app.apk',
          'sha256': 'not-a-sha256',
        }),
        isNull,
      );
    });
  });
}
