import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/audit/domain_event.dart';
import 'package:naviwealth/core/audit/event_log_reader.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/features/finance/cashflow/domain/budget_signal.dart';
import 'package:naviwealth/features/finance/cashflow/domain/budget_spend_mapper.dart';
import 'package:naviwealth/features/finance/cashflow/domain/budget_summary.dart';
import 'package:naviwealth/features/finance/data/preferences/base_currency_preference.dart';
import 'package:naviwealth/features/finance/domain/fx/currency_converter.dart';
import 'package:naviwealth/features/finance/domain/fx/fx_rate.dart' as dom;
import 'package:naviwealth/features/finance/domain/fx/money.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/asset.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';

import 'account_repository.dart';
import 'budget_repository.dart';
import 'fx_rate_repository.dart';
import 'journal_entry_providers.dart';
import 'manual_asset_repository.dart';
import 'price_repository.dart';
import 'securities_asset_repository.dart';

final accountRepositoryProvider = FutureProvider<AccountRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  return AccountRepository(db: db, outbox: outbox, stamper: stamper);
});

final manualAssetRepositoryProvider = FutureProvider<ManualAssetRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  final jeRepo = await ref.watch(journalEntryRepositoryProvider.future);
  final priceRepo = await ref.watch(priceRepositoryProvider.future);
  return ManualAssetRepository(
    db: db,
    outbox: outbox,
    stamper: stamper,
    journalEntryRepo: jeRepo,
    priceRepo: priceRepo,
  );
});

/// Securities-class assets (stock / ETF / fund / bond / crypto).
/// Sibling to [manualAssetRepositoryProvider]; the two repos write into
/// the same `assets` table but own different identity schemes.
final securitiesAssetRepositoryProvider =
    FutureProvider<SecuritiesAssetRepository>((ref) async {
      final db = await ref.watch(appDatabaseProvider.future);
      final outbox = await ref.watch(outboxStoreProvider.future);
      final stamper = await ref.watch(mutationStamperProvider.future);
      return SecuritiesAssetRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
      );
    });

final systemAccountsSeedProvider = FutureProvider<void>((ref) async {
  final repo = await ref.watch(accountRepositoryProvider.future);
  await repo.seedSystemAccounts();
});

/// Live stream of all non-archived, non-deleted accounts. UIs watch this
/// for the account list / picker.
///
/// Also seeds the income / expense / equity virtual system
/// accounts the first time the user opens any account-aware surface, so
/// the P2-A double-entry posting model has counter-accounts ready before
/// the first cash flow is recorded. The seed is idempotent (deterministic
/// ids) so doing it on every cold start is cheap.
final accountsStreamProvider = StreamProvider.autoDispose<List<Account>>((
  ref,
) async* {
  await ref.watch(systemAccountsSeedProvider.future);
  final repo = await ref.watch(accountRepositoryProvider.future);
  final ownerUserId = await ref.watch(currentUserIdProvider)();
  yield* repo.watchActiveForOwner(ownerUserId);
});

/// Live stream of all active accounts **including** system accounts.
/// Used by the expense category picker which needs seeded system expense
/// accounts (dining, coffee, transport, etc.) to be visible.
final allAccountsStreamProvider = StreamProvider.autoDispose<List<Account>>((
  ref,
) async* {
  await ref.watch(systemAccountsSeedProvider.future);
  final ownerUserId = await ref.watch(currentUserIdProvider)();
  final repo = await ref.watch(accountRepositoryProvider.future);
  yield* repo.watchActiveIncludingSystem(ownerUserId);
});

/// Live stream of all non-deleted manual-valuation assets (cash, deposits,
/// wealth products). The Assets tab subscribes to this directly.
final manualAssetsStreamProvider = StreamProvider.autoDispose<List<Asset>>((
  ref,
) async* {
  final repo = await ref.watch(manualAssetRepositoryProvider.future);
  yield* repo.watchManual();
});

