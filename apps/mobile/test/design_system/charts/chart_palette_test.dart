import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

Widget _wrap(
  Widget child, {
  Brightness brightness = Brightness.light,
  MarketColorMode mode = MarketColorMode.redUpGreenDown,
}) {
  final theme = brightness == Brightness.dark
      ? AppTheme.dark(marketColorMode: mode)
      : AppTheme.light(marketColorMode: mode);
  return MaterialApp(
    theme: theme,
    home: Scaffold(body: Builder(builder: (_) => child)),
  );
}

void main() {
  group('ChartPalette', () {
    testWidgets('exposes 8 distinct accent colors', (tester) async {
      late ChartPalette palette;
      await tester.pumpWidget(_wrap(Builder(builder: (ctx) {
        palette = ChartPalette.of(ctx);
        return const SizedBox();
      })));
      expect(palette.accentSequence.length, 8);
      expect(palette.accentSequence.toSet().length, 8,
          reason: 'all accent colors should be distinct');
    });

    testWidgets('dark mode swaps to lighter accents', (tester) async {
      late ChartPalette light;
      await tester.pumpWidget(_wrap(Builder(builder: (ctx) {
        light = ChartPalette.of(ctx);
        return const SizedBox();
      })));
      await tester.pumpAndSettle();
      late ChartPalette dark;
      await tester.pumpWidget(_wrap(
        Builder(builder: (ctx) {
          dark = ChartPalette.of(ctx);
          return const SizedBox();
        }),
        brightness: Brightness.dark,
      ));
      await tester.pumpAndSettle();
      expect(dark.accentSequence, isNot(equals(light.accentSequence)));
    });

    testWidgets('grid line follows SemanticColors.divider', (tester) async {
      late ChartPalette palette;
      late SemanticColors semantic;
      await tester.pumpWidget(_wrap(Builder(builder: (ctx) {
        palette = ChartPalette.of(ctx);
        semantic = SemanticColors.of(ctx);
        return const SizedBox();
      })));
      expect(palette.gridLine, semantic.divider);
    });

    testWidgets('accentAt wraps when index exceeds length', (tester) async {
      late ChartPalette palette;
      await tester.pumpWidget(_wrap(Builder(builder: (ctx) {
        palette = ChartPalette.of(ctx);
        return const SizedBox();
      })));
      expect(palette.accentAt(0), palette.accentAt(palette.accentSequence.length));
      expect(palette.accentAt(11), palette.accentSequence[11 % 8]);
    });
  });

  group('resolveSeriesColor', () {
    testWidgets('primary → colorScheme.primary', (tester) async {
      late Color resolved;
      late ColorScheme scheme;
      await tester.pumpWidget(_wrap(Builder(builder: (ctx) {
        scheme = Theme.of(ctx).colorScheme;
        resolved = resolveSeriesColor(
          ctx,
          intent: SeriesIntent.primary,
          ordinal: 0,
        );
        return const SizedBox();
      })));
      expect(resolved, scheme.primary);
    });

    testWidgets('up / down follow MarketColors and flip with mode', (
      tester,
    ) async {
      late Color upCn, downCn;
      await tester.pumpWidget(_wrap(
        Builder(builder: (ctx) {
          upCn = resolveSeriesColor(ctx, intent: SeriesIntent.up, ordinal: 0);
          downCn = resolveSeriesColor(
            ctx,
            intent: SeriesIntent.down,
            ordinal: 0,
          );
          return const SizedBox();
        }),
        mode: MarketColorMode.redUpGreenDown,
      ));
      await tester.pumpAndSettle();
      late Color upIntl;
      await tester.pumpWidget(_wrap(
        Builder(builder: (ctx) {
          upIntl = resolveSeriesColor(
            ctx,
            intent: SeriesIntent.up,
            ordinal: 0,
          );
          return const SizedBox();
        }),
        mode: MarketColorMode.greenUpRedDown,
      ));
      await tester.pumpAndSettle();
      expect(upCn, isNot(upIntl));
      expect(upCn, isNot(downCn));
    });

    testWidgets('benchmark walks the accent sequence', (tester) async {
      late Color first, second;
      late ChartPalette palette;
      await tester.pumpWidget(_wrap(Builder(builder: (ctx) {
        palette = ChartPalette.of(ctx);
        first = resolveSeriesColor(
          ctx,
          intent: SeriesIntent.benchmark,
          ordinal: 0,
        );
        second = resolveSeriesColor(
          ctx,
          intent: SeriesIntent.benchmark,
          ordinal: 1,
        );
        return const SizedBox();
      })));
      expect(first, palette.accentAt(0));
      expect(second, palette.accentAt(1));
      expect(first, isNot(second));
    });

    testWidgets('override wins over intent', (tester) async {
      const sentinel = Color(0xFF1234AB);
      late Color resolved;
      await tester.pumpWidget(_wrap(Builder(builder: (ctx) {
        resolved = resolveSeriesColor(
          ctx,
          intent: SeriesIntent.primary,
          ordinal: 0,
          override: sentinel,
        );
        return const SizedBox();
      })));
      expect(resolved, sentinel);
    });
  });
}
