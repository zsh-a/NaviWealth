import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

Widget _wrap(Widget child, {MarketColorMode? mode}) {
  return MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
    locale: const Locale('en', 'US'),
    home: AppThemeScope(
      data: resolveAppTheme(
        ThemeInputs(
          brightness: Brightness.light,
          marketMode: mode ?? MarketColorMode.redUpGreenDown,
        ),
      ),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  testWidgets(
    'DeltaText: positive value uses MarketColors.up (red in CN mode)',
    (tester) async {
      await tester.pumpWidget(
        _wrap(const DeltaText(value: 1.5, format: DeltaFormat.percent)),
      );

      // Find the icon — should be chevron-up tinted with the up color.
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, FLucideIcons.chevronUp);

      final ctx = tester.element(find.byType(DeltaText));
      final market = ctx.appTheme.market;
      expect(icon.color, market.up.fg);
    },
  );

  testWidgets('DeltaText: switching market mode flips up/down colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const DeltaText(value: 1.5, format: DeltaFormat.percent),
        mode: MarketColorMode.redUpGreenDown,
      ),
    );
    var iconCn = tester.widget<Icon>(find.byType(Icon));
    final colorCn = iconCn.color;

    await tester.pumpWidget(
      _wrap(
        const DeltaText(value: 1.5, format: DeltaFormat.percent),
        mode: MarketColorMode.greenUpRedDown,
      ),
    );
    await tester.pumpAndSettle();
    var iconIntl = tester.widget<Icon>(find.byType(Icon));

    expect(iconIntl.color, isNot(colorCn));
  });

  testWidgets('DeltaText: zero shows the flat icon', (tester) async {
    await tester.pumpWidget(
      _wrap(const DeltaText(value: 0, format: DeltaFormat.percent)),
    );
    expect(tester.widget<Icon>(find.byType(Icon)).icon, FLucideIcons.minus);
  });

  testWidgets('DeltaText: negative shows down arrow', (tester) async {
    await tester.pumpWidget(
      _wrap(const DeltaText(value: -3.4, format: DeltaFormat.percent)),
    );
    expect(
      tester.widget<Icon>(find.byType(Icon)).icon,
      FLucideIcons.chevronDown,
    );
  });

  testWidgets('DeltaText hides value and direction inside AmountPrivacyScope', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const AmountPrivacyScope(
          hidden: true,
          child: DeltaText(value: -3.4, format: DeltaFormat.percent),
        ),
      ),
    );

    expect(find.byType(AmountPrivacyPlaceholder), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
    expect(find.textContaining('3.40%'), findsNothing);
    expect(find.text(AmountPrivacyScope.mask), findsNothing);
  });

  testWidgets('DeltaText.percentFromRatio renders 2.34% for 0.0234', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(DeltaText.percentFromRatio(ratio: 0.0234)));
    // Expect "+2.34%" somewhere in the rendered text.
    expect(find.textContaining('2.34%'), findsOneWidget);
  });

  testWidgets(
    'DeltaText emits a single semantics node carrying sign + value + currency',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(const DeltaText(value: -1234.56, currencyCode: 'USD')),
      );
      // The Semantics(excludeSemantics: true) wrapper means the inner
      // Icon + Text don't leak as separate nodes; only our spoken label
      // is exposed to assistive tech.
      expect(
        find.bySemanticsLabel(RegExp(r'^-1,234\.56 USD$')),
        findsOneWidget,
      );
      handle.dispose();
    },
  );
}
