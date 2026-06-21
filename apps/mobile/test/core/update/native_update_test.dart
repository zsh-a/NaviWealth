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
}
