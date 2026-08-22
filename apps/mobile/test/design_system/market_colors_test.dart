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
      // Wong colorblind palette: blue up, orange down. Light mode uses the
      // dark orange as fg — bright #E69F00 is ~2.3:1 on white and fails the
      // contrast invariant (doc 15 §3.1); the bright hue stays in
      // container/chart roles.
      expect(cb.up, const Color(0xFF2271B3));
      expect(cb.down, const Color(0xFF8A5F00));
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

    test('upMuted / downMuted desaturate the full-saturation tone', () {
      // 80% saturation per FIR-104 — `mutedFor` keeps hue but shaves
      // saturation so dense lists don't read as fireworks.
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final m = MarketColors.fromMode(
          MarketColorMode.greenUpRedDown,
          brightness: brightness,
        );
        final upHsl = HSLColor.fromColor(m.up);
        final upMutedHsl = HSLColor.fromColor(m.upMuted);
        // Hue is preserved (modulo float wobble).
        expect(upMutedHsl.hue, closeTo(upHsl.hue, 1.0));
        // Saturation drops by ~20%.
        expect(upMutedHsl.saturation, lessThan(upHsl.saturation));
        expect(upMutedHsl.saturation, closeTo(upHsl.saturation * 0.8, 0.02));

        final downHsl = HSLColor.fromColor(m.down);
        final downMutedHsl = HSLColor.fromColor(m.downMuted);
        expect(downMutedHsl.saturation, lessThan(downHsl.saturation));
      }
    });

    test('mutedForDelta tracks forDelta direction', () {
      final m = MarketColors.fromMode(
        MarketColorMode.greenUpRedDown,
        brightness: Brightness.dark,
      );
      expect(m.mutedForDelta(1.5), m.upMuted);
      expect(m.mutedForDelta(-0.1), m.downMuted);
      expect(m.mutedForDelta(0), m.flat);
      expect(m.mutedForDelta(null), m.flat);
    });

    test('profitGlow follows the up hue under every market mode', () {
      // The hero glow tracks the mode's `up` color so the hero treatment
      // never contradicts the delta hue on screen (red-up CN mode gets a
      // red glow; green-up gets green; colorblind gets blue).
      for (final brightness in [Brightness.light, Brightness.dark]) {
        for (final mode in MarketColorMode.values) {
          final m = MarketColors.fromMode(mode, brightness: brightness);
          final glowHsl = HSLColor.fromColor(m.profitGlow);
          final upHsl = HSLColor.fromColor(m.up);
          expect(
            glowHsl.hue,
            closeTo(upHsl.hue, 1.0),
            reason:
                'profitGlow should match the up hue under '
                '$mode/${brightness.name}',
          );
          expect(
            m.profitGlow.a,
            closeTo(AppOpacity.glow, 0.02),
            reason: 'profitGlow keeps the shared glow base alpha',
          );
        }
      }
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
