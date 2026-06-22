import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/backup/providers.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';

import '../persistence/test_database.dart';

void main() {
  test('backup service is available in local-only mode', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
        activeUserIdProvider.overrideWithValue(kLocalOnlyUserId),
        outboxStoreProvider.overrideWith((_) async => const NoopOutboxStore()),
      ],
    );
    addTearDown(container.dispose);

    final service = await container.read(backupServiceProvider.future);

    expect(service, isNotNull);
  });

  test('backup service waits for an active user id', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((_) async => db),
        activeUserIdProvider.overrideWithValue(null),
        outboxStoreProvider.overrideWith((_) async => const NoopOutboxStore()),
      ],
    );
    addTearDown(container.dispose);

    final service = await container.read(backupServiceProvider.future);

    expect(service, isNull);
  });
}
