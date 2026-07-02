import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/dividend_forecast.dart';
import 'package:naviwealth/features/finance/investment/domain/models/cash_dividend.dart';
import 'package:naviwealth/features/finance/investment/domain/models/corporate_actions.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import '../domain/dividend_center.dart';
import 'dividend_center_providers.dart';

final dividendForecastDeclaredActionsProvider =
    Provider.autoDispose<List<CorporateAction>>((ref) {
      return ref.watch(recordedCorporateActionsProvider).value ??
          const <CorporateAction>[];
    });

final dividendForecast12mProvider =
    FutureProvider.autoDispose<ProjectedDividend>((ref) async {
      final center = await ref.watch(dividendCenterSnapshotProvider.future);
      final holdings = await ref.watch(holdingsSnapshotProvider.future);
      final now = ref.watch(dividendCenterNowProvider);
      final history = _historyFromDividendCenter(center, holdings);
      const service = DividendForecastService();
      return service.forecast(
        holdings: holdings.values,
        history: history,
        declared: ref.watch(dividendForecastDeclaredActionsProvider),
        horizonEnd: _addMonths(now.toUtc(), 12),
      );
    });

List<CashDividend> _historyFromDividendCenter(
  DividendCenterSnapshot center,
  Map<String, HoldingSnapshot> holdings,
) {
  return [
    for (final event in center.events)
      CashDividend(
        id: event.event.journalEntryId,
        transactionId: event.event.journalEntryId,
        accountId: event.event.accountId,
        assetId: event.assetId,
        currency: center.baseCurrency,
        effectiveDate: event.event.date,
        shareCount: holdings[event.assetId]?.quantity ?? Decimal.zero,
        amountPerShare: _amountPerShare(
          event.grossInBase,
          holdings[event.assetId],
        ),
        grossAmount: event.grossInBase,
        withholdingTax: event.withholdingInBase,
        netAmount: event.netInBase,
        reinvested: false,
      ),
  ];
}

Decimal _amountPerShare(Decimal amount, HoldingSnapshot? holding) {
  if (holding == null || holding.quantity <= Decimal.zero) return Decimal.zero;
  return (amount / holding.quantity).toDecimal(scaleOnInfinitePrecision: 8);
}

DateTime _addMonths(DateTime date, int delta) {
  final utc = date.toUtc();
  final monthIndex = utc.year * 12 + utc.month - 1 + delta;
  final year = monthIndex ~/ 12;
  final month = monthIndex % 12 + 1;
  final lastDay = DateTime.utc(year, month + 1, 0).day;
  final day = utc.day > lastDay ? lastDay : utc.day;
  return DateTime.utc(year, month, day);
}
