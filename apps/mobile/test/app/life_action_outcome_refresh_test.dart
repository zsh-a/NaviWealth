import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/domain_packs/health_life_contribution.dart';
import 'package:naviwealth/app/life_action_outcomes.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/auth/domain_opt_in_store.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/lifeos/action_outcome.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/execution/data/execution_repository.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/health/data/health_metric_repository.dart';
import 'package:naviwealth/features/health/data/providers.dart';
import 'package:naviwealth/features/health/domain/health_metric.dart';
import 'package:naviwealth/features/health/domain/health_metric_kind.dart';
import 'package:naviwealth/features/health/ui/health_today_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/persistence/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final enabled in [true, false]) {
    test(
      enabled
          ? 'retry rereads the failed health repository'
          : 'inactive source domain has no retry or source reads',
      () async {
        final db = makeTestDatabase();
        addTearDown(db.close);
        await DomainOptInStore(db)
            .write(DomainOptIns({if (enabled) DomainScope.health}));
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final outbox = InMemoryOutboxStore();
        final execution = ExecutionRepository(db: db, outbox: outbox);
        final health = _FailOnceHealthRepository(db: db, outbox: outbox);
        final now = DateTime.now();
        final day =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}';
        final completed = now.subtract(const Duration(minutes: 1));
        await execution.upsertAction(
          ExecutionAction(
            id: 'done',
            title: 'Recovery',
            status: ExecutionActionStatus.done,
            source: ExecutionSourceRef(
              domain: 'health',
              rowFamily: 'health:health_metrics',
              rowId: 'recovery:$day',
              labelSnapshot: 'HealthOS',
            ),
            createdAt: completed,
            completedAt: completed,
            sync: SyncMeta(
              ownerUserId: 'owner',
              updatedAt: completed,
              updatedByDevice: 'device',
              hlc: Hlc.zero('device'),
            ),
          ),
        );
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWith((_) async => db),
            currentUserIdProvider.overrideWithValue(() async => 'owner'),
            activeUserIdProvider.overrideWithValue('owner'),
            sharedPreferencesProvider.overrideWithValue(prefs),
            executionOwnerUserIdProvider.overrideWith((_) async => 'owner'),
            executionRepositoryProvider.overrideWith((_) async => execution),
            healthMetricRepositoryProvider.overrideWith((_) async => health),
            activeDomainPacksProvider.overrideWithValue([
              if (enabled)
                const DomainPack(
                  scope: DomainScope.health,
                  data: DomainDataContribution(
                    lifeSignalBuilder: healthLifeSignals,
                  ),
                ),
            ]),
            actionOutcomeSummariesProvider.overrideWith(
              watchLifeActionOutcomes,
            ),
            actionOutcomeRefreshProvider.overrideWith(
              watchActionOutcomeRefresh,
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(auth.domainOptInsProvider.future);
        final subscription = container.listen(
          actionOutcomeSummariesProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        await container.read(executionClosedActionsProvider.future);
        if (!enabled) {
          expect(container.read(actionOutcomeRefreshProvider('done')), isNull);
          expect(health.reads, 0);
          expect(
            container
                .read(actionOutcomeSummariesProvider)
                .requireValue['done']
                ?.status,
            ActionOutcomeStatus.unsupported,
          );
          return;
        }
        await expectLater(
          container.read(recoverySignalProvider.future),
          throwsStateError,
        );
        expect(
          container
              .read(actionOutcomeSummariesProvider)
              .requireValue['done']
              ?.status,
          ActionOutcomeStatus.failed,
        );
        expect(health.reads, 1);
        container.read(actionOutcomeRefreshProvider('done'))!();
        await container.read(recoverySignalProvider.future);
        expect(health.reads, 2);
        expect(
          container
              .read(actionOutcomeSummariesProvider)
              .requireValue['done']
              ?.status,
          ActionOutcomeStatus.incomplete,
        );
      },
    );
  }
}

class _FailOnceHealthRepository extends HealthMetricRepository {
  _FailOnceHealthRepository({required super.db, required super.outbox});
  int reads = 0;

  @override
  Future<Map<HealthMetricKind, List<HealthMetric>>> listInRange({
    required String ownerUserId,
    required Set<HealthMetricKind> kinds,
    required DateTime from,
    required DateTime to,
  }) async {
    if (++reads == 1) throw StateError('temporary repository failure');
    return super.listInRange(
      ownerUserId: ownerUserId,
      kinds: kinds,
      from: from,
      to: to,
    );
  }
}
