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
      expect(theme.textTheme.bodyMedium, isNotNull);
    });

    test('dark theme uses dark variants', () {
      final theme = AppTheme.dark();
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

  testWidgets('SemanticColors.of / MarketColors.of resolve from context', (
    tester,
  ) async {
    SemanticColors? semantic;
    MarketColors? market;

    await tester.pumpWidget(
      MarketColorsScope(
        colors: MarketColors.fromMode(
          MarketColorMode.redUpGreenDown,
          brightness: Brightness.light,
        ),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              semantic = SemanticColors.of(context);
              market = MarketColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(semantic, isNotNull);
    expect(market, isNotNull);
    expect(market!.mode, MarketColorMode.redUpGreenDown);
  });
}
