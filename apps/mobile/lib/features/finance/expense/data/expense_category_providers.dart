import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/core/sync/outbox_provider.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';

import '../domain/expense_category.dart';
import 'expense_category_repository.dart';

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

final expenseCategoriesSeedProvider = FutureProvider<void>((ref) async {
  await ref.watch(systemAccountsSeedProvider.future);
  final ownerUserId = await ref.watch(currentUserIdProvider)();
  final repository = await ref.watch(expenseCategoryRepositoryProvider.future);
  await repository.seedDefaults(ownerUserId);
});

final expenseCategoriesProvider =
    StreamProvider.autoDispose<List<ExpenseCategory>>((ref) async* {
      await ref.watch(expenseCategoriesSeedProvider.future);
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      final repository = await ref.watch(
        expenseCategoryRepositoryProvider.future,
      );
      yield* repository.watchActive(ownerUserId);
    });

final allExpenseCategoriesProvider =
    StreamProvider.autoDispose<List<ExpenseCategory>>((ref) async* {
      await ref.watch(expenseCategoriesSeedProvider.future);
      final ownerUserId = await ref.watch(currentUserIdProvider)();
      final repository = await ref.watch(
        expenseCategoryRepositoryProvider.future,
      );
      yield* repository.watchAll(ownerUserId);
    });
