import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/format/formatters.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
  locale: const Locale('en', 'US'),
  home: Scaffold(body: Center(child: child)),
);

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
}
