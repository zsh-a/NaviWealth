import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sync-v3.md describes the active protocol boundaries', () {
    final doc = File('../../docs/sync/sync-v3.md').readAsStringSync();
    for (final marker in <String>[
      'Sync-Protocol-Version: 3',
      'POST /sync',
      'accepted',
      'domain_generations',
      'POST /sync/reset-domain',
      'sync_table_registry.dart',
    ]) {
      expect(doc, contains(marker), reason: marker);
    }
  });
}
