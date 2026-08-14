import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) {
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
  return tester.widget<Text>(find.byType(Text)).data ?? '';
}

void main() {
  testWidgets('renders the initial value immediately', (tester) async {
    await tester.pumpWidget(
      _wrap(AnimatedValueText(value: 74, format: (v) => '${v.round()}')),
    );
    expect(_renderedText(tester), '74');
  });

  testWidgets('animates between two values, then settles on the target', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(AnimatedValueText(value: 0, format: (v) => '${v.round()}')),
    );
    await tester.pumpWidget(
      _wrap(AnimatedValueText(value: 100, format: (v) => '${v.round()}')),
    );

    // Mid-flight: the tween shows an intermediate value.
    await tester.pump(const Duration(milliseconds: 200));
    final mid = int.parse(_renderedText(tester));
    expect(mid, greaterThan(0));
    expect(mid, lessThan(100));

    await tester.pumpAndSettle();
    expect(_renderedText(tester), '100');
  });

  testWidgets('does not replay when rebuilt with an unchanged value', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(AnimatedValueText(value: 0, format: (v) => '${v.round()}')),
    );
    await tester.pumpWidget(
      _wrap(AnimatedValueText(value: 100, format: (v) => '${v.round()}')),
    );
    await tester.pumpAndSettle();

    // A rebuild with the same value after the roll completes renders the
    // terminal text statically instead of restarting the tween.
    await tester.pumpWidget(
      _wrap(AnimatedValueText(value: 100, format: (v) => '${v.round()}')),
    );
    expect(_renderedText(tester), '100');
    await tester.pump(const Duration(milliseconds: 200));
    expect(_renderedText(tester), '100');
  });

  testWidgets('keeps the formatter suffix attached while rolling', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(AnimatedValueText(value: 10, format: (v) => '${v.round()}%')),
    );
    await tester.pumpWidget(
      _wrap(AnimatedValueText(value: 90, format: (v) => '${v.round()}%')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(_renderedText(tester), endsWith('%'));
    await tester.pumpAndSettle();
    expect(_renderedText(tester), '90%');
  });

  testWidgets('skips animation when MediaQuery.disableAnimations is true', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AnimatedValueText(value: 0, format: (v) => '${v.round()}'),
        disableAnimations: true,
      ),
    );
    await tester.pumpWidget(
      _wrap(
        AnimatedValueText(value: 100, format: (v) => '${v.round()}'),
        disableAnimations: true,
      ),
    );
    // No frame advance: reduced motion renders the terminal value at once.
    expect(_renderedText(tester), '100');
  });

  testWidgets('null value renders the placeholder', (tester) async {
    await tester.pumpWidget(
      _wrap(AnimatedValueText(value: null, format: (v) => '${v.round()}')),
    );
    expect(find.text('—'), findsOneWidget);
  });
}
