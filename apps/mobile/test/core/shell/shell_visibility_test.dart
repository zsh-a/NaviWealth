import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/shell/shell_visibility.dart';

void main() {
  group('isShellTabPathActive', () {
    test('empty active path means everything is active', () {
      expect(
        isShellTabPathActive(activeTabPath: '', routePath: '/activity'),
        isTrue,
      );
    });

    test('matches exact tab root', () {
      expect(
        isShellTabPathActive(activeTabPath: '/wealth', routePath: '/wealth'),
        isTrue,
      );
    });

    test('matches nested routes under the tab root', () {
      expect(
        isShellTabPathActive(
          activeTabPath: '/activity',
          routePath: '/activity/spending',
        ),
        isTrue,
      );
    });

    test('rejects sibling tabs', () {
      expect(
        isShellTabPathActive(activeTabPath: '/wealth', routePath: '/plan'),
        isFalse,
      );
    });

    test('rejects prefix-confused siblings', () {
      expect(
        isShellTabPathActive(activeTabPath: '/plan', routePath: '/planfire'),
        isFalse,
      );
    });
  });
}
