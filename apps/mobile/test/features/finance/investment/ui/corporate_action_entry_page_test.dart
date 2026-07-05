import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/features/finance/investment/domain/corporate_action_preview.dart';
import 'package:naviwealth/features/finance/investment/domain/cost_basis/fifo_strategy.dart';
import 'package:naviwealth/features/finance/investment/domain/cost_basis_engine.dart';
import 'package:naviwealth/features/finance/investment/domain/models/corporate_actions.dart';
import 'package:naviwealth/features/finance/investment/domain/models/lot.dart';
import 'package:naviwealth/features/finance/investment/ui/corporate_action_entry_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

const _testAsset = CorporateActionAsset(
  id: 'AAPL',
  displayName: 'Apple',
  accountId: 'acct-1',
  currency: 'USD',
);

List<Lot> _testLots(String assetId) {
  if (assetId != 'AAPL') return const [];
  return [
    Lot(
      id: 'l-1',
      openingTransactionId: 'tx-1',
      accountId: 'acct-1',
      assetId: 'AAPL',
      currency: 'USD',
      originalQuantity: Decimal.fromInt(100),
      remainingQuantity: Decimal.fromInt(100),
      costPerUnit: Decimal.fromInt(150),
      openedAt: DateTime.utc(2025, 1, 1),
    ),
  ];
}

Future<void> _pump(
  WidgetTester tester, {
  required void Function(CorporateActionPreview) onSubmit,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: CorporateActionEntryPage(
        assets: const [_testAsset],
        lotsForAsset: (asset) => _testLots(asset.id),
        onSubmit: onSubmit,
        engine: CostBasisEngine(
          strategy: const FifoStrategy(),
          idGenerator: () => 'fixed-id',
        ),
        idGenerator: () => 'fixed-tx',
        now: DateTime.utc(2026, 6, 1),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectType(WidgetTester tester, String typeName) async {
  await tester.ensureVisible(find.byKey(Key('corp-action-type-$typeName')));
  await tester.tap(find.byKey(Key('corp-action-type-$typeName')));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String fieldKey, String value) async {
  await tester.ensureVisible(find.byKey(Key('corp-action-$fieldKey')));
  await tester.enterText(find.byKey(Key('corp-action-$fieldKey')), value);
  await tester.pumpAndSettle();
}

Future<void> _tapPreview(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('corp-action-preview')));
  await tester.tap(find.byKey(const Key('corp-action-preview')));
  await tester.pumpAndSettle();
}

Future<void> _tapSubmit(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('corp-action-submit')));
  await tester.tap(find.byKey(const Key('corp-action-submit')));
  await tester.pumpAndSettle();
}

