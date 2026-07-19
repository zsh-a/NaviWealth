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
import 'package:naviwealth/features/finance/liabilities/data/providers.dart';

import '../../../../core/auth/current_user.dart';
import '../../../../core/persistence/providers.dart';
import '../domain/money_runway.dart';
import 'runway_forecast_repository.dart';

final moneyRunwayNowProvider = Provider<DateTime>(
  (ref) => DateTime.now().toUtc(),
);

final runwayForecastRepositoryProvider =
    FutureProvider<RunwayForecastRepository>((ref) async {
      final ownerUserId = ref.watch(activeUserIdProvider) ?? kLocalOnlyUserId;
      return RunwayForecastRepository(
        db: await ref.watch(appDatabaseProvider.future),
        ownerUserId: ownerUserId,
      );
    });

final runwayForecastQualityProvider =
    FutureProvider.autoDispose<RunwayForecastQuality>((ref) async {
      final repository = await ref.watch(
        runwayForecastRepositoryProvider.future,
      );
      return repository.quality();
    });

final moneyRunwayProvider = Provider<AsyncValue<MoneyRunwaySnapshot>>((ref) {
  final dashboard = ref.watch(dashboardSnapshotProvider);
  final recurring = ref.watch(recurringTransactionsProvider);
  final events = ref.watch(cashFlowEventsProvider);
  final accounts = ref.watch(allAccountsStreamProvider);
  final liabilities = ref.watch(liabilitiesStreamProvider);
  final schedules = ref.watch(allLiabilitySchedulesProvider);

  if (dashboard.isLoading ||
      recurring.isLoading ||
      events.isLoading ||
      accounts.isLoading ||
      liabilities.isLoading ||
      schedules.isLoading) {
    return const AsyncValue<MoneyRunwaySnapshot>.loading();
  }
  final error =
      dashboard.error ??
      recurring.error ??
      events.error ??
      accounts.error ??
      liabilities.error ??
      schedules.error;
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

    final liabilitiesById = {
      for (final liability in liabilities.requireValue) liability.id: liability,
    };
    for (final entry in schedules.requireValue.entries) {
      final liability = liabilitiesById[entry.key];
      if (liability == null) continue;
      for (final payment in entry.value) {
        if (payment.paidAt != null ||
            payment.dueDate.isBefore(now) ||
            payment.dueDate.isAfter(window.to)) {
          continue;
        }
        final nativeAmount = payment.principalPayment + payment.interestPayment;
        Decimal amount;
        try {
          amount = converter
              .convert(
                Money(nativeAmount, liability.currency),
                baseCurrency,
                on: payment.dueDate,
              )
              .amount;
        } on Object {
          missingCurrencies.add(liability.currency.toUpperCase());
          continue;
        }
        if (_matchesScheduledOutflow(flows, payment.dueDate, amount)) continue;
        flows.add(
          RunwayScheduledFlow(
            id: 'liability:${payment.id}',
            date: payment.dueDate,
            amount: -amount.abs(),
            label: liability.name,
          ),
        );
      }
    }
    for (final liability in liabilities.requireValue) {
      if ((schedules.requireValue[liability.id]?.isNotEmpty ?? false) ||
          liability.monthlyPayment == null ||
          liability.monthlyPayment! <= Decimal.zero ||
          liability.paymentDueDay == null) {
        continue;
      }
      for (var monthOffset = 0; monthOffset <= 3; monthOffset++) {
        final month = DateTime.utc(now.year, now.month + monthOffset);
        final due = _clampedMonthDay(month, liability.paymentDueDay!);
        if (due.isBefore(now) || due.isAfter(window.to)) continue;
        Decimal amount;
        try {
          amount = converter
              .convert(
                Money(liability.monthlyPayment!, liability.currency),
                baseCurrency,
                on: due,
              )
              .amount;
        } on Object {
          missingCurrencies.add(liability.currency.toUpperCase());
          continue;
        }
        if (_matchesScheduledOutflow(flows, due, amount)) continue;
        flows.add(
          RunwayScheduledFlow(
            id: 'liability:${liability.id}:${due.year}-${due.month}',
            date: due,
            amount: -amount.abs(),
            label: liability.name,
          ),
        );
      }
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
    final completeness =
        ((observedDays / 60).clamp(0, 1) * 0.5 +
                (flows.isEmpty ? 0 : 0.25) +
                (missingCurrencies.isEmpty ? 0.25 : 0))
            .clamp(0.0, 1.0);
    final forecastError = ref
        .watch(runwayForecastQualityProvider)
        .value
        ?.meanRelativeError;
    final confidence =
        completeness < 0.5 || (forecastError != null && forecastError > 0.25)
        ? MoneyRunwayConfidence.low
        : completeness < 0.8 || (forecastError != null && forecastError > 0.10)
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
        dataCompleteness: completeness,
        historicalForecastError: forecastError,
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
    AccountCategory.cash || AccountCategory.bank => true,
    AccountCategory.broker => false,
    AccountCategory.crypto ||
    AccountCategory.credit ||
    AccountCategory.loan ||
    AccountCategory.asset ||
    AccountCategory.liability => false,
  };
}

bool _matchesScheduledOutflow(
  List<RunwayScheduledFlow> flows,
  DateTime date,
  Decimal amount,
) {
  final day = DateTime.utc(date.year, date.month, date.day);
  return flows.any((flow) {
    if (flow.amount >= Decimal.zero) return false;
    final flowDay = DateTime.utc(
      flow.date.year,
      flow.date.month,
      flow.date.day,
    );
    return flowDay == day && flow.amount.abs() == amount.abs();
  });
}

DateTime _clampedMonthDay(DateTime month, int requestedDay) {
  final lastDay = DateTime.utc(month.year, month.month + 1, 0).day;
  return DateTime.utc(month.year, month.month, requestedDay.clamp(1, lastDay));
}
