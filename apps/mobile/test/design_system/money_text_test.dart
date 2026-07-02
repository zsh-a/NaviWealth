import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
  locale: const Locale('en', 'US'),
  home: Scaffold(body: Center(child: child)),
);

DisplayMoney _money(String amount, String currency) =>
    DisplayMoney(amount: Decimal.parse(amount), currency: currency);

void main() {
  setUpAll(AppFormatters.ensureInitialized);

  testWidgets('MoneyText renders symbol + grouped value', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const MoneyText(amount: 12345.6, currencyCode: 'USD', symbol: '\$'),
      ),
    );
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, contains('12,345.60'));
    expect(text.data, contains('\$'));
  });

  testWidgets('MoneyText shows placeholder when amount is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const MoneyText(amount: null, currencyCode: 'CNY')),
    );
    expect(find.textContaining('—'), findsOneWidget);
    expect(find.textContaining('¥'), findsOneWidget);
  });

  testWidgets('MoneyText showSign prefixes positive values', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const MoneyText(
          amount: 1000,
          currencyCode: 'USD',
          symbol: '\$',
          showSign: true,
        ),
      ),
    );
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, startsWith('+'));
  });

  testWidgets('MoneyText prefixes negative with -', (tester) async {
    await tester.pumpWidget(
      _wrap(const MoneyText(amount: -250, currencyCode: 'USD', symbol: '\$')),
    );
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, startsWith('-'));
  });

  testWidgets(
    'MoneyText emits a screen-reader label that pairs amount + currency',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MoneyText(amount: 12345.6, currencyCode: 'USD', symbol: '\$'),
        ),
      );
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.semanticsLabel, contains('USD'));
      expect(text.semanticsLabel, contains('12,345.60'));
    },
  );

  testWidgets('MoneyText renders a privacy placeholder when hidden', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AmountPrivacyScope(
          hidden: true,
          child: MoneyText(amount: 12345.6, currencyCode: 'USD', symbol: '\$'),
        ),
      ),
    );

    expect(find.byType(AmountPrivacyPlaceholder), findsOneWidget);
    expect(find.text(AmountPrivacyScope.mask), findsNothing);
    expect(find.textContaining('12,345'), findsNothing);
  });

  testWidgets('SignedMoneyText uses shared signed formatter', (tester) async {
    final formatters = AppFormatters(locale: const Locale('en', 'US'));
    await tester.pumpWidget(
      _wrap(
        SignedMoneyText(
          amount: Decimal.parse('1234.5000'),
          unit: 'USD',
          formatters: formatters,
        ),
      ),
    );

    expect(find.text(r'+$1,234.5'), findsOneWidget);
  });

  testWidgets('SignedMoneyText renders a neutral privacy placeholder', (
    tester,
  ) async {
    final formatters = AppFormatters(locale: const Locale('en', 'US'));
    await tester.pumpWidget(
      _wrap(
        AmountPrivacyScope(
          hidden: true,
          child: SignedMoneyText(
            amount: Decimal.parse('1234.5000'),
            unit: 'USD',
            formatters: formatters,
          ),
        ),
      ),
    );

    expect(find.byType(AmountPrivacyPlaceholder), findsOneWidget);
    expect(find.text(AmountPrivacyScope.mask), findsNothing);
    expect(find.text(r'+$1,234.5'), findsNothing);
  });

  testWidgets('SignedMoneyText formats securities and can hide plus', (
    tester,
  ) async {
    final formatters = AppFormatters(locale: const Locale('en', 'US'));
    await tester.pumpWidget(
      _wrap(
        SignedMoneyText(
          amount: Decimal.parse('10.0000'),
          unit: 'us_stock:AAPL',
          formatters: formatters,
          showPositiveSign: false,
        ),
      ),
    );

    expect(find.text('10 AAPL'), findsOneWidget);
  });

  // §3.1 multi-currency dual-display — [DualMoneyText] surfaces both the
  // base-currency value (primary) and the native-currency value (caption)
  // for journal entries that involve FX conversion.
  testWidgets('DualMoneyText shows primary + caption when currencies differ', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        DualMoneyText(
          primaryAmount: _money('1000.00', 'USD'),
          originalAmount: _money('7240.00', 'CNY'),
        ),
      ),
    );
    expect(find.textContaining('1,000'), findsOneWidget);
    expect(find.textContaining('7,240'), findsOneWidget);
    // ISO-code style on the caption surfaces the original currency.
    expect(find.textContaining('CNY'), findsOneWidget);
  });

  testWidgets(
    'DualMoneyText hides caption when original currency matches primary',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          DualMoneyText(
            primaryAmount: _money('1000.00', 'USD'),
            originalAmount: _money('1000.00', 'USD'),
          ),
        ),
      );
      // Only one Text → the secondary caption is suppressed when there is
      // no FX delta to communicate.
      expect(find.byType(Text), findsOneWidget);
      expect(find.textContaining('CNY'), findsNothing);
    },
  );

  testWidgets('DualMoneyText hides caption when original is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(DualMoneyText(primaryAmount: _money('1000.00', 'USD'))),
    );
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets(
    'DualMoneyText stacked layout renders primary on top, caption below',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          DualMoneyText(
            primaryAmount: _money('1000.00', 'USD'),
            originalAmount: _money('7240.00', 'CNY'),
            layout: DualMoneyLayout.stacked,
          ),
        ),
      );
      expect(find.byType(Column), findsWidgets);
      // No inline separator glyph in stacked mode.
      expect(find.text(' · '), findsNothing);
    },
  );

  testWidgets(
    'DualMoneyText accessibility label folds in the original currency',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          DualMoneyText(
            primaryAmount: _money('1000.00', 'USD'),
            originalAmount: _money('7240.00', 'CNY'),
          ),
        ),
      );
      // The primary Text carries the consolidated semantics label; the
      // caption Text label is suppressed to keep VoiceOver focused.
      final primary = tester.widget<Text>(find.textContaining('1,000'));
      expect(primary.semanticsLabel, contains('USD'));
      expect(primary.semanticsLabel, contains('CNY'));
      // Both amounts must be readable in the same label so the screen
      // reader speaks the dual-currency context in one breath.
      expect(primary.semanticsLabel, contains('1000'));
      expect(primary.semanticsLabel, contains('7240'));
    },
  );
}
