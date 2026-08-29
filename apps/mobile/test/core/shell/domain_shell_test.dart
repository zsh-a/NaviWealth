import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/shell/domain_shell.dart';
import 'package:naviwealth/features/execution/composition/execution_domain_shell.dart';
import 'package:naviwealth/features/execution/composition/execution_route_paths.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_domain_shell.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_route_paths.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

DomainShellSpec _spec(DomainScope scope) => DomainShellSpec(
  scope: scope,
  label: scope.wire,
  icon: const IconData(0xe000),
  selectedIcon: const IconData(0xe001),
  tabs: const <DomainShellTab>[],
);

DomainShellTab _tab(String routePath) => DomainShellTab(
  icon: const IconData(0xe000),
  selectedIcon: const IconData(0xe001),
  label: routePath,
  routePath: routePath,
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

  group('hidden (routable-only) tabs', () {
    test('specOwnsPath resolves hidden tab roots and nested paths', () {
      final spec = DomainShellSpec(
        scope: DomainScope.knowledge,
        label: 'KnowledgeOS',
        icon: const IconData(0xe000),
        selectedIcon: const IconData(0xe001),
        tabs: <DomainShellTab>[_tab('/knowledge')],
        hiddenTabs: <DomainShellTab>[_tab('/knowledge/review')],
      );

      expect(specOwnsPath(spec, '/knowledge'), isTrue);
      expect(specOwnsPath(spec, '/knowledge/review'), isTrue);
      expect(specOwnsPath(spec, '/knowledge/review/weekly'), isTrue);
      expect(specOwnsPath(spec, '/execution'), isFalse);
    });

    test('nav-visible tabs stay exactly spec.tabs', () {
      final spec = DomainShellSpec(
        scope: DomainScope.execution,
        label: 'ExecutionOS',
        icon: const IconData(0xe000),
        selectedIcon: const IconData(0xe001),
        tabs: <DomainShellTab>[_tab('/execution'), _tab('/execution/plans')],
        hiddenTabs: <DomainShellTab>[_tab('/execution/review')],
      );

      final navRoutes = spec.tabs.map((t) => t.routePath).toList();
      expect(navRoutes, <String>['/execution', '/execution/plans']);
      expect(navRoutes, isNot(contains(spec.hiddenTabs.single.routePath)));
    });

    test('KnowledgeOS declares Review as a hidden tab', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final spec = knowledgeDomainShell(l10n);

      expect(spec.tabs, hasLength(2));
      expect(spec.hiddenTabs, hasLength(1));
      expect(spec.hiddenTabs.single.routePath, KnowledgeRoutes.review);
      expect(
        spec.tabs.map((t) => t.routePath),
        isNot(contains(KnowledgeRoutes.review)),
      );
      expect(specOwnsPath(spec, KnowledgeRoutes.review), isTrue);
    });

    test('ExecutionOS declares Review as a hidden tab', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final spec = executionDomainShell(l10n);

      expect(spec.tabs, hasLength(2));
      expect(spec.hiddenTabs, hasLength(1));
      expect(spec.hiddenTabs.single.routePath, ExecutionRoutes.review);
      expect(
        spec.tabs.map((t) => t.routePath),
        isNot(contains(ExecutionRoutes.review)),
      );
      expect(specOwnsPath(spec, ExecutionRoutes.review), isTrue);
    });
  });
}
