import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/lifeos/action_dispatcher.dart';
import '../../../../core/persistence/providers.dart';
import '../../../../core/sync/mutation_context.dart';
import '../../../../core/sync/outbox_provider.dart';
import '../../inbox/data/financial_inbox_providers.dart';
import '../../ingest/data/providers.dart';
import '../../runway/data/money_runway_providers.dart';
import '../../runway/domain/money_runway.dart';
import '../domain/account_reconciliation.dart';
import '../domain/monthly_close.dart';
import 'account_reconciliation_providers.dart';
import 'monthly_close_repository.dart';

export 'account_reconciliation_providers.dart';

final monthlyCloseNowProvider = Provider<DateTime>((ref) => DateTime.now());

final currentClosePeriodProvider = Provider<String>((ref) {
  final now = ref.watch(monthlyCloseNowProvider);
  return '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}';
});

final monthlyCloseRepositoryProvider = FutureProvider<MonthlyCloseRepository>((
  ref,
) async {
  return MonthlyCloseRepository(
    db: await ref.watch(appDatabaseProvider.future),
    outbox: await ref.watch(outboxStoreProvider.future),
    stamper: await ref.watch(mutationStamperProvider.future),
  );
});

final reconciliationTargetsProvider =
    Provider.autoDispose<AsyncValue<List<ReconciliationTarget>>>(
      (ref) => ref.watch(
        reconciliationTargetsForPeriodProvider(
          ref.watch(currentClosePeriodProvider),
        ),
      ),
    );

final monthlyCloseEvidenceProvider =
    Provider.autoDispose<AsyncValue<MonthlyCloseEvidence>>((ref) {
      final pendingImportsAsync = ref.watch(pendingIngestReviewItemsProvider);
      final inboxAsync = ref.watch(financialInboxProvider);
      final targetsAsync = ref.watch(reconciliationTargetsProvider);
      final runwayAsync = ref.watch(moneyRunwayProvider);
      final openActionCountAsync = ref.watch(lifeOpenActionCountProvider);
      if (pendingImportsAsync.isLoading ||
          inboxAsync.isLoading ||
          targetsAsync.isLoading ||
          runwayAsync.isLoading ||
          openActionCountAsync.isLoading) {
        return const AsyncValue.loading();
      }
      final error =
          pendingImportsAsync.error ??
          inboxAsync.error ??
          targetsAsync.error ??
          runwayAsync.error ??
          openActionCountAsync.error;
      if (error != null) return AsyncValue.error(error, StackTrace.current);
      final pendingImports = pendingImportsAsync.requireValue;
      final inbox = inboxAsync.requireValue;
      final targets = targetsAsync.requireValue;
      final runway = runwayAsync.requireValue;
      final openActionCount = openActionCountAsync.value;

      final acceptedTargets = targets
          .where((target) => target.isAccepted)
          .length;
      final hasOverride = targets.any(
        (target) =>
            target.reconciliation?.status ==
            AccountReconciliationStatus.overridden,
      );
      final hasMismatch = targets.any(
        (target) =>
            target.reconciliation?.status ==
            AccountReconciliationStatus.mismatch,
      );
      final accountState = targets.isEmpty || hasMismatch
          ? MonthlyCloseStepState.blocked
          : acceptedTargets != targets.length
          ? MonthlyCloseStepState.ready
          : hasOverride
          ? MonthlyCloseStepState.overridden
          : MonthlyCloseStepState.verified;
      final runwayState = !runway.hasData || runway.missingCurrencies.isNotEmpty
          ? MonthlyCloseStepState.blocked
          : runway.confidence == MoneyRunwayConfidence.low
          ? MonthlyCloseStepState.ready
          : MonthlyCloseStepState.verified;

      return AsyncValue.data(
        MonthlyCloseEvidence(
          states: <MonthlyCloseStep, MonthlyCloseStepState>{
            MonthlyCloseStep.importReview: pendingImports.isEmpty
                ? MonthlyCloseStepState.verified
                : MonthlyCloseStepState.ready,
            MonthlyCloseStep.inboxClear: inbox.isEmpty
                ? MonthlyCloseStepState.verified
                : MonthlyCloseStepState.ready,
            MonthlyCloseStep.accountReconcile: accountState,
            MonthlyCloseStep.runwayReview: runwayState,
            MonthlyCloseStep.actionReview:
                !openActionCountAsync.isLoading &&
                    !openActionCountAsync.hasError &&
                    (openActionCount == null || openActionCount == 0)
                ? MonthlyCloseStepState.verified
                : MonthlyCloseStepState.ready,
          },
          details: <String, Object?>{
            'pending_import_count': pendingImports.length,
            'open_inbox_count': inbox.length,
            'reconciliation_target_count': targets.length,
            'reconciliation_accepted_count': acceptedTargets,
            'runway_confidence': runway.confidence.name,
            'runway_data_completeness': runway.dataCompleteness,
            'open_action_count': openActionCount,
            'active_signal_keys': inbox
                .map((item) => item.sourceKey)
                .toList(growable: false),
            'reconciliation_exception_keys': targets
                .where(
                  (target) =>
                      target.reconciliation != null && !target.isAccepted,
                )
                .map((target) => '${target.accountId}:${target.unit}')
                .toList(growable: false),
          },
        ),
      );
    });

final currentMonthlyCloseProvider = StreamProvider.autoDispose<MonthlyClose?>((
  ref,
) async* {
  final repository = await ref.watch(monthlyCloseRepositoryProvider.future);
  yield* repository.watch(ref.watch(currentClosePeriodProvider));
});

final previousMonthlyCloseProvider = StreamProvider.autoDispose<MonthlyClose?>((
  ref,
) async* {
  final repository = await ref.watch(monthlyCloseRepositoryProvider.future);
  yield* repository.watchPreviousClosed(ref.watch(currentClosePeriodProvider));
});

final monthlyCloseComparisonProvider =
    Provider.autoDispose<AsyncValue<MonthlyCloseComparison>>((ref) {
      final evidence = ref.watch(monthlyCloseEvidenceProvider);
      final previous = ref.watch(previousMonthlyCloseProvider);
      if (evidence.isLoading || previous.isLoading) {
        return const AsyncValue.loading();
      }
      final error = evidence.error ?? previous.error;
      if (error != null) return AsyncValue.error(error, StackTrace.current);
      return AsyncValue.data(
        compareMonthlyCloseEvidence(
          current: evidence.requireValue,
          previous: previous.value,
        ),
      );
    });
