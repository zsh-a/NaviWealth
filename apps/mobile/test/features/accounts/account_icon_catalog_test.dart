import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/features/accounts/account_icon_catalog.dart';

void main() {
  test('catalogue is non-empty and uniquely keyed', () {
    expect(kAccountIconCatalogue, isNotEmpty);
    final names = kAccountIconCatalogue.map((c) => c.name).toList();
    expect(
      names.toSet().length,
      names.length,
      reason: 'Duplicate names in icon catalogue: $names',
    );
  });

  test('every catalogue entry is reachable through resolveAccountIcon', () {
    for (final entry in kAccountIconCatalogue) {
      expect(
        resolveAccountIcon(entry.name),
        entry.icon,
        reason: 'Mismatch on ${entry.name}',
      );
    }
  });

  test('null / empty / unknown names resolve to null', () {
    expect(resolveAccountIcon(null), isNull);
    expect(resolveAccountIcon(''), isNull);
    expect(resolveAccountIcon('not_a_real_icon'), isNull);
  });

  test('every FIR-133 seeded icon name has a catalogue entry', () {
    // Pinned to the names referenced from
    // `AccountRepository._kSystemAccountTreeSeeds`. A FIR-133 seed
    // change that adds a new icon must also extend the catalogue —
    // otherwise the AccountTreePicker silently falls back to the
    // bullet glyph for that account, which defeats the purpose of
    // FIR-133 carrying [Account.icon] through to the UI.
    const seeded = <String>[
      'south_west',
      'north_east',
      'account_balance',
      'work',
      'paid',
      'savings',
      'trending_up',
      'more_horiz',
      'restaurant',
      'directions_bus',
      'home',
      'show_chart',
      'receipt_long',
      'request_quote',
      'credit_card',
      'flag',
      'call_split',
      'tune',
    ];
    for (final name in seeded) {
      expect(
        kAccountIconByName.containsKey(name),
        isTrue,
        reason: 'Missing catalogue entry for FIR-133 seed icon: $name',
      );
    }
  });

  test('default colour palette is non-empty and well-formed hex', () {
    expect(kAccountColorPalette, isNotEmpty);
    final hexPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');
    for (final hex in kAccountColorPalette) {
      expect(
        hexPattern.hasMatch(hex),
        isTrue,
        reason: 'Malformed colour string: $hex',
      );
    }
  });

  test('catalogue exposes a sane working size for the picker grid', () {
    // The grid is rendered horizontally; > ~40 entries makes the
    // picker a chore to scan. Pin the upper bound so a reviewer
    // accepting a CL that doubles the catalogue notices the UX
    // implication.
    expect(kAccountIconCatalogue.length, lessThanOrEqualTo(40));
    expect(kAccountIconCatalogue.length, greaterThanOrEqualTo(20));
  });

  test('catalogue icons all resolve to non-default IconData', () {
    for (final entry in kAccountIconCatalogue) {
      expect(entry.icon, isA<IconData>());
      // All Material Icons live under the 'MaterialIcons' font family
      // (modulo packaged icon fonts). Catching a stray free-form
      // IconData here keeps the catalogue honest.
      expect(entry.icon.fontFamily, isNotNull);
    }
  });
}