void main() {
  group('CorporateActionEntryPage', () {
    testWidgets('cash dividend → preview shows gross/net, submit emits '
        'CashDividendAction with parsed params', (tester) async {
      CorporateActionPreview? captured;
      await _pump(tester, onSubmit: (p) => captured = p);

      // Default selection is cashDividend; verify chip selected.
      expect(
        find.byKey(const Key('corp-action-type-cashDividend')),
        findsOneWidget,
      );

      await _enter(tester, 'amount-per-share', '0.50');
      await _enter(tester, 'withholding-tax', '5');
      await _tapPreview(tester);

      // Preview card visible; gross = 100 * 0.5 = 50, net = 45.
      // Net = 45 also appears as the "Cash flow" row → 2 occurrences.
      expect(find.byKey(const Key('corp-action-preview-card')), findsOneWidget);
      expect(find.text(r'$50.00'), findsOneWidget);
      expect(find.text(r'$45.00'), findsNWidgets(2));

      await _tapSubmit(tester);

      expect(captured, isNotNull);
      final action = captured!.action;
      expect(action, isA<CashDividendAction>());
      final cd = action as CashDividendAction;
      expect(cd.assetId, 'AAPL');
      expect(cd.accountId, 'acct-1');
      expect(cd.currency, 'USD');
      expect(cd.amountPerShare, Decimal.parse('0.50'));
      expect(cd.withholdingTax, Decimal.parse('5'));
      expect(cd.effectiveDate, DateTime.utc(2026, 6, 1));

      // Expire the 6-second dismiss timer from AppMessenger.show().
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('stock dividend → preview shows quantity-up / cost-down '
        'delta', (tester) async {
      await _pump(tester, onSubmit: (_) {});
      await _selectType(tester, 'stockDividend');

      await _enter(tester, 'bonus-ratio', '0.10');
      await _tapPreview(tester);

      // After 10 % bonus on 100 shares: 100 → 110, cost 150 → 13636…(infinite).
      // The localized template renders as "Lot l-1: 100 → 110 @ 150 → 136…".
      expect(find.textContaining('100 → 110'), findsOneWidget);

      // Expire the 6-second dismiss timer from AppMessenger.show().
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('split → preview shows doubled quantity, halved cost', (
      tester,
    ) async {
      CorporateActionPreview? captured;
      await _pump(tester, onSubmit: (p) => captured = p);
      await _selectType(tester, 'split');

      await _enter(tester, 'split-ratio', '2');
      await _tapPreview(tester);

      expect(find.textContaining('100 → 200'), findsOneWidget);
      expect(find.textContaining('150 → 75'), findsOneWidget);

      await _tapSubmit(tester);
      expect(captured!.action, isA<SplitAction>());
      expect((captured!.action as SplitAction).ratio, Decimal.parse('2'));

      // Expire the 6-second dismiss timer from AppMessenger.show().
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('rights issue → preview includes new lot and negative '
        'cash flow', (tester) async {
      CorporateActionPreview? captured;
      await _pump(tester, onSubmit: (p) => captured = p);
      await _selectType(tester, 'rightsIssue');

      await _enter(tester, 'subscribed-qty', '50');
      await _enter(tester, 'price-per-unit', '15');
      await _enter(tester, 'fee', '5');
      await _tapPreview(tester);

      // -(50 * 15 + 5) = -755
      expect(find.text(r'-$755.00'), findsOneWidget);
      expect(find.textContaining('50'), findsWidgets);

      await _tapSubmit(tester);
      final ri = captured!.action as RightsIssueAction;
      expect(ri.subscribedQuantity, Decimal.parse('50'));
      expect(ri.pricePerUnit, Decimal.parse('15'));
      expect(ri.fee, Decimal.parse('5'));

      // Expire the 6-second dismiss timer from AppMessenger.show().
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('DRIP → preview includes the reinvested lot', (tester) async {
      CorporateActionPreview? captured;
      await _pump(tester, onSubmit: (p) => captured = p);
      await _selectType(tester, 'drip');

      await _enter(tester, 'amount-per-share', '1');
      await _enter(tester, 'price-per-unit', '500');
      await _tapPreview(tester);

      // 100 * 1 = 100 dividend; 100 / 500 = 0.2 new shares.
      expect(find.textContaining('0.2'), findsWidgets);

      await _tapSubmit(tester);
      final d = captured!.action as DripAction;
      expect(d.amountPerShare, Decimal.parse('1'));
      expect(d.pricePerUnit, Decimal.parse('500'));
      expect(captured!.cashDividend!.reinvested, isTrue);

      // Expire the 6-second dismiss timer from AppMessenger.show().
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('preview without filling required fields stays blank and '
        'submit stays disabled', (tester) async {
      var submitted = 0;
      await _pump(tester, onSubmit: (_) => submitted++);

      // Don't fill anything; tap preview.
      await _tapPreview(tester);
      // Form validates → no preview card.
      expect(find.byKey(const Key('corp-action-preview-card')), findsNothing);

      // Submit button disabled while preview is null.
      final submit = tester.widget<FButton>(
        find.byKey(const Key('corp-action-submit')),
      );
      expect(submit.onPress, isNull);
      expect(submitted, 0);
    });

    testWidgets('switching event type clears the previous preview', (
      tester,
    ) async {
      await _pump(tester, onSubmit: (_) {});

      await _enter(tester, 'amount-per-share', '0.50');
      await _enter(tester, 'withholding-tax', '0');
      await _tapPreview(tester);
      expect(find.byKey(const Key('corp-action-preview-card')), findsOneWidget);

      await _selectType(tester, 'split');
      expect(find.byKey(const Key('corp-action-preview-card')), findsNothing);
    });
  });
}
