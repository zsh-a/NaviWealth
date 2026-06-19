import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/row_applier.dart';

void main() {
  test('sync-v2.md syncable table inventory matches kSyncableTables', () {
    final doc = File('../../docs/sync-v2.md').readAsStringSync();
    final start = doc.indexOf('Current syncable table inventory is pinned by');
    final end = doc.indexOf('Locally-dirty rows are tracked', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThanOrEqualTo(0));

    final section = doc.substring(start, end);
    final tableNames = <String>{};
    for (final line in section.split('\n')) {
      if (!line.startsWith('| `')) continue;
      final values = RegExp('`([^`]+)`')
          .allMatches(line)
          .map((match) => match.group(1)!)
          .where((value) => !value.endsWith(':'));
      tableNames.addAll(values);
    }

    expect(tableNames, kSyncableTables);
  });
}
