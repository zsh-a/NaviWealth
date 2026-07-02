import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/async/isolate_runner.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';

import '../domain/cash_flow_aggregator.dart';
import '../domain/cash_flow_classifier.dart';
import '../domain/cash_flow_event.dart';
import '../domain/cash_flow_kind.dart';
import 'cash_flow_ledger_adapters.dart';

final cashFlowEventsProvider = StreamProvider.autoDispose<List<CashFlowEvent>>((
  ref,
) async* {
  final entriesFuture = ref.watch(
    journalEntriesWithPostingsStreamProvider.future,
  );
  final accountsFuture = ref.watch(allAccountsStreamProvider.future);
  final converter = ref.watch(cashFlowCurrencyConverterProvider);
  final baseCurrency = ref.watch(cashFlowBaseCurrencyProvider);

  final entries = await entriesFuture;
  final accounts = await accountsFuture;
  if (!ref.mounted) return;

  final accountsById = {for (final account in accounts) account.id: account};

  final events = <CashFlowEvent>[];
  for (final entry in entries) {
    final event = classifyCashFlowEvent(
      entry.toCashFlowLedgerEntry(),
      resolveAccount: accountsById.get,
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
    if (event != null) events.add(event);
  }
  yield List.unmodifiable(events);
});

final cashFlowSummaryProvider = FutureProvider.autoDispose
    .family<CashFlowSummary, CashFlowSummaryRequest>((ref, request) async {
      final eventsFuture = ref.watch(cashFlowEventsProvider.future);
      final baseCurrency = ref.watch(cashFlowBaseCurrencyProvider);
      final events = await eventsFuture;
      return runInIsolate(
        () => aggregateCashFlow(
          events,
          period: request.period,
          baseCurrency: baseCurrency,
        ),
      );
    });

final dividendEventsProvider =
    Provider.autoDispose<AsyncValue<List<CashFlowEvent>>>((ref) {
      final events = ref.watch(cashFlowEventsProvider);
      return events.whenData(
        (value) => List.unmodifiable(
          value.where((event) => event.kind == CashFlowKind.dividend),
        ),
      );
    });

final cashFlowBaseCurrencyProvider = Provider<String>(
  (ref) => ref.watch(baseCurrencyProvider),
);

final cashFlowNowProvider = Provider<DateTime>((ref) => DateTime.now().toUtc());

final cashFlowCurrencyConverterProvider = Provider<CurrencyConverter>((ref) {
  final rates = ref.watch(fxRatesStreamProvider).value ?? const [];
  return FxRateCurrencyConverter(InMemoryFxRateLookup(rates));
});

extension _AccountLookup on Map<String, Account> {
  Account? get(String accountId) => this[accountId];
}
