import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/persistence/providers.dart';
import '../../../../core/sync/mutation_context.dart';
import '../../../../core/sync/outbox_provider.dart';
import '../../composition/finance_route_paths.dart';
import '../../ingest/data/providers.dart';
import '../../runway/data/money_runway_providers.dart';
import '../../runway/domain/money_runway.dart';
import '../domain/financial_inbox.dart';
import 'financial_signal_repository.dart';

final financialInboxNowProvider = Provider<DateTime>((ref) => DateTime.now());

final financialSignalRepositoryProvider =
    FutureProvider<FinancialSignalRepository>((ref) async {
      return FinancialSignalRepository(
        db: await ref.watch(appDatabaseProvider.future),
        outbox: await ref.watch(outboxStoreProvider.future),
        stamper: await ref.watch(mutationStamperProvider.future),
      );
    });

final financialSignalCandidatesProvider =
    Provider.autoDispose<List<FinancialSignalCandidate>>((ref) {
      final items = <FinancialSignalCandidate>[];
      final pending =
          ref.watch(pendingIngestReviewItemsProvider).value ?? const [];
      if (pending.isNotEmpty) {
        items.add(
          FinancialSignalCandidate(
            sourceKey: 'import-review',
            kind: FinancialInboxKind.importReview,
            priority: FinancialInboxPriority.important,
            count: pending.length,
            route: FinanceRoutes.activityIngest,
          ),
        );
      }

      final runway = ref.watch(moneyRunwayProvider).value;
      if (runway != null && runway.hasData) {
        if (runway.status != MoneyRunwayStatus.healthy) {
          items.add(
            FinancialSignalCandidate(
              sourceKey: 'runway-risk',
              kind: FinancialInboxKind.runwayRisk,
              priority: runway.status == MoneyRunwayStatus.shortfall
                  ? FinancialInboxPriority.important
                  : FinancialInboxPriority.attention,
              count: 1,
              route: FinanceRoutes.planRunway,
              evidence: runway.toEvidenceJson(),
            ),
          );
        }
        if (runway.missingCurrencies.isNotEmpty) {
          items.add(
            FinancialSignalCandidate(
              sourceKey: 'missing-fx',
              kind: FinancialInboxKind.missingExchangeRate,
              priority: FinancialInboxPriority.attention,
              count: runway.missingCurrencies.length,
              route: FinanceRoutes.planRunway,
              evidence: {
                'currencies': runway.missingCurrencies.toList()..sort(),
              },
            ),
          );
        }
      }
      return List.unmodifiable(items);
    });

final financialInboxProvider =
    FutureProvider.autoDispose<List<FinancialInboxItem>>((ref) async {
      final repository = await ref.watch(
        financialSignalRepositoryProvider.future,
      );
      final candidates = ref.watch(financialSignalCandidatesProvider);
      return repository.reconcile(
        candidates,
        now: ref.watch(financialInboxNowProvider),
      );
    });
