import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/drift_sync_storage.dart';
import '../../core/sync/op_outbox.dart';
import '../../domain/entities/fx_rate.dart' as dom;
import '../audit/domain_event.dart';
import '../audit/event_log_reader.dart';
import '../db/providers.dart';
import '../domain/account.dart';
import '../domain/asset.dart';
import '../domain/enums.dart';
import '../domain/expense.dart';
import '../domain/expense_category.dart';
import 'account_repository.dart';
import 'expense_category_repository.dart';
import 'expense_repository.dart';
import 'fx_rate_repository.dart';
import 'manual_asset_repository.dart';
import 'mutation_context.dart';
import 'securities_asset_repository.dart';

/// FIFO outbox bound to the local database. Mirrors the engine's outbox so
/// repos enqueue ops into the same row of the `op_outbox` table the
/// SyncEngine drains on the next push.
final outboxStoreProvider = FutureProvider<OutboxStore>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return DriftOutboxStore(db);
});

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
  return ManualAssetRepository(db: db, outbox: outbox, stamper: stamper);
});

/// FIR-75: securities-class assets (stock / ETF / fund / bond / crypto).
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

/// Live stream of all non-archived, non-deleted accounts. UIs watch this
/// for the account list / picker.
///
/// FIR-126: also seeds the income / expense / equity virtual system
/// accounts the first time the user opens any account-aware surface, so
/// the P2-A double-entry posting model has counter-accounts ready before
/// the first cash flow is recorded. The seed is idempotent (deterministic
/// ids) so doing it on every cold start is cheap.
final accountsStreamProvider = StreamProvider.autoDispose<List<Account>>((
  ref,
) async* {
  final repo = await ref.watch(accountRepositoryProvider.future);
  await repo.seedSystemAccounts();
  yield* repo.watchActive();
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

final expenseCategoryRepositoryProvider =
    FutureProvider<ExpenseCategoryRepository>((ref) async {
      final db = await ref.watch(appDatabaseProvider.future);
      final outbox = await ref.watch(outboxStoreProvider.future);
      final stamper = await ref.watch(mutationStamperProvider.future);
      return ExpenseCategoryRepository(
        db: db,
        outbox: outbox,
        stamper: stamper,
      );
    });

final expenseRepositoryProvider = FutureProvider<ExpenseRepository>((
  ref,
) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final outbox = await ref.watch(outboxStoreProvider.future);
  final stamper = await ref.watch(mutationStamperProvider.future);
  return ExpenseRepository(db: db, outbox: outbox, stamper: stamper);
});

/// Live stream of non-archived, non-deleted expense categories — what the
/// expense entry picker subscribes to.
///
/// First read also triggers default-category seeding so a brand-new install
/// has the canonical 12 buckets ready before the picker paints. The seed
/// is idempotent across devices (deterministic ids), so doing this on
/// every cold start is safe.
final expenseCategoriesStreamProvider =
    StreamProvider.autoDispose<List<ExpenseCategory>>((ref) async* {
      final repo = await ref.watch(expenseCategoryRepositoryProvider.future);
      await repo.seedDefaults();
      yield* repo.watchActive();
    });

/// Live stream of every non-tombstoned expense category, archived rows
/// included. Drives the management page; the active picker keeps using
/// [expenseCategoriesStreamProvider] so it doesn't paint archived rows.
final allExpenseCategoriesStreamProvider =
    StreamProvider.autoDispose<List<ExpenseCategory>>((ref) async* {
      final repo = await ref.watch(expenseCategoryRepositoryProvider.future);
      await repo.seedDefaults();
      yield* repo.watchAllExceptDeleted();
    });

/// Live stream of all non-deleted expenses across all accounts. Feature
/// screens that want a per-account view should call
/// `repo.watchExpenses(accountId: ...)` directly.
final expensesStreamProvider = StreamProvider.autoDispose<List<Expense>>((
  ref,
) async* {
  final repo = await ref.watch(expenseRepositoryProvider.future);
  yield* repo.watchExpenses();
});

/// Repository for the local `fx_rates` table. Not synced (FX rates are
/// global market data, not user data) so this repo bypasses the outbox.
final fxRateRepositoryProvider = FutureProvider<FxRateRepository>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return FxRateRepository(db: db);
});

/// Live stream of every recorded FX rate. The dashboard converter and the
/// FX-rate management page both watch this so a manual rate insert
/// reactively flows into every consumer.
final fxRatesStreamProvider = StreamProvider.autoDispose<List<dom.FxRate>>((
  ref,
) async* {
  final repo = await ref.watch(fxRateRepositoryProvider.future);
  yield* repo.watchAll();
});

/// FIR-125 — read access over the local audit ledger (`domain_event_log`).
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
    .family<List<DomainEvent>, ({String entityTable, String entityId})>(
  (ref, key) async* {
    final reader = await ref.watch(eventLogReaderProvider.future);
    yield* reader.watchByEntity(
      entityTable: key.entityTable,
      entityId: key.entityId,
    );
  },
);
