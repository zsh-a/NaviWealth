import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';

import '../domain/cash_flow_event.dart';
import '../domain/cash_flow_kind.dart';
import '../domain/dividend_center.dart';
import 'cash_flow_ledger_adapters.dart';
import 'cash_flow_providers.dart';

final dividendCenterNowProvider = Provider<DateTime>(
  (ref) => DateTime.now().toUtc(),
);

final dividendCenterSnapshotProvider =
    FutureProvider.autoDispose<DividendCenterSnapshot>((ref) async {
      final dividendAsync = ref.watch(dividendEventsProvider);
      final cashFlowFuture = ref.watch(cashFlowEventsProvider.future);
      final entriesFuture = ref.watch(
        journalEntriesWithPostingsStreamProvider.future,
      );
      final accountsFuture = ref.watch(allAccountsStreamProvider.future);
      final assetsFuture = ref.watch(allAssetsStreamProvider.future);
      final holdingsAsync = ref.watch(holdingsSnapshotProvider);
      final holdingsFuture = ref.watch(holdingsSnapshotProvider.future);
      final baseCurrency = ref.watch(cashFlowBaseCurrencyProvider);
      final converter = ref.watch(cashFlowCurrencyConverterProvider);
      final now = ref.watch(dividendCenterNowProvider);

      final cashFlow = dividendAsync.hasValue
          ? dividendAsync.requireValue
          : _dividendCashFlowSnapshot(await cashFlowFuture);
      final entries = await entriesFuture;
      final accounts = await accountsFuture;
      final assets = await assetsFuture;
      final holdings = holdingsAsync.hasValue
          ? holdingsAsync.requireValue
          : await holdingsFuture;

      return buildDividendCenterSnapshot(
        dividendEvents: cashFlow.events,
        entriesById: {
          for (final entry in entries)
            entry.entry.id: entry.toCashFlowLedgerEntry(),
        },
        accountsById: {for (final account in accounts) account.id: account},
        assetLabelsById: {
          for (final asset in assets)
            asset.id: (asset.name?.trim().isNotEmpty ?? false)
                ? asset.name!.trim()
                : asset.symbol,
        },
        holdings: holdings,
        baseCurrency: baseCurrency,
        now: now,
        fxExclusions: cashFlow.fxExclusions,
        convertToBaseAmount: (amount, currency, date) {
          if (currency.trim().toUpperCase() == baseCurrency) return amount;
          try {
            return converter
                .convert(Money(amount, currency), baseCurrency, on: date)
                .amount;
          } on FxRateNotFoundError {
            return null;
          }
        },
      );
    });

CashFlowEventsSnapshot _dividendCashFlowSnapshot(
  CashFlowEventsSnapshot snapshot,
) {
  return CashFlowEventsSnapshot(
    events: List.unmodifiable(
      snapshot.events.where((event) => event.kind == CashFlowKind.dividend),
    ),
    fxExclusions: List.unmodifiable(
      snapshot.fxExclusions.where(
        (event) => event.kind == CashFlowKind.dividend,
      ),
    ),
  );
}
