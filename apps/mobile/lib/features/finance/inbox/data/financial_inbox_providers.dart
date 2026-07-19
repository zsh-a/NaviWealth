import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../composition/finance_route_paths.dart';
import '../../ingest/data/providers.dart';
import '../../runway/data/money_runway_providers.dart';
import '../../runway/domain/money_runway.dart';
import '../domain/financial_inbox.dart';

final financialInboxProvider = Provider.autoDispose<List<FinancialInboxItem>>((
  ref,
) {
  final items = <FinancialInboxItem>[];
  final pending = ref.watch(pendingIngestReviewItemsProvider).value ?? const [];
  if (pending.isNotEmpty) {
    items.add(
      FinancialInboxItem(
        id: 'import-review',
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
        FinancialInboxItem(
          id: 'runway-risk',
          kind: FinancialInboxKind.runwayRisk,
          priority: runway.status == MoneyRunwayStatus.shortfall
              ? FinancialInboxPriority.important
              : FinancialInboxPriority.attention,
          count: 1,
          route: FinanceRoutes.planRunway,
        ),
      );
    }
    if (runway.missingCurrencies.isNotEmpty) {
      items.add(
        FinancialInboxItem(
          id: 'missing-fx',
          kind: FinancialInboxKind.missingExchangeRate,
          priority: FinancialInboxPriority.attention,
          count: runway.missingCurrencies.length,
          route: FinanceRoutes.planRunway,
        ),
      );
    }
  }
  return List.unmodifiable(items);
});
