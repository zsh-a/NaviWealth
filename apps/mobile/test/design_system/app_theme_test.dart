import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  group('AppTheme', () {
    test('light theme exposes all design ThemeExtensions', () {
      final theme = AppTheme.light();
      expect(theme.brightness, Brightness.light);
      expect(theme.extension<SemanticColors>(), isNotNull);
      expect(theme.extension<MarketColors>(), isNotNull);
      expect(theme.extension<AppElevations>(), isNotNull);
    });

    test('dark theme uses dark variants', () {
      final theme = AppTheme.dark();
      expect(theme.brightness, Brightness.dark);
      // Dark divider != light divider.
      expect(
        theme.extension<SemanticColors>()!.divider,
        isNot(SemanticColors.light().divider),
      );
    });

    test('market mode propagates to MarketColors extension', () {
      final cn = AppTheme.light(
        marketColorMode: MarketColorMode.redUpGreenDown,
      ).extension<MarketColors>()!;
      final intl = AppTheme.light(
        marketColorMode: MarketColorMode.greenUpRedDown,
      ).extension<MarketColors>()!;
      expect(cn.mode, MarketColorMode.redUpGreenDown);
      expect(intl.mode, MarketColorMode.greenUpRedDown);
      expect(cn.up, intl.down);
    });
  });

  testWidgets('SemanticColors.of / MarketColors.of resolve from context', (
    tester,
  ) async {
    SemanticColors? semantic;
    MarketColors? market;
    AppElevations? elevations;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            semantic = SemanticColors.of(context);
            market = MarketColors.of(context);
            elevations = AppElevations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(semantic, isNotNull);
    expect(market, isNotNull);
    expect(market!.mode, MarketColorMode.redUpGreenDown);
    expect(elevations!.level2, isNotEmpty);
  });
}
