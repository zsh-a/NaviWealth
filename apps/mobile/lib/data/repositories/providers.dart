import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/drift_sync_storage.dart';
import '../../core/sync/op_outbox.dart';
import '../db/providers.dart';
import '../domain/account.dart';
import '../domain/asset.dart';
import '../domain/expense.dart';
import '../domain/expense_category.dart';
import 'account_repository.dart';
import 'expense_category_repository.dart';
import 'expense_repository.dart';
import 'manual_asset_repository.dart';
import 'mutation_context.dart';

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

/// Live stream of all non-archived, non-deleted accounts. UIs watch this
/// for the account list / picker.
final accountsStreamProvider = StreamProvider.autoDispose<List<Account>>((
  ref,
) async* {
  final repo = await ref.watch(accountRepositoryProvider.future);
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
final expenseCategoriesStreamProvider =
    StreamProvider.autoDispose<List<ExpenseCategory>>((ref) async* {
      final repo = await ref.watch(expenseCategoryRepositoryProvider.future);
      yield* repo.watchActive();
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
