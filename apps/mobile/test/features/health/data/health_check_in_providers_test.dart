import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/health/data/health_check_in_providers.dart';
import 'package:naviwealth/features/health/data/health_check_in_repository.dart';
import 'package:naviwealth/features/health/data/health_series_providers.dart';
import 'package:naviwealth/features/health/domain/health_check_in.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

class _SpyRepository extends HealthCheckInRepository {
  _SpyRepository({
    required super.db,
    required super.outbox,
    required super.stamper,
    required super.clock,
  });
  int queries = 0;
  @override
  Stream<List<HealthCheckIn>> watchInRange({
    required String ownerUserId,
    required DateTime from,
    required DateTime to,
  }) {
    queries++;
    return super.watchInRange(ownerUserId: ownerUserId, from: from, to: to);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('opt-in gates queries, edits stream live and account switching drops previous records', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final now = DateTime(2026, 10, 1, 12);
    final repo = _SpyRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(userId: 'alice'),
      clock: () => now,
    );
    await repo.save(day: now, note: 'Alice');
    await HealthCheckInRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(userId: 'bob'),
      clock: () => now,
    ).save(day: now, note: 'Bob');
    List<Override> overrides(String owner) => [
      appDatabaseProvider.overrideWith((_) async => db),
      currentUserIdProvider.overrideWithValue(() async => owner),
      activeUserIdProvider.overrideWithValue(owner),
      healthClockProvider.overrideWithValue(() => now),
      healthCheckInRepositoryProvider.overrideWith((_) async => repo),
    ];
    final container = ProviderContainer(overrides: overrides('alice'));
    addTearDown(container.dispose);
    await container.read(auth.domainOptInsProvider.future);
    final subscription = container.listen(healthCheckInsProvider(7), (_, _) {});
    addTearDown(subscription.close);
    expect(await container.read(healthCheckInsProvider(7).future), isEmpty);
    expect(repo.queries, 0);
    await container
        .read(auth.domainOptInsProvider.notifier)
        .setEnabled(DomainScope.health, true);
    expect(
      (await container.read(healthCheckInsProvider(7).future)).single.note,
      'Alice',
    );
    await repo.save(day: now, note: 'Alice edited');
    await container.pump();
    expect(
      (await container.read(healthCheckInsProvider(7).future)).single.note,
      'Alice edited',
    );
    container.updateOverrides(overrides('bob'));
    await container.pump();
    expect(
      (await container.read(healthCheckInsProvider(7).future)).single.note,
      'Bob',
    );
    final activeQueries = repo.queries;
    await container
        .read(auth.domainOptInsProvider.notifier)
        .setEnabled(DomainScope.health, false);
    expect(await container.read(healthCheckInsProvider(7).future), isEmpty);
    expect(repo.queries, activeQueries);
  });
}
