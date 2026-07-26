import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  group('AppTheme', () {
    test('light theme exposes Material theme tokens', () {
      final theme = AppTheme.light();
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, AccentColors.primary(Brightness.light));
      expect(theme.colorScheme.onSurfaceVariant, ColorPalette.navy500);
      expect(theme.textTheme.bodyMedium, isNotNull);
    });

    test('dark theme uses dark variants', () {
      final theme = AppTheme.dark();
      expect(theme.colorScheme.onSurfaceVariant, ColorPalette.navy300);
      expect(theme.brightness, Brightness.dark);
      // Dark divider != light divider.
      expect(SemanticColors.dark.divider, isNot(SemanticColors.light.divider));
    });

    test('market mode resolves MarketColors token set', () {
      final cn = MarketColors.fromMode(
        MarketColorMode.redUpGreenDown,
        brightness: Brightness.light,
      );
      final intl = MarketColors.fromMode(
        MarketColorMode.greenUpRedDown,
        brightness: Brightness.light,
      );
      expect(cn.mode, MarketColorMode.redUpGreenDown);
      expect(intl.mode, MarketColorMode.greenUpRedDown);
      expect(cn.up, intl.down);
    });
  });

  testWidgets('context.appTheme resolves from context', (tester) async {
    AppStatus? status;
    AppMarket? market;

    await tester.pumpWidget(
      AppThemeScope(
        data: resolveAppTheme(
          const ThemeInputs(
            brightness: Brightness.light,
            marketMode: MarketColorMode.redUpGreenDown,
          ),
        ),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              status = context.appTheme.status;
              market = context.appTheme.market;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(status, isNotNull);
    expect(market, isNotNull);
    expect(market!.mode, MarketColorMode.redUpGreenDown);
  });
}
