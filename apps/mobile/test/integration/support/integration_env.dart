// Integration-test environment (docs/development/testing-strategy.md §4 "Integration").
//
// Unlike flow tests (which stub the data layer to deterministic streams),
// an integration env wires a *real* in-memory Drift database into the
// production provider graph, so repository writes, Drift streams, and the
// dashboard read-model aggregator are all exercised for real — only the
// non-deterministic edges (auth session, HLC stamper) are faked.
//
// Faked edges and why:
//   - authControllerProvider → AuthLocalOnly: selects the local-only code
//     paths (NoopOutboxStore, no backend Dio), so nothing reaches the
//     network or a sync engine.
//   - mutationStamperProvider → makeStubStamper(): a deterministic HLC
//     stamper, the sanctioned test seam (see mutation_context.dart) that
//     sidesteps the secure-storage device-identity lookup.
//
// Everything downstream — accountsStreamProvider, manualAssetsStreamProvider,
// dashboardSnapshotProvider — runs against the real database.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/sync/mutation_context.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/features/auth/data/auth_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/persistence/test_database.dart';
import '../../features/finance/data/repositories/_stub_stamper.dart';

class _LocalOnlyAuthController extends AuthController {
  @override
  Future<AuthState> build() async => const AuthLocalOnly();
}

/// A real-database integration environment. The returned [container] is
/// wired to a fresh in-memory [db]; both are torn down automatically via
/// the active test's `addTearDown`.
class IntegrationEnv {
  IntegrationEnv._(this.container, this.db);

  final ProviderContainer container;
  final AppDatabase db;

  /// [extraOverrides] are appended after the base overrides, so a test can
  /// replace any provider it needs (e.g. swap the live price resolver for a
  /// deterministic fake) without rebuilding the base wiring.
  static Future<IntegrationEnv> create({
    List<Override> extraOverrides = const [],
  }) async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final db = makeTestDatabase();

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWith((ref) async => db),
        authControllerProvider.overrideWith(_LocalOnlyAuthController.new),
        mutationStamperProvider.overrideWith((ref) async => makeStubStamper()),
        ...extraOverrides,
      ],
    );

    addTearDown(() async {
      container.dispose();
      await db.close();
    });
    return IntegrationEnv._(container, db);
  }

  /// Keeps an autoDispose provider alive for the rest of the test. Stream
  /// providers dispose the instant they have no listener, so call this
  /// before reading their `.future`.
  void keepAlive(ProviderListenable<Object?> provider) {
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
  }
}