/// Live stream of all non-deleted securities-class assets (stock / ETF /
/// mutual fund / bond / crypto). The Assets tab subscribes to this so the
/// portfolio's tradable instruments surface alongside cash and physical
/// assets — without it, freshly recorded trades have no listing surface
/// outside the holdings/dashboard pipeline.
final securitiesAssetsStreamProvider = StreamProvider.autoDispose<List<Asset>>((
  ref,
) async* {
  final repo = await ref.watch(securitiesAssetRepositoryProvider.future);
  yield* repo.watchSecurities(types: kSecuritiesAssetTypes);
});

/// Repository for the local `fx_rates` table. Not synced (FX rates are
/// global market data, not user data) so this repo bypasses the outbox.
final fxRateRepositoryProvider = FutureProvider<FxRateRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return FxRateRepository(db: db);
});

final priceRepositoryProvider = FutureProvider<PriceRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  return PriceRepository(db: db, outbox: outbox, stamper: stamper);
});

/// Monthly category budgets backed
/// by the `budgets` SyncableTable.
final budgetRepositoryProvider = FutureProvider<BudgetRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  final ownerUserId = await ref.watch(currentUserIdProvider)();
  return BudgetRepository(
    db: db,
    outbox: outbox,
    stamper: stamper,
    ownerUserId: ownerUserId,
  );
});

/// Live stream of every non-deleted budget, ordered (periodMonth desc,
/// categoryId asc). UIs that show "this month's budgets" subscribe via
/// [budgetsForMonthProvider] instead; this raw stream powers the budget
/// management list.
final budgetsStreamProvider = StreamProvider.autoDispose<List<BudgetRow>>((
  ref,
) async* {
  final repo = await ref.watch(budgetRepositoryProvider.future);
  yield* repo.watchAll();
});

/// Live stream of budgets for a specific `YYYY-MM` calendar month. The
/// family key is the month string — UIs key on the displayed month so
/// switching months tears down the prior subscription cleanly.
final budgetsForMonthProvider = StreamProvider.autoDispose
    .family<List<BudgetRow>, String>((ref, periodMonth) async* {
      final repo = await ref.watch(budgetRepositoryProvider.future);
      yield* repo.watchByMonth(periodMonth);
    });

/// Pure derivation of the budget posture for a given month. FIRE and
/// reporting surfaces subscribe to this rather than to budgets + postings
/// directly, so "budget overspend nudges safetyLevel" remains one provider
/// read.
/// This keeps the Budget → FIRE dependency one-way and read-model based.
final monthlyBudgetSignalProvider = Provider.autoDispose
    .family<AsyncValue<BudgetSignal>, String>((ref, periodMonth) {
      final summaryAsync = ref.watch(monthlyBudgetSummaryProvider(periodMonth));
      if (summaryAsync.hasError) {
        return AsyncValue.error(
          summaryAsync.error!,
          summaryAsync.stackTrace ?? StackTrace.current,
        );
      }
      if (!summaryAsync.hasValue) return const AsyncValue.loading();
      return AsyncValue.data(
        summaryAsync.requireValue.mismatchedCount > 0
            ? BudgetSignal.noData
            : budgetSignalFor(summaryAsync.requireValue.summary),
      );
    });

typedef MonthlyBudgetSummaryRead = ({
  MonthlyBudgetSummary summary,
  int mismatchedCount,
});

