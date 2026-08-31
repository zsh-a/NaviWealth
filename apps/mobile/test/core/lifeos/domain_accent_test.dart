import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/design_system/design_system.dart';

void main() {
  group('DomainAccent', () {
    test('resolves the light/dark pair by brightness', () {
      const accent = DomainAccent(
        light: Color(0xFF111111),
        dark: Color(0xFFEEEEEE),
      );
      expect(accent.resolve(Brightness.light), const Color(0xFF111111));
      expect(accent.resolve(Brightness.dark), const Color(0xFFEEEEEE));
    });
  });

  group('resolveDomainAccent', () {
    test('returns null for unregistered scopes and accent-less packs', () {
      const packs = <DomainPack>[DomainPack(scope: DomainScope.finance)];
      expect(
        resolveDomainAccent(packs, DomainScope.finance, Brightness.light),
        isNull,
      );
      expect(
        resolveDomainAccent(packs, DomainScope.health, Brightness.light),
        isNull,
      );
      expect(
        resolveDomainAccent(
          const <DomainPack>[],
          DomainScope.finance,
          Brightness.light,
        ),
        isNull,
      );
    });

    test('resolves the pack accent per brightness', () {
      const accent = DomainAccent(
        light: Color(0xFF111111),
        dark: Color(0xFFEEEEEE),
      );
      const packs = <DomainPack>[
        DomainPack(scope: DomainScope.knowledge, accent: accent),
      ];
      expect(
        resolveDomainAccent(packs, DomainScope.knowledge, Brightness.light),
        const Color(0xFF111111),
      );
      expect(
        resolveDomainAccent(packs, DomainScope.knowledge, Brightness.dark),
        const Color(0xFFEEEEEE),
      );
    });
  });

  group('DomainAccents catalog', () {
    test('all four production domains declare distinct hues', () {
      const accents = <DomainAccent>[
        DomainAccents.finance,
        DomainAccents.health,
        DomainAccents.knowledge,
        DomainAccents.execution,
      ];
      final lightHues = accents.map((a) => a.light).toSet();
      final darkHues = accents.map((a) => a.dark).toSet();
      expect(lightHues, hasLength(4));
      expect(darkHues, hasLength(4));
    });
  });
}
