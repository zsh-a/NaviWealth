/// Headless process-host wiring for the Rust agent runtime.
///
/// This is the CLI-safe sibling of full Flutter bootstrap. It mounts the
/// production domain tool graph in a [ProviderContainer], but uses mock
/// preferences and an in-memory Drift database so `flutter pub run` can expose
/// app-backed tools to the Rust CLI without starting the UI or touching the
/// user's production database.
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_host.dart';
import 'package:naviwealth/app/domain_composition.dart';
import 'package:naviwealth/app/domain_packs.dart';
import 'package:naviwealth/core/auth/auth_state.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/config/app_config.dart';
import 'package:naviwealth/core/config/providers.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AgentRuntimeHeadlessToolHost {
  AgentRuntimeHeadlessToolHost._({
    required this.container,
    required this.host,
    required AppDatabase database,
  }) : _database = database;

  final ProviderContainer container;
  final AgentRuntimeToolHost host;
  final AppDatabase _database;

  Future<void> dispose() async {
    container.dispose();
    await _database.close();
  }
}

Future<AgentRuntimeHeadlessToolHost> createAgentRuntimeHeadlessToolHost({
  Iterable<DomainScope> domains = const <DomainScope>[DomainScope.finance],
}) async {
  final activeDomains = _activeHeadlessDomains(domains);
  final activePacks = _headlessDomainPacks(activeDomains);

  // Headless CLI mode deliberately avoids platform plugin storage.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase(
    DatabaseConnection(NativeDatabase.memory(logStatements: false)),
  );

  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      appConfigProvider.overrideWithValue(
        const AppConfig(
          apiBaseUrl: 'http://127.0.0.1:8787',
          environment: AppEnvironment.dev,
          bypassAuth: true,
        ),
      ),
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWith((_) async => db),
      auth.authStateProvider.overrideWithValue(const AuthLocalOnly()),
      ...lifeOsDomainCompositionOverrides(packs: activePacks),
    ],
  );

  await container.read(auth.domainOptInsProvider.future);
  for (final domain in activeDomains) {
    if (domain == DomainScope.finance) continue;
    await container
        .read(auth.domainOptInsProvider.notifier)
        .setEnabled(domain, true);
  }

  return AgentRuntimeHeadlessToolHost._(
    container: container,
    host: container.read(agentRuntimeToolHostProvider),
    database: db,
  );
}

Set<DomainScope> _activeHeadlessDomains(Iterable<DomainScope> domains) {
  return <DomainScope>{DomainScope.finance, ...domains};
}

List<DomainPack> _headlessDomainPacks(Set<DomainScope> domains) {
  return [
    for (final pack in kAllDomainPacks)
      if (domains.contains(pack.scope)) pack,
  ];
}

List<DomainScope> parseHeadlessDomains(String? raw) {
  final trimmed = raw?.trim();
  if (trimmed == null || trimmed.isEmpty || trimmed == 'finance') {
    return const <DomainScope>[DomainScope.finance];
  }
  if (trimmed == 'all') {
    return _productionDomainScopes();
  }
  final parsed = <DomainScope>{DomainScope.finance};
  for (final part in trimmed.split(',')) {
    final value = part.trim();
    if (value.isEmpty) continue;
    final scope = DomainScope.tryParse(value);
    if (scope == null) {
      throw ArgumentError.value(raw, 'domains', 'unknown domain "$value"');
    }
    parsed.add(scope);
  }
  return parsed.toList(growable: false);
}

List<DomainScope> _productionDomainScopes() {
  return [for (final pack in kAllDomainPacks) pack.scope];
}
