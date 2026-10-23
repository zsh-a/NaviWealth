import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:naviwealth/app/domain_packs.dart';
import 'package:naviwealth/app/routing/route_paths.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/shell/domain_shell.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

import '../core/persistence/test_database.dart';

const _financeTabs = <String>[
  AppRoutes.home,
  AppRoutes.activity,
  AppRoutes.wealth,
  AppRoutes.plan,
];
const _healthTabs = <String>[AppRoutes.healthToday, AppRoutes.healthTrend];
const _knowledgeTabs = <String>[
  AppRoutes.knowledgeInbox,
  AppRoutes.knowledgeLibrary,
];
const _executionTabs = <String>[
  AppRoutes.executionToday,
  AppRoutes.executionPlans,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final pack in kAllDomainPacks) {
    test('${pack.scope.name} routes match visible and hidden shell tabs', () {
      final navigation = pack.shell.navigation!;
      final spec = navigation.shellSpecBuilder(
        lookupAppLocalizations(const Locale('en')),
      );
      final visible = spec.tabs.map((tab) => tab.routePath).toList();
      final hidden = spec.hiddenTabs.map((tab) => tab.routePath).toList();
      final route = navigation.shellRouteBuilder();
      final branchRoots = <String>[
        for (final branch in route.branches)
          (branch.routes.first as GoRoute).path,
      ];

      expect(spec.scope, pack.scope);
      expect(navigation.tabPaths, orderedEquals(visible));
      expect(branchRoots, orderedEquals([...visible, ...hidden]));
      expect(branchRoots.toSet(), hasLength(branchRoots.length));
      for (final path in [...visible, ...hidden]) {
        expect(domainForRoute(kAllDomainPacks, path), pack.scope);
        expect(specOwnsPath(spec, path), isTrue);
        expect(
          domainTabPathsForLocation(kAllDomainPacks, path),
          orderedEquals(visible),
        );
      }
      for (final path in hidden) {
        expect(navigation.tabPaths, isNot(contains(path)));
      }
      if (navigation.reviewRoutePath case final reviewPath?) {
        expect([...visible, ...hidden], contains(reviewPath));
      }
    });
  }

  test('global tab fallback skips a headless first pack', () {
    const headless = DomainPack(scope: DomainScope.health);
    final packs = [headless, kFinancePack, kExecutionPack];

    expect(
      domainTabPathsForLocation(packs, AppRoutes.settings),
      orderedEquals(_financeTabs),
    );
    expect(
      domainTabPathsForLocation(packs, AppRoutes.executionReview),
      orderedEquals(_executionTabs),
    );
    expect(
      domainTabPathsForLocation(const [headless], AppRoutes.settings),
      isEmpty,
    );
    expect(domainTabPathsForLocation(const [], AppRoutes.settings), isEmpty);
  });

  test('route ownership requires a complete tab or additional prefix', () {
    const packs = <DomainPack>[
      DomainPack(
        scope: DomainScope.finance,
        shell: DomainShellContribution(
          navigation: DomainNavigation(
            shellSpecBuilder: _unusedShellSpec,
            shellRouteBuilder: _unusedShellRoute,
            tabPaths: ['/ledger'],
            additionalPathPrefixes: ['/reports'],
          ),
        ),
      ),
    ];

    for (final prefix in ['/ledger', '/reports']) {
      expect(domainForRoute(packs, prefix), DomainScope.finance);
      expect(domainForRoute(packs, '$prefix/item'), DomainScope.finance);
      expect(domainForRoute(packs, '$prefix-old'), isNull);
      expect(domainForRoute(packs, '${prefix}ish/item'), isNull);
    }
    expect(domainForRoute(packs, AppRoutes.settings), isNull);
    expect(domainTabPathsForLocation(packs, '/reports/monthly'), ['/ledger']);
    for (final pack in kAllDomainPacks) {
      for (final prefix in pack.shell.navigation!.additionalPathPrefixes) {
        expect(domainForRoute(kAllDomainPacks, prefix), pack.scope);
        expect(domainForRoute(kAllDomainPacks, '$prefix/item'), pack.scope);
        expect(pack.shell.navigation!.tabPaths, isNot(contains(prefix)));
      }
    }
  });

  test(
    'primary paths react to opt-ins and exclude hidden destinations',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((ref) async => db),
          domainPackRegistryProvider.overrideWithValue(kAllDomainPacks),
        ],
      );
      addTearDown(container.dispose);
      container.listen(primaryTabPathsProvider, (_, _) {});

      expect(container.read(primaryTabPathsProvider), _financeTabs);
      await container.read(domainOptInsProvider.future);
      expect(container.read(primaryTabPathsProvider), _financeTabs);
      final optIns = container.read(domainOptInsProvider.notifier);

      await optIns.setEnabled(DomainScope.health, true);
      expect(container.read(primaryTabPathsProvider), [
        ..._financeTabs,
        ..._healthTabs,
      ]);
      await optIns.setEnabled(DomainScope.execution, true);
      await optIns.setEnabled(DomainScope.knowledge, true);
      expect(container.read(primaryTabPathsProvider), [
        ..._financeTabs,
        ..._healthTabs,
        ..._knowledgeTabs,
        ..._executionTabs,
      ]);
      expect(
        container.read(primaryTabPathsProvider),
        isNot(contains(AppRoutes.executionReview)),
      );

      await optIns.setEnabled(DomainScope.health, false);
      await optIns.setEnabled(DomainScope.finance, false);
      expect(container.read(primaryTabPathsProvider), [
        ..._financeTabs,
        ..._knowledgeTabs,
        ..._executionTabs,
      ]);
    },
  );
}

Never _unusedShellSpec(AppLocalizations _) =>
    throw StateError('Route ownership does not build shell UI.');

Never _unusedShellRoute() =>
    throw StateError('Route ownership does not build routes.');
