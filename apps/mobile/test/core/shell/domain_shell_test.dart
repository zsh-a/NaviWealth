import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/shell/domain_shell.dart';

DomainShellSpec _spec(DomainScope scope) => DomainShellSpec(
      scope: scope,
      label: scope.wire,
      icon: const IconData(0xe000),
      selectedIcon: const IconData(0xe001),
      tabs: const <DomainShellTab>[],
    );

void main() {
  group('D-1.8 multi-domain shell seam', () {
    test('default activeDomainShellsProvider is empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(activeDomainShellsProvider), isEmpty);
    });

    test('dock visible only when ≥ 2 specs are registered', () {
      final container = ProviderContainer(
        overrides: [
          activeDomainShellsProvider.overrideWith(
            (_) => <DomainShellSpec>[_spec(DomainScope.finance)],
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(domainDockVisibleProvider), isFalse);
    });

    test('dock visible with two active domains', () {
      final container = ProviderContainer(
        overrides: [
          activeDomainShellsProvider.overrideWith(
            (_) => <DomainShellSpec>[
              _spec(DomainScope.finance),
              _spec(DomainScope.health),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(domainDockVisibleProvider), isTrue);
    });
  });
}
