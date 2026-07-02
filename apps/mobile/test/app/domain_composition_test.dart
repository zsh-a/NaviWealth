import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/domain_composition.dart';
import 'package:naviwealth/app/domain_packs.dart';
import 'package:naviwealth/core/ai/agents/agent.dart';
import 'package:naviwealth/core/ai/agents/agent_registry.dart';
import 'package:naviwealth/core/ai/agents/agent_schedule.dart';
import 'package:naviwealth/core/ai/composition/composite_proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/device_tools_provider.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_kind_registry.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/ai/composition/system_prompt_blocks.dart';
import 'package:naviwealth/core/ai/composition/tool_descriptor_lookup.dart';
import 'package:naviwealth/core/ai/contracts/intent.dart';
import 'package:naviwealth/core/ai/contracts/privacy_budget.dart';
import 'package:naviwealth/core/ai/contracts/tool_descriptor.dart';
import 'package:naviwealth/core/ai/intent/intent.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/command_palette/command_palette_entry.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/core/persistence/app_database.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/shell/domain_shell.dart';
import 'package:naviwealth/design_system/preferences/theme_preferences.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/persistence/test_database.dart';

const _tool = _FakeTool('domain_tool');
const _agent = _FakeAgent('domain_agent');

final _domainSeamProvider = Provider<int>((ref) => 0);

const _financeDescriptor = ToolDescriptor(
  name: 'finance_descriptor',
  access: Access.read,
  risk: RiskLevel.info,
  requiresConfirmation: Confirmation.none,
  allowedContextTier: BudgetTier.small,
  domain: 'finance',
);

const _healthDescriptor = ToolDescriptor(
  name: 'health_descriptor',
  access: Access.read,
  risk: RiskLevel.info,
  requiresConfirmation: Confirmation.none,
  allowedContextTier: BudgetTier.small,
  domain: 'health',
);

const _financeIntent = IntentDescriptor(
  name: 'fake_finance_intent',
  allowedObjectTypes: <String>{'finance_object'},
  preferredCapabilities: <AiCapability>{AiCapability.chat},
);

const _healthIntent = IntentDescriptor(
  name: 'fake_health_intent',
  allowedObjectTypes: <String>{'health_object'},
  preferredCapabilities: <AiCapability>{AiCapability.chat},
  domain: kDomainHealth,
);

const _financePack = DomainPack(
  scope: DomainScope.finance,
  deviceTools: [_tool],
  toolDescriptors: <String, ToolDescriptor>{
    'finance_descriptor': _financeDescriptor,
  },
  intentDescriptors: [_financeIntent],
  proposalKinds: [
    ProposalKindMeta(
      kind: 'fake_finance',
      icon: Icons.account_balance,
      label: _fakeFinanceProposalLabel,
      toolName: 'propose_fake_finance',
    ),
  ],
  proposalApplierRouteBuilder: _fakeFinanceProposalRoute,
  systemPromptBlock: 'Finance block',
  commandPaletteEntriesBuilder: _financeEntries,
  agentBuilder: _financeAgents,
);

const _healthPack = DomainPack(
  scope: DomainScope.health,
  toolDescriptors: <String, ToolDescriptor>{
    'health_descriptor': _healthDescriptor,
  },
  intentDescriptors: [_healthIntent],
  proposalKinds: [
    ProposalKindMeta(
      kind: 'fake_health',
      icon: Icons.monitor_heart,
      label: _fakeHealthProposalLabel,
      toolName: 'propose_fake_health',
    ),
  ],
  proposalApplierRouteBuilder: _fakeHealthProposalRoute,
  systemPromptBlock: 'Health block',
  commandPaletteEntriesBuilder: _healthEntries,
);

String _fakeFinanceProposalLabel(AppLocalizations l10n) => 'Fake finance';
String _fakeHealthProposalLabel(AppLocalizations l10n) => 'Fake health';

Future<ProposalApplierRoute> _fakeFinanceProposalRoute(Ref ref) async =>
    const ProposalApplierRoute(
      applier: _FakeProposalApplier('finance_table'),
      kinds: {'fake_finance'},
      tablePrefixes: {'finance_table'},
    );

Future<ProposalApplierRoute> _fakeHealthProposalRoute(Ref ref) async =>
    const ProposalApplierRoute(
      applier: _FakeProposalApplier('health_table'),
      kinds: {'fake_health'},
      tablePrefixes: {'health_table'},
    );

