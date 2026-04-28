import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  group('MarketColors.fromMode', () {
    test('CN mode: positive delta resolves to red, negative to green', () {
      final m = MarketColors.fromMode(
        MarketColorMode.redUpGreenDown,
        brightness: Brightness.light,
      );
      expect(m.forDelta(1.0), m.up);
      expect(m.forDelta(-1.0), m.down);
      expect(m.forDelta(0), m.flat);
      expect(m.forDelta(null), m.flat);
      // Sanity: red > green tonally — red 600 has higher red channel.
      expect((m.up.r * 255).round() > (m.down.r * 255).round(), isTrue);
    });

    test('INTL mode swaps up/down vs CN mode', () {
      final cn = MarketColors.fromMode(
        MarketColorMode.redUpGreenDown,
        brightness: Brightness.light,
      );
      final intl = MarketColors.fromMode(
        MarketColorMode.greenUpRedDown,
        brightness: Brightness.light,
      );
      expect(intl.up, cn.down);
      expect(intl.down, cn.up);
    });

    test('Colorblind mode uses Wong palette (blue up, orange down)', () {
      final cb = MarketColors.fromMode(
        MarketColorMode.colorblind,
        brightness: Brightness.light,
      );
      expect(cb.up, ColorPalette.cbBlue);
      expect(cb.down, ColorPalette.cbOrange);
    });

    test('Dark variants differ from light variants', () {
      final lightCn = MarketColors.fromMode(
        MarketColorMode.redUpGreenDown,
        brightness: Brightness.light,
      );
      final darkCn = MarketColors.fromMode(
        MarketColorMode.redUpGreenDown,
        brightness: Brightness.dark,
      );
      expect(lightCn.up, isNot(darkCn.up));
      expect(lightCn.down, isNot(darkCn.down));
    });

    test('container helpers fall through to flat for zero', () {
      final m = MarketColors.fromMode(
        MarketColorMode.redUpGreenDown,
        brightness: Brightness.light,
      );
      // Flat container is a translucent flat — opacity < 1.
      final flatContainer = m.containerForDelta(0);
      expect(flatContainer.a, lessThan(1.0));
      expect(m.onContainerForDelta(0), m.onFlat);
    });
  });

  group('MarketColorMode.fromKey', () {
    test('round-trips persisted keys', () {
      for (final m in MarketColorMode.values) {
        expect(MarketColorMode.fromKey(m.persistedKey), m);
      }
    });

    test('falls back to redUpGreenDown for unknown / null', () {
      expect(MarketColorMode.fromKey(null), MarketColorMode.redUpGreenDown);
      expect(
        MarketColorMode.fromKey('garbage'),
        MarketColorMode.redUpGreenDown,
      );
    });
  });
}
