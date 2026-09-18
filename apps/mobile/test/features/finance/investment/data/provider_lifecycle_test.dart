import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/current_user.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/features/finance/investment/data/providers.dart';
import 'package:naviwealth/features/finance/investment/domain/holding_service.dart';
import 'package:naviwealth/features/finance/investment/domain/models/holding_snapshot.dart';
import 'package:naviwealth/features/finance/options_income/data/providers.dart';
import 'package:naviwealth/features/finance/options_income/data/trade_journal_repository.dart';
import 'package:naviwealth/features/finance/options_income/domain/trade_journal_entry.dart';

import '../../../../core/persistence/test_database.dart';

void main() {
  test('ledger revision may be disposed while database initialization is pending', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final ready = Completer<AppDatabase>();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWith((_) => ready.future),
        holdingServiceProvider.overrideWith((_) async => _Holdings()),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(holdingsSnapshotProvider, (_, _) {});
    await container.pump();
    subscription.close();
    await container.pump();
    ready.complete(db);
    await container.pump();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    // Uncaught disposed-Ref errors fail this test, including late async* work.
    expect(container.exists(holdingsSnapshotProvider), isFalse);
  });

  for (final duringOwner in [false, true]) {
    test(
      'trade journal closes during ${duringOwner ? 'owner' : 'repository'} resolution',
      () async {
        final repo = _Journal();
        final ready = Completer<TradeJournalRepository>();
        final owner = Completer<String>();
        final container = ProviderContainer(
          overrides: [
            tradeJournalRepositoryProvider.overrideWith((_) => ready.future),
            currentUserIdProvider.overrideWithValue(() => owner.future),
          ],
        );
        addTearDown(container.dispose);
        final subscription = container.listen(
          tradeJournalEntriesProvider,
          (_, _) {},
        );
        if (duringOwner) ready.complete(repo);
        await container.pump();
        subscription.close();
        await container.pump();
        if (!duringOwner) ready.complete(repo);
        owner.complete('alice');
        await container.pump();
        expect(repo.watches, 0);
      },
    );
  }
}

class _Holdings implements HoldingService {
  @override
  Future<Map<String, HoldingSnapshot>> computeAt(DateTime asOf) async => {};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Journal implements TradeJournalRepository {
  int watches = 0;
  @override
  Stream<List<TradeJournalEntry>> watchActive(String ownerUserId) {
    watches++;
    return Stream.value([]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