List<CommandPaletteEntry> _financeEntries(AppLocalizations l10n) => [
  CommandPaletteEntry(
    id: 'finance',
    label: 'Finance',
    icon: Icons.account_balance,
    run: (_) {},
  ),
];

List<Agent> _financeAgents(Ref ref) => const <Agent>[_agent];

List<CommandPaletteEntry> _healthEntries(AppLocalizations l10n) => [
  CommandPaletteEntry(
    id: 'health',
    label: 'Health',
    icon: Icons.monitor_heart,
    run: (_) {},
  ),
];

List<Override> _providerOverrides() => [
  _domainSeamProvider.overrideWith((ref) => 42),
];

ProviderContainer _container({
  required AppDatabase db,
  List<DomainPack> packs = const [_financePack, _healthPack],
}) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWith((_) async => db),
      ...lifeOsDomainCompositionOverrides(packs: packs),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'composition bundle wires the registry and active device tools',
    () async {
      final db = makeTestDatabase();
      addTearDown(db.close);
      final c = _container(db: db);
      addTearDown(c.dispose);

      await c.read(auth.domainOptInsProvider.future);

      expect(c.read(domainPackRegistryProvider), [_financePack, _healthPack]);
      expect(
        c.read(deviceToolsProvider).map((tool) => tool.name),
        contains('domain_tool'),
      );
      expect(c.read(proposalKindRegistryProvider).map((meta) => meta.kind), [
        'fake_finance',
      ]);

      final applier = await c.read(proposalApplierProvider.future);
      final state = await applier.apply(
        const ReadyProposalPlan(
          proposalId: 'p',
          kind: 'fake_finance',
          summaryZh: 's',
          payload: {},
        ),
      );
      expect(state.appliedTable, 'finance_table');
    },
  );

  test('prompt blocks and command entries preserve active pack order', () {
    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(domainSystemPromptBlocks(const [_financePack, _healthPack]), [
      'Finance block',
      'Health block',
    ]);
    expect(
      domainProposalKinds(const [
        _financePack,
        _healthPack,
      ]).map((meta) => meta.kind),
      ['fake_finance', 'fake_health'],
    );
    expect(
      domainCommandPaletteEntries(const [
        _financePack,
        _healthPack,
      ], l10n).map((entry) => entry.id),
      ['finance', 'health'],
    );
  });

  test('agent registrations attach the owning pack scope', () {
    final registrationsProvider = Provider<List<DomainAgentRegistration>>(
      (ref) => domainAgentRegistrations(ref, const [_financePack]),
    );
    final agentsProvider = Provider<List<Agent>>(
      (ref) => domainAgents(ref, const [_financePack]),
    );
    final c = ProviderContainer();
    addTearDown(c.dispose);

    final registrations = c.read(registrationsProvider);

    expect(registrations, hasLength(1));
    expect(registrations.single.agent.id, 'domain_agent');
    expect(registrations.single.domain, DomainScope.finance);
    expect(c.read(agentsProvider).single.id, 'domain_agent');
  });

  test('tool descriptor lookup follows active domain opt-ins', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final c = _container(db: db);
    addTearDown(c.dispose);

    await c.read(auth.domainOptInsProvider.future);
    var lookup = c.read(toolDescriptorLookupProvider);
    expect(lookup('finance_descriptor'), _financeDescriptor);
    expect(lookup('health_descriptor'), isNull);

    await c
        .read(auth.domainOptInsProvider.notifier)
        .setEnabled(DomainScope.health, true);
    lookup = c.read(toolDescriptorLookupProvider);
    expect(lookup('health_descriptor'), _healthDescriptor);
  });

  test('intent catalog follows active domain opt-ins', () async {
    final db = makeTestDatabase();
    addTearDown(db.close);
    final c = _container(db: db);
    addTearDown(c.dispose);

    await c.read(auth.domainOptInsProvider.future);
    var catalog = c.read(intentCatalogProvider);
    expect(catalog.lookup('fake_finance_intent'), _financeIntent);
    expect(catalog.lookup('fake_health_intent'), isNull);

    await c
        .read(auth.domainOptInsProvider.notifier)
        .setEnabled(DomainScope.health, true);
    catalog = c.read(intentCatalogProvider);
    expect(catalog.lookup('fake_health_intent'), _healthIntent);
  });

  test('composition bundle includes domain provider overrides', () {
    const pack = DomainPack(
      scope: DomainScope.finance,
      providerOverridesBuilder: _providerOverrides,
    );
    final c = ProviderContainer(
      overrides: [
        ...lifeOsDomainCompositionOverrides(packs: [pack]),
      ],
    );
    addTearDown(c.dispose);

    expect(c.read(_domainSeamProvider), 42);
  });

  test('domain bootstraps are contributed by packs', () {
    var memoryBootstrapCount = 0;
    var backgroundBootstrapCount = 0;
    final pack = DomainPack(
      scope: DomainScope.finance,
      memoryBootstrapBuilder: (_) => memoryBootstrapCount++,
      backgroundBootstrapBuilder: (_) => backgroundBootstrapCount++,
    );
    final memoryBootstrapProvider = Provider<void>(
      (ref) => domainMemoryBootstraps(ref, [pack]),
    );
    final backgroundBootstrapProvider = Provider<void>(
      (ref) => domainBackgroundBootstraps(ref, [pack]),
    );
    final c = ProviderContainer();
    addTearDown(c.dispose);

    c.read(memoryBootstrapProvider);
    c.read(backgroundBootstrapProvider);

    expect(memoryBootstrapCount, 1);
    expect(backgroundBootstrapCount, 1);
  });

  test(
    'production four-domain packs derive active tools prompts shells and agents',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = makeTestDatabase();
      addTearDown(db.close);
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWith((_) async => db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...lifeOsDomainCompositionOverrides(),
        ],
      );
      addTearDown(c.dispose);

      await c.read(auth.domainOptInsProvider.future);
      await c
          .read(auth.domainOptInsProvider.notifier)
          .setEnabled(DomainScope.health, true);
      await c
          .read(auth.domainOptInsProvider.notifier)
          .setEnabled(DomainScope.knowledge, true);
      await c
          .read(auth.domainOptInsProvider.notifier)
          .setEnabled(DomainScope.execution, true);

      expect(c.read(domainPackRegistryProvider), kAllDomainPacks);
      expect(kFinancePack.backgroundBootstrapBuilder, isNotNull);
      expect(c.read(activeDomainPacksProvider).map((pack) => pack.scope), [
        DomainScope.finance,
        DomainScope.health,
        DomainScope.knowledge,
        DomainScope.execution,
      ]);

      expect(
        c.read(deviceToolsProvider).map((tool) => tool.name),
        containsAll(<String>['propose_action', 'summarize_execution_progress']),
      );
      expect(c.read(systemPromptBlocksProvider), [
        kFinancePack.systemPromptBlock,
        kHealthPack.systemPromptBlock,
        kKnowledgePack.systemPromptBlock,
        kExecutionPack.systemPromptBlock,
      ]);
      expect(c.read(activeDomainShellsProvider).map((shell) => shell.scope), [
        DomainScope.finance,
        DomainScope.health,
        DomainScope.knowledge,
        DomainScope.execution,
      ]);
      expect(
        c.read(agentRegistryProvider).map((agent) => agent.id),
        containsAll(<String>[
          'morning_briefing',
          'knowledge_review',
          'execution_review',
        ]),
      );
    },
  );
}

class _FakeTool implements DeviceTool {
  const _FakeTool(this.name);

  @override
  final String name;

  @override
  String get description => 'Fake tool';

  @override
  Map<String, Object?> get inputSchema => const <String, Object?>{};

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    return const <String, Object?>{'ok': true};
  }
}

class _FakeProposalApplier implements ProposalApplier {
  const _FakeProposalApplier(this.table);

  final String table;

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedTable: table,
    );
  }

  @override
  Future<void> undo(ProposalApplyState state) async {}
}

class _FakeAgent implements Agent {
  const _FakeAgent(this.id);

  @override
  final String id;

  @override
  String get name => 'Fake agent';

  @override
  AgentSchedule get schedule =>
      const AgentSchedule(interval: Duration(hours: 1));

  @override
  Future<AgentRunResult> run(AgentContext ctx) async {
    return AgentRunResult.skipped(
      agentId: id,
      startedAt: ctx.now,
      finishedAt: ctx.now,
      reason: 'test',
    );
  }
}
