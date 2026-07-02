import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/finance/domain/models/entry_kind.dart';
import 'package:naviwealth/features/finance/shared/entry_kind_badge.dart';
import 'package:naviwealth/features/finance/shared/entry_kind_labels.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:naviwealth/l10n/gen/app_localizations_en.dart';
import 'package:naviwealth/l10n/gen/app_localizations_zh.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en', 'US'),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  test('entryKindLabel covers every EntryKind in English and Chinese', () {
    final en = AppLocalizationsEn();
    final zh = AppLocalizationsZh();

    expect(EntryKind.values.map((kind) => entryKindLabel(en, kind)).toList(), [
      'Trade',
      'Transfer',
      'Income',
      'Expense',
      'Payment',
      'Adjustment',
      'Opening',
      'Other',
    ]);
    expect(EntryKind.values.map((kind) => entryKindLabel(zh, kind)).toList(), [
      '交易',
      '转账',
      '收入',
      '支出',
      '还款',
      '调整',
      '期初',
      '其他',
    ]);
  });

  testWidgets('renders directional icon + label for a buy trade', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const EntryKindIndicator(
          classification: EntryKindClassification(
            kind: EntryKind.trade,
            isInflow: false,
          ),
        ),
      ),
    );
    expect(find.byIcon(FLucideIcons.trendingDown), findsOneWidget);
    expect(find.text('Trade'), findsOneWidget);
  });

  testWidgets('sell trade shows trending_up icon', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const EntryKindIndicator(
          classification: EntryKindClassification(
            kind: EntryKind.trade,
            isInflow: true,
          ),
        ),
      ),
    );
    expect(find.byIcon(FLucideIcons.trendingUp), findsOneWidget);
  });

  testWidgets('compact mode hides the label and tightens padding', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const EntryKindIndicator(
          classification: EntryKindClassification(kind: EntryKind.expense),
          compact: true,
        ),
      ),
    );
    expect(find.byIcon(FLucideIcons.arrowUpRight), findsOneWidget);
    expect(find.text('Expense'), findsNothing);
  });

  testWidgets('label override replaces the default short name', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const EntryKindIndicator(
          classification: EntryKindClassification(
            kind: EntryKind.payment,
            isInflow: false,
          ),
          labelOverride: '还款',
        ),
      ),
    );
    expect(find.text('还款'), findsOneWidget);
    // Default 'Payment' is no longer surfaced.
    expect(find.text('Payment'), findsNothing);
    expect(find.byIcon(FLucideIcons.banknote), findsOneWidget);
  });

  testWidgets('every kind has a deterministic icon mapping', (tester) async {
    // Smoke-test the full enum so a future addition that forgets to
    // extend the visuals switch trips here rather than in production.
    const kinds = [
      EntryKind.trade,
      EntryKind.transfer,
      EntryKind.income,
      EntryKind.expense,
      EntryKind.payment,
      EntryKind.adjustment,
      EntryKind.opening,
      EntryKind.other,
    ];
    for (final k in kinds) {
      await tester.pumpWidget(
        _wrap(
          EntryKindIndicator(classification: EntryKindClassification(kind: k)),
        ),
      );
      // At least one icon is rendered (anything beyond zero would
      // have failed the build_runner type check).
      expect(find.byType(Icon), findsOneWidget, reason: 'kind=$k');
    }
  });

  testWidgets('other kind uses the explicit localized label', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const EntryKindIndicator(
          classification: EntryKindClassification(kind: EntryKind.other),
        ),
      ),
    );
    expect(find.text('Other'), findsOneWidget);
    expect(find.text('Entry'), findsNothing);
    expect(find.text('other'), findsNothing);
  });
}
