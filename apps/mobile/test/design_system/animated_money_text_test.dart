import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(
  Widget child, {
  bool disableAnimations = false,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
    locale: const Locale('en', 'US'),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

String _renderedText(WidgetTester tester) {
  // The AnimatedMoneyText renders a MoneyText, which renders a single Text.
  return tester.widget<Text>(find.byType(Text)).data ?? '';
}

void main() {
  testWidgets('renders the initial amount immediately', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AnimatedMoneyText(
          amount: 1000,
          currencyCode: 'USD',
          symbol: '\$',
        ),
      ),
    );
    expect(_renderedText(tester), contains('1,000'));
  });

  testWidgets('animates between two values over the configured duration',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AnimatedMoneyText(
          amount: 1000,
          currencyCode: 'USD',
          symbol: '\$',
        ),
      ),
    );
    await tester.pumpWidget(
      _wrap(
        const AnimatedMoneyText(
          amount: 2000,
          currencyCode: 'USD',
          symbol: '\$',
        ),
      ),
    );

    // Mid-flight: a tween should have produced an intermediate value.
    await tester.pump(const Duration(milliseconds: 200));
    final mid = _renderedText(tester);
    expect(mid, isNot(contains('1,000.00')));
    expect(mid, isNot(contains('2,000.00')));

    // Settled: lands on the final amount.
    await tester.pumpAndSettle();
    expect(_renderedText(tester), contains('2,000'));
  });

  testWidgets('skips animation when MediaQuery.disableAnimations is true',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AnimatedMoneyText(
          amount: 1000,
          currencyCode: 'USD',
          symbol: '\$',
        ),
        disableAnimations: true,
      ),
    );
    await tester.pumpWidget(
      _wrap(
        const AnimatedMoneyText(
          amount: 2000,
          currencyCode: 'USD',
          symbol: '\$',
        ),
        disableAnimations: true,
      ),
    );
    // No frame advance: when motion is disabled the widget renders the
    // terminal value on the very next build.
    expect(_renderedText(tester), contains('2,000'));
  });

  testWidgets('switching sign animates and the final string starts with -',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AnimatedMoneyText(
          amount: 100,
          currencyCode: 'USD',
          symbol: '\$',
        ),
      ),
    );
    await tester.pumpWidget(
      _wrap(
        const AnimatedMoneyText(
          amount: -100,
          currencyCode: 'USD',
          symbol: '\$',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_renderedText(tester), startsWith('-'));
  });

  testWidgets('switching currency code rebuilds the tween cleanly',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AnimatedMoneyText(
          amount: 1000,
          currencyCode: 'USD',
          symbol: '\$',
        ),
      ),
    );
    await tester.pumpWidget(
      _wrap(
        const AnimatedMoneyText(
          amount: 1000,
          currencyCode: 'CNY',
          symbol: '¥',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final settled = _renderedText(tester);
    expect(settled, contains('¥'));
    expect(settled, contains('1,000'));
  });

  testWidgets('null amount falls back to the MoneyText placeholder',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AnimatedMoneyText(amount: null, currencyCode: 'CNY'),
      ),
    );
    expect(find.textContaining('—'), findsOneWidget);
  });

  testWidgets(
    'small same-sign change uses the short cadence (settles before 800ms)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AnimatedMoneyText(
            amount: 10000,
            currencyCode: 'USD',
            symbol: '\$',
          ),
        ),
      );
      await tester.pumpWidget(
        _wrap(
          const AnimatedMoneyText(
            amount: 10100, // +1% — under the 5% threshold
            currencyCode: 'USD',
            symbol: '\$',
          ),
        ),
      );
      // Past the short duration but well before the marquee one — the
      // tween should already be at its terminal value.
      await tester.pump(const Duration(milliseconds: 400));
      expect(_renderedText(tester), contains('10,100'));
    },
  );

  testWidgets('respects showSign on settled positive values', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AnimatedMoneyText(
          amount: 250,
          currencyCode: 'USD',
          symbol: '\$',
          showSign: true,
        ),
      ),
    );
    expect(_renderedText(tester), startsWith('+'));
  });
}
