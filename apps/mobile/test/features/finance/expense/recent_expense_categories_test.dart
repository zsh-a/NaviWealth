import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/domain/models/expense.dart';
import 'package:naviwealth/features/finance/expense/data/recent_expense_categories.dart';

Expense _expense({
  required String id,
  required String expenseAccountId,
  required DateTime tradeDate,
}) {
  return Expense(
    id: id,
    expenseAccountId: expenseAccountId,
    amount: Decimal.fromInt(10),
    currency: 'CNY',
    tradeDate: tradeDate,
    sync: SyncMeta(
      ownerUserId: 'u',
      updatedAt: tradeDate,
      updatedByDevice: 'dev',
      hlc: const Hlc(wallMillis: 0, counter: 0, nodeId: 'dev'),
    ),
  );
}

void main() {
  test('returns null when there are no recent expenses', () {
    final container = ProviderContainer(
      overrides: [
        journalExpensesStreamProvider.overrideWith(
          (_) => Stream.value(const []),
        ),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(mostUsedExpenseCategoryProvider), isNull);
  });

  test('returns the most-frequent category in the recent window', () async {
    final now = DateTime.now();
    final container = ProviderContainer(
      overrides: [
        journalExpensesStreamProvider.overrideWith(
          (_) => Stream.value([
            _expense(
              id: '1',
              expenseAccountId: 'food',
              tradeDate: now.subtract(const Duration(days: 1)),
            ),
            _expense(
              id: '2',
              expenseAccountId: 'food',
              tradeDate: now.subtract(const Duration(days: 2)),
            ),
            _expense(
              id: '3',
              expenseAccountId: 'transport',
              tradeDate: now.subtract(const Duration(days: 3)),
            ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    // Hold a subscription so the autoDispose stream stays alive through
    // the read below; otherwise the provider tears down between calls
    // and the future never completes with a value.
    final sub = container.listen(mostUsedExpenseCategoryProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(journalExpensesStreamProvider.future);
    expect(container.read(mostUsedExpenseCategoryProvider), 'food');
  });

  test('ignores spends older than the window', () async {
    final now = DateTime.now();
    final container = ProviderContainer(
      overrides: [
        journalExpensesStreamProvider.overrideWith(
          (_) => Stream.value([
            // Six "transport" rows from a few months ago — would dominate
            // a naïve all-time pick but should be ignored entirely.
            for (var i = 0; i < 6; i++)
              _expense(
                id: 'old-$i',
                expenseAccountId: 'transport',
                tradeDate: now.subtract(Duration(days: 90 + i)),
              ),
            _expense(
              id: 'new-1',
              expenseAccountId: 'food',
              tradeDate: now.subtract(const Duration(days: 2)),
            ),
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(mostUsedExpenseCategoryProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(journalExpensesStreamProvider.future);
    expect(container.read(mostUsedExpenseCategoryProvider), 'food');
  });

  test('returns null while the stream is still loading', () {
    final container = ProviderContainer(
      overrides: [
        // Returning a never-completing stream keeps the AsyncValue in
        // loading state — exactly the case the provider has to handle
        // without crashing.
        journalExpensesStreamProvider.overrideWith(
          (_) => Stream<List<dynamic>>.fromFuture(
            Future.delayed(const Duration(seconds: 30), () => const []),
          ).cast(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(mostUsedExpenseCategoryProvider, (_, _) {});
    addTearDown(sub.close);
    expect(container.read(mostUsedExpenseCategoryProvider), isNull);
  });
}
