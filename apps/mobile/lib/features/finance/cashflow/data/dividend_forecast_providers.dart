import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/dividend_forecast.dart';
import 'package:naviwealth/features/finance/investment/domain/models/cash_dividend.dart';
import 'package:naviwealth/features/finance/investment/domain/models/corporate_actions.dart';
import '../domain/dividend_center.dart';
import 'cash_flow_providers.dart';
import 'dividend_center_providers.dart';

final dividendForecastDeclaredActionsProvider =
    Provider.autoDispose<List<CorporateAction>>((ref) {
      return ref.watch(recordedCorporateActionsProvider).value ??
          const <CorporateAction>[];
    });

final dividendForecast12mProvider =
    FutureProvider.autoDispose<ProjectedDividend>((ref) async {
      final centerFuture = ref.watch(dividendCenterSnapshotProvider.future);
      final holdingsFuture = ref.watch(holdingsSnapshotProvider.future);
      final now = ref.watch(dividendCenterNowProvider);
      final declared = ref.watch(dividendForecastDeclaredActionsProvider);
      final converter = ref.watch(cashFlowCurrencyConverterProvider);
      final center = await centerFuture;
      final holdings = await holdingsFuture;
      final history = _historyFromDividendCenter(center);
      final normalized = normalizeDeclaredDividendActions(
        actions: declared,
        baseCurrency: center.baseCurrency,
        converter: converter,
      );
      const service = DividendForecastService();
      final projection = service.forecast(
        holdings: holdings.values,
        history: history,
        declared: normalized.actions,
        horizonEnd: _addMonths(now.toUtc(), 12),
      );
      return projection.withExcludedDeclaredCurrencies(
        normalized.excludedCurrencies,
      );
    });

typedef NormalizedDeclaredDividendActions = ({
  List<CorporateAction> actions,
  Set<String> excludedCurrencies,
});

NormalizedDeclaredDividendActions normalizeDeclaredDividendActions({
  required Iterable<CorporateAction> actions,
  required String baseCurrency,
  required CurrencyConverter converter,
}) {
  final base = baseCurrency.trim().toUpperCase();
  final normalized = <CorporateAction>[];
  final excluded = <String>{};
  for (final action in actions) {
    try {
      normalized.add(switch (action) {
        CashDividendAction value => CashDividendAction(
          id: value.id,
          assetId: value.assetId,
          effectiveDate: value.effectiveDate,
          transactionId: value.transactionId,
          accountId: value.accountId,
          currency: base,
          amountPerShare: _convertToBase(
            value.amountPerShare,
            value.currency,
            base,
            value.effectiveDate,
            converter,
          ),
          withholdingTax: _convertToBase(
            value.withholdingTax,
            value.currency,
            base,
            value.effectiveDate,
            converter,
          ),
        ),
        DripAction value => DripAction(
          id: value.id,
          assetId: value.assetId,
          effectiveDate: value.effectiveDate,
          transactionId: value.transactionId,
          accountId: value.accountId,
          currency: base,
          amountPerShare: _convertToBase(
            value.amountPerShare,
            value.currency,
            base,
            value.effectiveDate,
            converter,
          ),
          pricePerUnit: _convertToBase(
            value.pricePerUnit,
            value.currency,
            base,
            value.effectiveDate,
            converter,
          ),
          withholdingTax: _convertToBase(
            value.withholdingTax,
            value.currency,
            base,
            value.effectiveDate,
            converter,
          ),
          fee: _convertToBase(
            value.fee,
            value.currency,
            base,
            value.effectiveDate,
            converter,
          ),
        ),
        _ => action,
      });
    } on FxRateNotFoundError {
      final currency = switch (action) {
        CashDividendAction value => value.currency,
        DripAction value => value.currency,
        _ => null,
      };
      if (currency != null) excluded.add(currency.trim().toUpperCase());
    }
  }
  return (
    actions: List.unmodifiable(normalized),
    excludedCurrencies: Set.unmodifiable(excluded),
  );
}

Decimal _convertToBase(
  Decimal amount,
  String currency,
  String baseCurrency,
  DateTime date,
  CurrencyConverter converter,
) {
  if (amount == Decimal.zero || currency.trim().toUpperCase() == baseCurrency) {
    return amount;
  }
  return converter
      .convert(Money(amount, currency), baseCurrency, on: date)
      .amount;
}

List<CashDividend> _historyFromDividendCenter(DividendCenterSnapshot center) {
  return [
    for (final event in center.events)
      CashDividend(
        id: event.event.journalEntryId,
        transactionId: event.event.journalEntryId,
        accountId: event.event.accountId,
        assetId: event.assetId,
        currency: center.baseCurrency,
        effectiveDate: event.event.date,
        shareCount: Decimal.zero,
        amountPerShare: Decimal.zero,
        grossAmount: event.grossInBase,
        withholdingTax: event.withholdingInBase,
        netAmount: event.netInBase,
        reinvested: false,
      ),
  ];
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
