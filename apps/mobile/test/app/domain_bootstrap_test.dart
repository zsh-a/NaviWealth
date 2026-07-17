import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/domain_bootstrap.dart';
import 'package:naviwealth/core/auth/auth_state.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/data_management/providers.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/sync/providers.dart';

final _authStateProvider = StateProvider<AuthState?>(
  (_) => const AuthLoggedOut(),
);

void main() {
  test(
    'auth-gated startup mounts after a later local-only transition',
    () async {
      var syncStarts = 0;
      var maintenanceStarts = 0;
      var memoryMaintenanceStarts = 0;
      var memoryLayerStarts = 0;
      var agentSchedulerStarts = 0;
      final container = ProviderContainer(
        overrides: <Override>[
          auth.authStateProvider.overrideWith(
            (ref) => ref.watch(_authStateProvider),
          ),
          syncSchedulerBootstrapProvider.overrideWith((_) => syncStarts++),
          dataMaintenanceBootstrapProvider.overrideWith(
            (_) => maintenanceStarts++,
          ),
          memoryRuntimeMaintenanceBootstrapProvider.overrideWith(
            (_) => memoryMaintenanceStarts++,
          ),
          memoryLayerBootstrapProvider.overrideWith((_) => memoryLayerStarts++),
          agentForegroundSchedulerBootstrapProvider.overrideWith(
            (_) => agentSchedulerStarts++,
          ),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen<void>(
        authenticatedStartupBootstrapProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      expect(<int>[
        syncStarts,
        maintenanceStarts,
        memoryMaintenanceStarts,
        memoryLayerStarts,
        agentSchedulerStarts,
      ], everyElement(0));

      container.read(_authStateProvider.notifier).state = const AuthLocalOnly();
      await Future<void>.delayed(Duration.zero);

      expect(<int>[
        syncStarts,
        maintenanceStarts,
        memoryMaintenanceStarts,
        memoryLayerStarts,
        agentSchedulerStarts,
      ], everyElement(1));
    },
  );

  test('domain background hooks re-evaluate when auth changes', () async {
    var backgroundRuns = 0;
    final pack = DomainPack(
      scope: DomainScope.finance,
      backgroundBootstrapBuilder: (_) => backgroundRuns++,
    );
    final container = ProviderContainer(
      overrides: <Override>[
        auth.authStateProvider.overrideWith(
          (ref) => ref.watch(_authStateProvider),
        ),
        domainPackRegistryProvider.overrideWith((_) => <DomainPack>[pack]),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen<void>(
      domainBackgroundBootstrapProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    expect(backgroundRuns, 1);

    container.read(_authStateProvider.notifier).state = const AuthLocalOnly();
    await Future<void>.delayed(Duration.zero);

    expect(backgroundRuns, 2);
  });
}
