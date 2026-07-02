import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';

import '../domain/cash_flow_kind.dart';
import '../domain/dividend_center.dart';
import 'cash_flow_providers.dart';

final dividendCenterNowProvider = Provider<DateTime>(
  (ref) => DateTime.now().toUtc(),
);

final dividendCenterSnapshotProvider =
    FutureProvider.autoDispose<DividendCenterSnapshot>((ref) async {
      final dividendAsync = ref.watch(dividendEventsProvider);
      final dividendEvents = dividendAsync.hasValue
          ? dividendAsync.value!
          : (await ref.watch(
              cashFlowEventsProvider.future,
            )).where((event) => event.kind == CashFlowKind.dividend).toList();

      final entries = await ref.watch(
        journalEntriesWithPostingsStreamProvider.future,
      );
      final accounts = await ref.watch(allAccountsStreamProvider.future);
      final holdings = ref.watch(holdingsSnapshotProvider).value ?? const {};
      final baseCurrency = ref.watch(cashFlowBaseCurrencyProvider);
      final converter = ref.watch(cashFlowCurrencyConverterProvider);

      return buildDividendCenterSnapshot(
        dividendEvents: dividendEvents,
        entriesById: {for (final entry in entries) entry.entry.id: entry},
        accountsById: {for (final account in accounts) account.id: account},
        holdings: holdings,
        baseCurrency: baseCurrency,
        now: ref.watch(dividendCenterNowProvider),
        convertToBaseAmount: (amount, currency, date) {
          if (currency.trim().toUpperCase() == baseCurrency) return amount;
          try {
            return converter
                .convert(Money(amount, currency), baseCurrency, on: date)
                .amount;
          } catch (_) {
            return null;
          }
        },
      );
    });
