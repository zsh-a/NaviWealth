import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/cash_flow_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/recurring_transaction_providers.dart';
import 'package:naviwealth/features/finance/cashflow/data/recurring_transaction_repository.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_kind.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/fire/data/fire_providers.dart';

import '../domain/money_runway.dart';

final moneyRunwayNowProvider = Provider<DateTime>(
  (ref) => DateTime.now().toUtc(),
);

final moneyRunwayProvider = Provider<AsyncValue<MoneyRunwaySnapshot>>((ref) {
  final dashboard = ref.watch(dashboardSnapshotProvider);
  final recurring = ref.watch(recurringTransactionsProvider);
  final events = ref.watch(cashFlowEventsProvider);
  final accounts = ref.watch(allAccountsStreamProvider);

  if (dashboard.isLoading ||
      recurring.isLoading ||
      events.isLoading ||
      accounts.isLoading) {
    return const AsyncValue<MoneyRunwaySnapshot>.loading();
  }
  final error =
      dashboard.error ?? recurring.error ?? events.error ?? accounts.error;
  if (error != null) {
    return AsyncValue<MoneyRunwaySnapshot>.error(error, StackTrace.current);
  }

  try {
    final snapshot = dashboard.requireValue;
    final now = ref.watch(moneyRunwayNowProvider);
    final baseCurrency = snapshot.baseCurrency;
    final converter = ref.watch(cashFlowCurrencyConverterProvider);
    final accountMap = <String, Account>{
      for (final account in accounts.requireValue) account.id: account,
    };
    final window = RecurringForecastWindow(
      from: now,
      to: now.add(const Duration(days: 90)),
    );
    final upcoming = ref.watch(upcomingRecurringEventsProvider(window));
    final missingCurrencies = <String>{};
    final flows = <RunwayScheduledFlow>[];

    for (final occurrence in upcoming) {
      final template = JournalBuildTemplateCodec.decode(
        occurrence.templateJournalBuildJson,
      );
      var amount = Decimal.zero;
      for (final posting in template.postings) {
        final account = accountMap[posting.accountId];
        if (account == null || !_isLiquidAccount(account)) continue;
        if (posting.unit.contains(':')) continue;
        if (posting.unit.toUpperCase() == baseCurrency.toUpperCase()) {
          amount += posting.units;
          continue;
        }
        try {
          amount += converter
              .convert(
                Money(posting.units, posting.unit),
                baseCurrency,
                on: occurrence.occurrenceDate,
              )
              .amount;
        } on Object {
          missingCurrencies.add(posting.unit.toUpperCase());
        }
      }
      if (amount == Decimal.zero) continue;
      flows.add(
        RunwayScheduledFlow(
          id:
              '${occurrence.recurringTransactionId}:'
              '${occurrence.occurrenceDate.toIso8601String()}',
          date: occurrence.occurrenceDate,
          amount: amount,
          label: template.entry.payee ?? template.entry.narration,
        ),
      );
    }

    final history = events.requireValue.events
        .where((event) {
          final age = now.difference(event.date.toUtc());
          return event.kind == CashFlowKind.expense &&
              !event.isForecast &&
              !age.isNegative &&
              age <= const Duration(days: 90);
        })
        .toList(growable: false);
    var historicalOutflow = Decimal.zero;
    for (final event in history) {
      historicalOutflow += event.signedAmount.abs();
    }
    final observedDays = history.isEmpty
        ? 0
        : now
              .difference(
                history
                    .map((e) => e.date)
                    .reduce((a, b) => a.isBefore(b) ? a : b),
              )
              .inDays
              .clamp(1, 90);
    final historicalDaily = observedDays == 0
        ? Decimal.zero
        : (historicalOutflow / Decimal.fromInt(observedDays)).toDecimal(
            scaleOnInfinitePrecision: 4,
          );
    var scheduledOutflow = Decimal.zero;
    for (final flow in flows) {
      if (flow.amount < Decimal.zero) scheduledOutflow += -flow.amount;
    }
    final scheduledDaily = (scheduledOutflow / Decimal.fromInt(90)).toDecimal(
      scaleOnInfinitePrecision: 4,
    );
    final variableDaily = historicalDaily > scheduledDaily
        ? historicalDaily - scheduledDaily
        : Decimal.zero;
    final averageMonthlyExpense = historicalDaily * Decimal.fromInt(30);
    final plan = ref.watch(firePlanProvider);
    final configuredMonthlyExpense = plan.monthlyExpenses > Decimal.zero
        ? plan.monthlyExpenses
        : averageMonthlyExpense;
    final reserveMonths = plan.targetCashBucketMonths > 0
        ? plan.targetCashBucketMonths
        : 3;
    final reserveTarget =
        configuredMonthlyExpense * Decimal.fromInt(reserveMonths);
    final startingBalance = computeLiquidAssets(snapshot).amount;
    final confidence = missingCurrencies.isNotEmpty || observedDays < 30
        ? MoneyRunwayConfidence.low
        : flows.isEmpty
        ? MoneyRunwayConfidence.medium
        : MoneyRunwayConfidence.high;

    return AsyncValue<MoneyRunwaySnapshot>.data(
      buildMoneyRunway(
        asOf: now,
        currency: baseCurrency,
        startingBalance: startingBalance,
        reserveTarget: reserveTarget,
        averageMonthlyExpense: configuredMonthlyExpense,
        estimatedDailyVariableOutflow: variableDaily,
        scheduledFlows: flows,
        confidence: confidence,
        missingCurrencies: missingCurrencies,
        hasData: !snapshot.isEmpty || events.requireValue.events.isNotEmpty,
      ),
    );
  } on Object catch (error, stackTrace) {
    return AsyncValue<MoneyRunwaySnapshot>.error(error, stackTrace);
  }
});

bool _isLiquidAccount(Account account) {
  if (account.archived || account.category != AccountSide.asset) return false;
  return switch (account.type) {
    AccountCategory.cash ||
    AccountCategory.bank ||
    AccountCategory.broker => true,
    AccountCategory.crypto ||
    AccountCategory.credit ||
    AccountCategory.loan ||
    AccountCategory.asset ||
    AccountCategory.liability => false,
  };
}
