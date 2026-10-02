import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/accounts/data/account_balances_provider.dart';
import 'package:naviwealth/features/finance/accounts/domain/account_balances.dart';
import 'package:naviwealth/features/finance/accounts/ui/account_detail_page.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/account.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets(
    'loading and failed balances/activity never appear as empty; sections retry independently',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final balances = Completer<Map<String, AccountBalances>>();
      final journal = Completer<List<JournalEntryWithPostings>>();
      var balanceLoads = 0;
      var journalLoads = 0;
      final account = Account(
        id: 'a',
        type: AccountCategory.bank,
        name: 'Checking',
        currency: 'CNY',
        sync: SyncMeta(
          ownerUserId: 'owner',
          updatedAt: DateTime.utc(2026),
          updatedByDevice: 'device',
          hlc: Hlc.zero('device'),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountsStreamProvider.overrideWith((_) => Stream.value([account])),
            accountBalancesByIdProvider.overrideWith((_) {
              balanceLoads++;
              return balanceLoads == 1
                  ? Stream.fromFuture(balances.future)
                  : Stream.value({});
            }),
            journalEntriesWithPostingsStreamProvider.overrideWith((_) {
              journalLoads++;
              return journalLoads == 1
                  ? Stream.fromFuture(journal.future)
                  : Stream.value([]);
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: FTheme(
              data: FTheme.neutral.light.desktop,
              child: const AccountDetailPage(accountId: 'a'),
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text('—'), findsNothing);
      expect(find.text(l10n.accountDetailNoActivity), findsNothing);
      expect(find.text(l10n.accountDetailAddBalanceAction), findsOneWidget);
      balances.completeError(StateError('temporary balance failure'));
      journal.completeError(StateError('temporary activity failure'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.accountDetailNoActivity), findsNothing);
      expect(find.text(l10n.commonRetry), findsNWidgets(2));
      await tester.tap(find.text(l10n.commonRetry).first);
      await tester.pumpAndSettle();
      expect(balanceLoads, 2);
      expect(journalLoads, 1);
      expect(find.text('—'), findsOneWidget);
      await tester.tap(find.text(l10n.commonRetry));
      await tester.pumpAndSettle();
      expect(find.text(l10n.accountDetailNoActivity), findsOneWidget);
      expect(journalLoads, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
