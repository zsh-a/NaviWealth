import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/core/sync/drift_sync_storage.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_event.dart';
import 'package:naviwealth/features/finance/cashflow/domain/cash_flow_kind.dart';
import 'package:naviwealth/features/finance/cashflow/domain/dividend_center.dart';
import 'package:naviwealth/features/finance/cashflow/ui/dividend_event_actions.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_providers.dart';
import 'package:naviwealth/features/finance/data/repositories/journal_entry_repository.dart';
import 'package:naviwealth/features/finance/domain/models/enums.dart';
import 'package:naviwealth/features/finance/domain/models/invariants.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../../../../core/persistence/test_database.dart';
import '../../data/repositories/_stub_stamper.dart';

class _IdentityFx implements FxRateSource {
  const _IdentityFx();

  @override
  Decimal? rate({
    required String from,
    required String to,
    required DateTime asOf,
  }) => Decimal.one;
}

class _ActionHost extends ConsumerWidget {
  const _ActionHost({required this.event});

  final DividendCenterEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delete = buildDividendEventActions(context, ref, event).last;
    return FScaffold(
      child: Center(
        child: FButton(
          onPress: delete.onPress,
          child: const Text('delete-dividend'),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('deletes a dividend journal entry and restores it from Undo', (
    tester,
  ) async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final repository = JournalEntryRepository(
      db: db,
      outbox: InMemoryOutboxStore(),
      stamper: makeStubStamper(),
      fxRateSource: const _IdentityFx(),
      baseCurrency: 'CNY',
    );
    await repository.create(
      entry: JournalEntryDraft(
        id: 'je-dividend',
        date: DateTime.utc(2026, 6, 1),
        narration: 'ACME dividend',
      ),
      postings: [
        PostingDraft(
          id: 'p-cash',
          accountId: 'assets:cash',
          units: Decimal.parse('100'),
          unit: 'CNY',
        ),
        PostingDraft(
          id: 'p-income',
          accountId: 'income:dividend',
          units: Decimal.parse('-100'),
          unit: 'CNY',
        ),
      ],
    );
    final event = DividendCenterEvent(
      event: CashFlowEvent(
        journalEntryId: 'je-dividend',
        date: DateTime.utc(2026, 6, 1),
        kind: CashFlowKind.dividend,
        signedAmount: Decimal.parse('100'),
        originalAmount: Decimal.parse('100'),
        currency: 'CNY',
        accountId: 'assets:cash',
        counterAccountSide: AccountSide.income,
      ),
      assetId: 'asset-acme',
      assetLabel: 'ACME',
      withholdingInBase: Decimal.zero,
      withholdingOriginal: Decimal.zero,
      withholdingCurrency: 'CNY',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          journalEntryRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => AppMessenger.init(child: child!),
          home: FTheme(
            data: FTheme.neutral.light.desktop,
            child: _ActionHost(event: event),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('delete-dividend'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Delete the dividend for ACME? '
        'You can undo it from the confirmation message.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Dividend deleted'), findsOneWidget);
    expect(await repository.getById('je-dividend'), isNull);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('Change undone'), findsOneWidget);
    expect((await repository.getById('je-dividend'))?.postings, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
