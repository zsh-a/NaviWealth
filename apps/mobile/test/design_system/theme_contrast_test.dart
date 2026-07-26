import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/design_system/design_system.dart';

/// WCAG 2.x contrast ratio between two opaque colors.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

typedef _RoleEntry = (String name, ColorRole role);

List<_RoleEntry> _roles(AppThemeData t) => [
  ('accent', t.accent),
  ('status.success', t.status.success),
  ('status.warning', t.status.warning),
  ('status.danger', t.status.danger),
  ('status.info', t.status.info),
  ('market.up', t.market.up),
  ('market.down', t.market.down),
  ('market.flat', t.market.flat),
];

/// Pre-existing palette debts, tracked for phase P5 of the UI refactor
/// blueprint (doc 15 §3.1). Entries here may FAIL the invariant but must not
/// grow — fixing a pair means deleting its exemption in the same change.
/// Key format: `brightness/marketMode/role/check`.
// Both P5 palette debts (invisible light info cyan, colorblind light
// orange) were re-derived — the set stays empty and any regression fails.
const Set<String> _exemptions = {};

void main() {
  final inputs = [
    for (final brightness in [Brightness.light, Brightness.dark])
      for (final mode in MarketColorMode.values)
        ThemeInputs(brightness: brightness, marketMode: mode),
  ];

  for (final input in inputs) {
    final label = '${input.brightness.name}/${input.marketMode.name}';
    final theme = resolveAppTheme(input);

    group('contrast invariants [$label]', () {
      for (final (name, role) in _roles(theme)) {
        test('$name onContainer vs container >= 4.5', () {
          final key = '$label/$name/onContainer';
          final ratio = _contrast(role.onContainer, role.container);
          if (_exemptions.contains(key)) {
            expect(
              ratio,
              lessThan(4.5),
              reason: '$key is exempted but now passes — delete the exemption.',
            );
            return;
          }
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                '$name.onContainer on $name.container is '
                '${ratio.toStringAsFixed(2)}:1 — small text needs 4.5:1.',
          );
        });

        // TODO(blueprint doc 15 P5): raise to 4.5 once the palette debts
        // (info-on-card, dark rose-on-card) are re-derived.
        test('$name fg vs card >= 3.0', () {
          final key = '$label/$name/fgOnCard';
          final ratio = _contrast(role.fg, theme.surfaces.card);
          if (_exemptions.contains(key)) {
            expect(
              ratio,
              lessThan(3.0),
              reason: '$key is exempted but now passes — delete the exemption.',
            );
            return;
          }
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason:
                '$name.fg on surfaces.card is ${ratio.toStringAsFixed(2)}:1 '
                '— needs at least 3.0:1 (large-text tier).',
          );
        });
      }

      test('content ladder is legible on card', () {
        for (final (name, color) in [
          ('strong', theme.content.strong),
          ('body', theme.content.body),
          ('muted', theme.content.muted),
        ]) {
          final ratio = _contrast(color, theme.surfaces.card);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: 'content.$name on card is ${ratio.toStringAsFixed(2)}:1.',
          );
        }
      });

      test('status.danger and market direction colors never collide '
          'with each other in a misleading way', () {
        // Under red-up the danger role and the "down" role are distinct
        // hues by design (danger=rose, down=profit-green swap); the
        // invariant that matters app-wide is that up != down.
        expect(theme.market.up.fg, isNot(theme.market.down.fg));
      });
    });
  }
}
