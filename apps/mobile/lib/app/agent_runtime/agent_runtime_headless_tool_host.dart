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
import 'package:flutter_riverpod/misc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/composition/device_tools_provider.dart';
import '../../core/ai/composition/tool_descriptor_lookup.dart';
import '../../core/ai/contracts/tool_descriptor.dart';
import '../../core/ai/runtime/device/tools/device_tool.dart';
import '../../core/ai/runtime/device/tools/device_tool_registry.dart'
    show kShellDeviceToolsCore, kShellToolDescriptors;
import '../../core/auth/auth_state.dart';
import '../../core/auth/domain_scope.dart';
import '../../core/auth/providers.dart' as auth;
import '../../core/config/app_config.dart';
import '../../core/config/providers.dart';
import '../../core/persistence/app_database.dart';
import '../../core/persistence/providers.dart';
import '../../design_system/preferences/theme_preferences.dart';
import '../../features/execution_ai_tools.dart';
import '../../features/finance_ai_tools.dart';
import '../../features/health_ai_tools.dart';
import '../../features/knowledge_ai_tools.dart';
import 'agent_runtime_tool_host.dart';

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
  // Headless CLI mode deliberately avoids platform plugin storage.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase(
    DatabaseConnection(NativeDatabase.memory(logStatements: false)),
  );

  final container = ProviderContainer(
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
      auth.authTokenDomainsProvider.overrideWithValue(
        _activeHeadlessDomains(domains).map((scope) => scope.wire).toList()
          ..sort(),
      ),
      ..._headlessToolOverrides(domains),
    ],
  );

  await container.read(auth.domainOptInsProvider.future);
  for (final domain in domains) {
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

List<Override> _headlessToolOverrides(Iterable<DomainScope> domains) {
  final activeDomains = _activeHeadlessDomains(domains);
  return <Override>[
    deviceToolsProvider.overrideWithValue(_headlessDeviceTools(activeDomains)),
    toolDescriptorLookupProvider.overrideWithValue((name) {
      return _headlessToolDescriptors(activeDomains)[name];
    }),
  ];
}

Set<DomainScope> _activeHeadlessDomains(Iterable<DomainScope> domains) {
  return <DomainScope>{DomainScope.finance, ...domains};
}

List<DeviceTool> _headlessDeviceTools(Set<DomainScope> domains) {
  return <DeviceTool>[
    ...kShellDeviceToolsCore,
    if (domains.contains(DomainScope.finance)) ...kFinanceDeviceTools,
    if (domains.contains(DomainScope.health)) ...kHealthDeviceTools,
    if (domains.contains(DomainScope.knowledge)) ...kKnowledgeDeviceTools,
    if (domains.contains(DomainScope.execution)) ...kExecutionDeviceTools,
  ];
}

Map<String, ToolDescriptor> _headlessToolDescriptors(Set<DomainScope> domains) {
  return <String, ToolDescriptor>{
    ...kShellToolDescriptors,
    if (domains.contains(DomainScope.finance)) ...kFinanceToolDescriptors,
    if (domains.contains(DomainScope.health)) ...kHealthToolDescriptors,
    if (domains.contains(DomainScope.knowledge)) ...kKnowledgeToolDescriptors,
    if (domains.contains(DomainScope.execution)) ...kExecutionToolDescriptors,
  };
}

List<DomainScope> parseHeadlessDomains(String? raw) {
  if (raw == null || raw.trim().isEmpty || raw == 'finance') {
    return const <DomainScope>[DomainScope.finance];
  }
  if (raw.trim() == 'all') {
    return DomainScope.values;
  }
  final parsed = <DomainScope>{DomainScope.finance};
  for (final part in raw.split(',')) {
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
