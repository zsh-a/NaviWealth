// Flow / Task test: "Transfer cash" — Task #3 companion.
//
// This boots the real app shell, starts from Activity's quick-add menu,
// records a same-currency transfer through the real journal repository, and
// verifies the two ledger legs were persisted.

import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/finance/data/repositories/account_repository.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';

import 'support/app_harness.dart';
import 'support/page_objects.dart';

void main() {
  group('Task: Transfer cash', () {
    late FlowDataHarness data;

    setUp(() async {
      data = await FlowDataHarness.create();
    });

    tearDown(() async {
      await data.dispose();
    });

    testWidgets('user transfers between accounts from Activity', (
      tester,
    ) async {
      final accountRepo = AccountRepository(
        db: data.db,
        outbox: data.outbox,
        stamper: data.stamper,
      );
      final checking = await accountRepo.create(
        type: AccountCategory.bank,
        name: 'Flow Checking',
        currency: 'CNY',
      );
      final savings = await accountRepo.create(
        type: AccountCategory.bank,
        name: 'Flow Savings',
        currency: 'CNY',
      );

      await bootApp(tester, liveData: data);

      final shell = AppShell(tester)..expectMounted();
      await shell.openTab('Records');

      final activity = ActivityPageObject(tester);
      await activity.openTransferEntry();

      final form = TransferFormObject(tester);
      form.expectCreateMode();
      await form.selectFromAccount('Flow Checking');
      await form.selectToAccount('Flow Savings');
      await form.enterAmount('1200');
      await form.enterNote('Flow rent reserve');
      await form.save();

      final entries = await data.db.select(data.db.journalEntries).get();
      expect(entries, hasLength(1));
      expect(entries.single.narration, 'Flow rent reserve');

      final postings = await data.db.select(data.db.postings).get();
      expect(postings, hasLength(2));
      expect(postings.map((posting) => posting.accountId).toSet(), {
        checking.id,
        savings.id,
      });
      expect(postings.map((posting) => posting.units.toString()).toSet(), {
        '-1200',
        '1200',
      });

      await closeApp(tester);
    }, tags: 'flow');
  });
}
