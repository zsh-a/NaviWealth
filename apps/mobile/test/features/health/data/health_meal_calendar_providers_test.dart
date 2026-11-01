import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/features/health/data/health_calendar_providers.dart';
import 'package:naviwealth/features/health/data/health_meal_providers.dart';
import 'package:naviwealth/features/health/data/health_meal_repository.dart';
import 'package:naviwealth/features/health/data/meal_food_catalog.dart';
import 'package:naviwealth/features/health/domain/health_meal.dart';

import '../../../core/persistence/test_database.dart';
import '../../finance/data/repositories/_stub_stamper.dart';

class _CalendarRepository extends HealthMealRepository {
  _CalendarRepository({
    required super.db,
    required super.outbox,
    required super.stamper,
    required super.clock,
  });

  final queries = <({String owner, DateTime from, DateTime to})>[];

  @override
  Stream<Map<DateTime, int>> watchRecordedDayCounts({
    required String ownerUserId,
    required DateTime from,
    required DateTime to,
  }) {
    queries.add((owner: ownerUserId, from: from, to: to));
    return super.watchRecordedDayCounts(
      ownerUserId: ownerUserId,
      from: from,
      to: to,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('calendar counts honor opt-in, owner changes and sign-out', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final now = DateTime(2026, 10, 28, 12);
    final repo = _CalendarRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(userId: 'alice'),
      clock: () => now,
    );
    await repo.save(
      expectedOwnerUserId: 'alice',
      capturedAt: now,
      day: DateTime(2026, 10, 27),
      type: HealthMealType.lunch,
      foods: [mealFoodCatalog.first.portion(100)],
    );
    await HealthMealRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(userId: 'bob'),
      clock: () => now,
    ).save(
      expectedOwnerUserId: 'bob',
      capturedAt: now,
      day: now,
      type: HealthMealType.lunch,
      foods: [mealFoodCatalog.first.portion(100)],
    );
    List<Override> overrides(String? owner) => [
      appDatabaseProvider.overrideWith((_) async => db),
      activeUserIdProvider.overrideWithValue(owner),
      currentUserIdProvider.overrideWithValue(() async => owner!),
      healthClockProvider.overrideWithValue(() => now),
      healthMealRepositoryProvider.overrideWith((_) async => repo),
    ];
    final container = ProviderContainer(overrides: overrides('alice'));
    addTearDown(container.dispose);
    await container.read(auth.domainOptInsProvider.future);
    final provider = healthMealRecordedDayCountsProvider(
      DateTime.utc(2026, 10),
    );
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    expect(await container.read(provider.future), isEmpty);
    expect(repo.queries, isEmpty);
    await container
        .read(auth.domainOptInsProvider.notifier)
        .setEnabled(DomainScope.health, true);
    expect(await container.read(provider.future), {
      DateTime.utc(2026, 10, 27): 1,
    });
    container.updateOverrides(overrides('bob'));
    await container.pump();
    expect(await container.read(provider.future), {
      DateTime.utc(2026, 10, 28): 1,
    });
    final queryCount = repo.queries.length;
    await container
        .read(auth.domainOptInsProvider.notifier)
        .setEnabled(DomainScope.health, false);
    expect(await container.read(provider.future), isEmpty);
    expect(repo.queries.length, queryCount);
    container.updateOverrides(overrides(null));
    await container.pump();
    expect(await container.read(provider.future), isEmpty);
    expect(repo.queries.length, queryCount);
  });

  test(
    'calendar queries one month at a time and advances at midnight',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      var now = DateTime(2026, 10, 28, 12);
      final repo = _CalendarRepository(
        db: db,
        outbox: InMemoryOutboxStore(),
        stamper: makeStubStamper(userId: 'alice'),
        clock: () => now,
      );
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          activeUserIdProvider.overrideWithValue('alice'),
          healthClockProvider.overrideWithValue(() => now),
          healthMealRepositoryProvider.overrideWith((_) async => repo),
        ],
      );
      addTearDown(container.dispose);
      await container.read(auth.domainOptInsProvider.future);
      await container
          .read(auth.domainOptInsProvider.notifier)
          .setEnabled(DomainScope.health, true);
      final current = healthMealRecordedDayCountsProvider(
        DateTime.utc(2026, 10),
      );
      final future = healthMealRecordedDayCountsProvider(
        DateTime.utc(2026, 11),
      );
      final subscriptions = [
        container.listen(current, (_, _) {}),
        container.listen(future, (_, _) {}),
      ];
      addTearDown(() {
        for (final subscription in subscriptions) {
          subscription.close();
        }
      });
      await container.read(current.future);
      await container.read(future.future);
      expect(repo.queries, [
        (
          owner: 'alice',
          from: DateTime.utc(2026, 10),
          to: DateTime.utc(2026, 10, 29),
        ),
      ]);
      now = DateTime(2026, 11, 1, 0, 1);
      container.invalidate(healthCalendarDayProvider);
      await container.pump();
      await container.read(current.future);
      await container.read(future.future);
      expect(
        repo.queries,
        contains((
          owner: 'alice',
          from: DateTime.utc(2026, 10),
          to: DateTime.utc(2026, 11),
        )),
      );
      expect(
        repo.queries,
        contains((
          owner: 'alice',
          from: DateTime.utc(2026, 11),
          to: DateTime.utc(2026, 11, 2),
        )),
      );
    },
  );
}
