import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/nav.dart';

void main() {
  group('logicalParentOf', () {
    test('drops the last segment of a nested path', () {
      expect(logicalParentOf('/activity/expenses/new'), '/activity/expenses');
      expect(logicalParentOf('/accounts/list/abc123'), '/accounts/list');
      expect(
        logicalParentOf('/accounts/liabilities/new'),
        '/accounts/liabilities',
      );
    });

    test('a primary tab root collapses to Home', () {
      expect(logicalParentOf('/accounts'), '/');
      expect(logicalParentOf('/activity'), '/');
    });

    test('Home and empty stay at Home', () {
      expect(logicalParentOf('/'), '/');
      expect(logicalParentOf(''), '/');
    });

    test('ignores query string when computing the parent', () {
      expect(
        logicalParentOf('/accounts/list/abc123?selected=xyz'),
        '/accounts/list',
      );
    });
  });
}