final monthlyBudgetSummaryProvider = Provider.autoDispose
    .family<AsyncValue<MonthlyBudgetSummaryRead>, String>((ref, periodMonth) {
      final budgetsAsync = ref.watch(budgetsForMonthProvider(periodMonth));
      final expensesAsync = ref.watch(journalExpensesStreamProvider);
      final ratesAsync = ref.watch(fxRatesStreamProvider);
      if (budgetsAsync.hasError) {
        return AsyncValue.error(
          budgetsAsync.error!,
          budgetsAsync.stackTrace ?? StackTrace.current,
        );
      }
      if (expensesAsync.hasError) {
        return AsyncValue.error(
          expensesAsync.error!,
          expensesAsync.stackTrace ?? StackTrace.current,
        );
      }
      if (ratesAsync.hasError) {
        return AsyncValue.error(
          ratesAsync.error!,
          ratesAsync.stackTrace ?? StackTrace.current,
        );
      }
      if (!budgetsAsync.hasValue || !expensesAsync.hasValue) {
        return const AsyncValue.loading();
      }

      final rows = budgetsAsync.requireValue;
      final targetCurrency = ref.watch(baseCurrencyProvider).toUpperCase();
      final converter = FxRateCurrencyConverter(
        InMemoryFxRateLookup(ratesAsync.value ?? const <dom.FxRate>[]),
      );
      var missingExpenseFxCount = 0;
      final spendByCategoryId = buildBudgetSpendByCategoryId(
        periodMonth: periodMonth,
        expenses: expensesAsync.requireValue,
        targetCurrency: targetCurrency,
        converter: converter,
        onMissingFx: () => missingExpenseFxCount++,
      );
      final budgetPlans = rows.map((row) {
        final plan = _budgetCategoryPlanFromRow(row);
        if (plan.currency.toUpperCase() == targetCurrency) return plan;
        try {
          final converted = converter.convert(
            Money(plan.amount, plan.currency),
            targetCurrency,
            on: _budgetValuationDate(periodMonth),
          );
          return BudgetCategoryPlan(
            categoryId: plan.categoryId,
            periodMonth: plan.periodMonth,
            amount: converted.amount,
            currency: converted.currency,
            deletedAt: plan.deletedAt,
          );
        } on FxRateNotFoundError {
          // Keep the original row so the summary reports it as unresolved
          // instead of presenting an incomplete total as authoritative.
          return plan;
        }
      });
      final res = buildMonthlyBudgetSummary(
        periodMonth: periodMonth,
        budgets: budgetPlans,
        spendByCategoryId: spendByCategoryId,
        targetCurrency: targetCurrency,
      );
      return AsyncValue.data((
        summary: res.summary,
        mismatchedCount: res.mismatchedCount + missingExpenseFxCount,
      ));
    });

DateTime _budgetValuationDate(String periodMonth) {
  final parts = periodMonth.split('-');
  final year = int.tryParse(parts.first);
  final month = parts.length > 1 ? int.tryParse(parts[1]) : null;
  if (year == null || month == null) return DateTime.now();
  return DateTime(year, month + 1, 0);
}

BudgetCategoryPlan _budgetCategoryPlanFromRow(BudgetRow row) {
  return BudgetCategoryPlan(
    categoryId: row.categoryId,
    periodMonth: row.periodMonth,
    amount: row.amount,
    currency: row.currency,
    deletedAt: row.deletedAt,
  );
}

/// Live stream of every recorded FX rate. The dashboard converter and the
/// FX-rate management page both watch this so a manual rate insert
/// reactively flows into every consumer.
final fxRatesStreamProvider = StreamProvider.autoDispose<List<dom.FxRate>>((
  ref,
) async* {
  final repo = await ref.watch(fxRateRepositoryProvider.future);
  yield* repo.watchAll();
});

/// Read access over the local audit ledger (`domain_event_log`).
/// UIs that render an entity's "change history" subscribe to one of the
/// per-entity providers below; this provider exposes the raw reader for
/// dev / maintenance tooling.
final eventLogReaderProvider = FutureProvider<EventLogReader>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return EventLogReader(db);
});

/// Per-entity event timeline. Family is keyed by `(table, id)` pair,
/// matching the storage shape, so e.g. asset detail pages call
/// `eventTimelineProvider((entityTable: 'assets', entityId: assetId))`.
final eventTimelineProvider = StreamProvider.autoDispose
    .family<List<DomainEvent>, ({String entityTable, String entityId})>((
      ref,
      key,
    ) async* {
      final reader = await ref.watch(eventLogReaderProvider.future);
      yield* reader.watchByEntity(
        entityTable: key.entityTable,
        entityId: key.entityId,
      );
    });
