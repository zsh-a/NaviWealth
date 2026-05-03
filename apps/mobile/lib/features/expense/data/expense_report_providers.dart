import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/repositories/journal_entry_providers.dart';
import '../../../design_system/preferences/theme_preferences.dart';
import '../../../domain/services/currency_converter.dart';
import '../../../domain/values/money.dart';
import '../../home/data/dashboard_providers.dart';
import '../domain/expense_report.dart';
import '../domain/expense_report_aggregator.dart';
import '../domain/expense_report_range.dart';
import '../domain/monthly_expense_derivation.dart';

/// Currently selected range chip on the expense report page. Mirrors the
/// dashboard's chip-state pattern so a screen rebuild doesn't reset
/// what the user picked.
final expenseReportRangePresetProvider =
    StateProvider<ExpenseReportRangePreset>(
  (ref) => ExpenseReportRangePreset.m3,
);

final expenseReportCustomRangeProvider =
    StateProvider<({DateTime from, DateTime to})?>((ref) => null);

/// Resolved [ExpenseReportRange] for the report. The bar chart renders
/// every month in this range (zero-filled gaps included); the pie + list
/// only count expenses whose `tradeDate` falls in the range.
final expenseReportRangeProvider = Provider<ExpenseReportRange>((ref) {
  final preset = ref.watch(expenseReportRangePresetProvider);
  final custom = ref.watch(expenseReportCustomRangeProvider);
  return ExpenseReportRange.resolve(
    preset: preset,
    now: DateTime.now(),
    customFrom: custom?.from,
    customTo: custom?.to,
  );
});

/// The expense report shares the dashboard's currency converter so users
/// see the same FX behaviour across the app — including the "skip
/// expenses without an FX rate" graceful degradation. When a dedicated
/// expense-side converter ships we'll override this provider in the
/// report scope rather than threading a separate one through.
final expenseReportCurrencyConverterProvider = Provider<CurrencyConverter>(
  (ref) => ref.watch(dashboardCurrencyConverterProvider),
);

/// Base currency used by the report and the FIRE auto-derivation. Same
/// source as the dashboard so totals line up across screens.
final expenseReportBaseCurrencyProvider = Provider<String>(
  (ref) => ref.watch(dashboardBaseCurrencyProvider),
);

/// Live aggregated [ExpenseReport]. Re-computes whenever the range
/// or expenses change.
final expenseReportProvider = Provider<AsyncValue<ExpenseReport>>((ref) {
  final expensesAsync = ref.watch(journalExpensesStreamProvider);
  final range = ref.watch(expenseReportRangeProvider);
  final converter = ref.watch(expenseReportCurrencyConverterProvider);
  final base = ref.watch(expenseReportBaseCurrencyProvider);

  if (expensesAsync.isLoading) {
    return const AsyncValue.loading();
  }
  final err = expensesAsync.error;
  if (err != null) {
    return AsyncValue.error(
      err,
      expensesAsync.stackTrace ?? StackTrace.current,
    );
  }
  final aggregator =
      ExpenseReportAggregator(converter: converter, baseCurrency: base);
  final report = aggregator.aggregate(
    expenses: expensesAsync.value ?? const [],
    range: range,
  );
  return AsyncValue.data(report);
});

// ---------- FIRE monthly-expense derivation ----------

/// Window (in completed months) used by the FIRE auto-derivation. The
/// description calls out "近 3 个月平均" as the default; the user can
/// nudge it to 6 / 12 from the FIRE settings UI when that lands.
final monthlyExpensePreferencesProvider =
    StateNotifierProvider<MonthlyExpensePreferencesController,
        MonthlyExpensePreferences>(
  (ref) => MonthlyExpensePreferencesController(
    ref.watch(sharedPreferencesProvider),
  ),
);

/// Auto-derived rolling average. Pure read — does not consult overrides.
final autoMonthlyExpenseProvider = Provider<AsyncValue<MonthlyExpenseAverage>>(
  (ref) {
    final expensesAsync = ref.watch(journalExpensesStreamProvider);
    final converter = ref.watch(expenseReportCurrencyConverterProvider);
    final base = ref.watch(expenseReportBaseCurrencyProvider);
    final prefs = ref.watch(monthlyExpensePreferencesProvider);

    if (expensesAsync.isLoading) return const AsyncValue.loading();
    final err = expensesAsync.error;
    if (err != null) {
      return AsyncValue.error(
        err,
        expensesAsync.stackTrace ?? StackTrace.current,
      );
    }
    final derivation = MonthlyExpenseDerivation(
      converter: converter,
      baseCurrency: base,
    );
    final average = derivation.compute(
      expenses: expensesAsync.value ?? const [],
      windowMonths: prefs.windowMonths,
    );
    return AsyncValue.data(average);
  },
);

/// What the FIRE dashboard should display: the manual override (if set)
/// otherwise the rolling average. Always carries the auto value so the
/// override UI can render "auto would be ¥X" alongside the manual figure.
final effectiveMonthlyExpenseProvider =
    Provider<AsyncValue<EffectiveMonthlyExpense>>((ref) {
  final autoAsync = ref.watch(autoMonthlyExpenseProvider);
  final prefs = ref.watch(monthlyExpensePreferencesProvider);
  final base = ref.watch(expenseReportBaseCurrencyProvider);

  return autoAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
    data: (auto) {
      final override = prefs.override;
      final source = override == null
          ? MonthlyExpenseSource.auto
          : MonthlyExpenseSource.manual;
      final value = override == null
          ? auto.average
          : Money(override, base);
      return AsyncValue.data(
        EffectiveMonthlyExpense(source: source, value: value, auto: auto),
      );
    },
  );
});

/// Persistence shape for the user's monthly-expense preferences. Backs the
/// FIR-57 "月支出 (auto / manual)" toggle: [windowMonths] feeds the
/// rolling-average derivation, [override] short-circuits it when the user
/// wants to hand-tune the FIRE projection.
@immutable
class MonthlyExpensePreferences {
  const MonthlyExpensePreferences({
    required this.windowMonths,
    this.override,
  });

  /// Rolling-window length, in *complete* months, used by the auto
  /// derivation. Clamped to [MonthlyExpensePreferencesController.minWindow]
  /// .. [MonthlyExpensePreferencesController.maxWindow].
  final int windowMonths;

  /// Manual override, in the base currency. `null` means "use the auto
  /// derivation". Stored as [Decimal] so the projection math stays exact.
  final Decimal? override;

  MonthlyExpensePreferences copyWith({
    int? windowMonths,
    Object? override = _sentinel,
  }) {
    return MonthlyExpensePreferences(
      windowMonths: windowMonths ?? this.windowMonths,
      override: override == _sentinel ? this.override : override as Decimal?,
    );
  }

  static const Object _sentinel = Object();
}

/// Persists the FIRE monthly-expense override + window via SharedPreferences.
/// Per-device for now — when FIR-57 lands we may move this onto the FIRE
/// `Goal` row so the override syncs, but the public read API (the providers
/// above) stays the same either way.
class MonthlyExpensePreferencesController
    extends StateNotifier<MonthlyExpensePreferences> {
  MonthlyExpensePreferencesController(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static const _windowKey = 'naviwealth.expense.monthly.window';
  static const _overrideKey = 'naviwealth.expense.monthly.override';

  /// Default rolling window from the FIR-70 description.
  static const int defaultWindow = 3;

  static const int minWindow = 1;
  static const int maxWindow = 12;

  static MonthlyExpensePreferences _load(SharedPreferences p) {
    final stored = p.getInt(_windowKey) ?? defaultWindow;
    final clamped = stored.clamp(minWindow, maxWindow);
    final overrideStr = p.getString(_overrideKey);
    Decimal? override;
    if (overrideStr != null && overrideStr.isNotEmpty) {
      override = Decimal.tryParse(overrideStr);
    }
    return MonthlyExpensePreferences(
      windowMonths: clamped,
      override: override,
    );
  }

  Future<void> setWindow(int months) async {
    final clamped = months.clamp(minWindow, maxWindow);
    state = state.copyWith(windowMonths: clamped);
    await _prefs.setInt(_windowKey, clamped);
  }

  Future<void> setOverride(Decimal? value) async {
    state = state.copyWith(override: value);
    if (value == null) {
      await _prefs.remove(_overrideKey);
    } else {
      await _prefs.setString(_overrideKey, value.toString());
    }
  }

  /// Clear the override and revert the FIRE display to the auto value.
  Future<void> useAuto() => setOverride(null);
}
