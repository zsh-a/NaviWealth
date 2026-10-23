import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime/proposals/agent_runtime_proposal_bridge.dart';
import 'package:naviwealth/app/agent_runtime/runner/agent_runtime_runner.dart';
import 'package:naviwealth/app/agent_runtime/runner/agent_runtime_step_runner.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/composition/proposal_applier.dart';
import 'package:naviwealth/core/ai/composition/proposal_apply_state.dart';
import 'package:naviwealth/core/ai/composition/proposal_plan.dart';
import 'package:naviwealth/core/ai/contracts/ai_domain.dart';
import 'package:naviwealth/core/ai/contracts/ai_privacy_settings.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_connectivity.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';
import 'package:naviwealth/core/ai/llm_credentials/providers.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_session.dart';
import 'package:naviwealth/core/persistence/providers.dart';
import 'package:naviwealth/core/security/in_memory_key_store.dart';
import 'package:naviwealth/core/security/secure_key_store.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/settings/ui/ai/ai_llm_credentials_page.dart';
import 'package:naviwealth/features/settings/ui/ai/ai_provider_privacy_fields.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/agent_runtime_native_bridge_test_harness.dart';
import '../../../support/test_app_theme.dart';

late SharedPreferences _preferences;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    _preferences = await SharedPreferences.getInstance();
  });

  testWidgets(
    'native setup discloses provider data use only when configuring',
    (tester) async {
      final probe = _RecordingProbe();
      await tester.pumpWidget(
        _wrap(
          credentials: const LlmCredentials(),
          runtimeRunner: null,
          probe: probe,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AiProviderPrivacyFields), findsNothing);
      await tester.tap(find.text('Add provider'));
      await tester.pumpAndSettle();
      expect(find.byType(AiProviderPrivacyFields), findsOneWidget);
      final fields = tester.widget<AiProviderPrivacyFields>(
        find.byType(AiProviderPrivacyFields),
      );
      expect(fields.allowDocumentRecognition, isFalse);
      expect(find.byType(Dialog), findsNothing);
      expect(probe.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unsupported platforms expose no provider setup or permission', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        credentials: const LlmCredentials(),
        runtimeRunner: null,
        supported: false,
      ),
    );
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.aiLlmUnsupportedTitle), findsOneWidget);
    expect(find.text(l10n.aiLlmAddProvider), findsNothing);
    expect(find.byType(AiProviderPrivacyFields), findsNothing);
  });

  testWidgets(
    'failed profile save retains input and cancel guards unsaved changes',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store = _UnavailableKeyStore();
      final probe = _RecordingProbe();
      await tester.pumpWidget(
        _wrap(
          credentials: const LlmCredentials(),
          runtimeRunner: null,
          keyStore: store,
          probe: probe,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add provider'));
      await tester.pumpAndSettle();
      final privacyFields = tester.widget<AiProviderPrivacyFields>(
        find.byType(AiProviderPrivacyFields),
      );
      privacyFields.onChanged(true);
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('llm-profile-name')));
      await tester.enterText(
        find.byKey(const Key('llm-profile-name')),
        'My profile',
      );
      await tester.ensureVisible(find.byKey(const Key('llm-profile-key')));
      await tester.enterText(
        find.byKey(const Key('llm-profile-key')),
        'test-key',
      );
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('My profile'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const Key('llm-profile-key')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'test-key',
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text(l10n.commonSaveFailed), findsWidgets);
      expect(find.text(l10n.aiLlmSaved), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AiLlmCredentialsPage)),
      );
      expect(
        container.read(aiPrivacySettingsProvider).allowDocumentRecognition,
        isFalse,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.unsavedChangesTitle), findsOneWidget);
      await tester.tap(find.text(l10n.unsavedChangesKeepEditing));
      await tester.pumpAndSettle();
      expect(find.text('My profile'), findsOneWidget);
      store.fail = false;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.aiLlmSaved), findsWidgets);
      expect(
        container.read(aiPrivacySettingsProvider).allowDocumentRecognition,
        isTrue,
      );
      expect(find.byType(EditableText), findsNothing);
      expect(probe.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shows runtime check unavailable without active profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(credentials: const LlmCredentials(), runtimeRunner: null),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI service check'), findsOneWidget);
    expect(
      find.text(
        'Save and activate a model provider before checking the AI service.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('runs active profile through FRB profile turn runner surface', (
    tester,
  ) async {
    final native = _SettingsRuntimeBridge();
    await tester.pumpWidget(
      _wrap(
        credentials: const LlmCredentials(
          profiles: <LlmProfile>[
            LlmProfile(
              id: 'profile_1',
              name: 'Runtime profile',
              provider: LlmProvider.openai,
              apiKey: 'sk-test',
              model: 'gpt-test',
            ),
          ],
          activeId: 'profile_1',
        ),
        runtimeRunner: _runner(native),
      ),
    );
    await tester.pumpAndSettle();

    expect(native.llmRequests, isEmpty);
    await tester.ensureVisible(find.text('Start check'));
    await tester.tap(find.text('Start check'));
    await tester.pumpAndSettle();

    expect(native.llmRequests, hasLength(1));
    expect(native.startRequests.single.agentId, 'settings_llm_runtime_check');
    expect(find.text('On-device check: completed'), findsOneWidget);
    expect(find.text('runtime reachable'), findsOneWidget);
  });

  testWidgets('applies ready proposal from FRB runtime result after confirm', (
    tester,
  ) async {
    final native = _SettingsRuntimeBridge(
      proposal: const <String, Object?>{
        'proposal_id': 'proposal_1',
        'kind': 'runtime_test',
        'status': 'ready',
        'summary_zh': 'Record runtime proposal',
        'payload': <String, Object?>{'id': 'entity_1'},
        'warnings': <String>['Generated by runtime check'],
      },
    );
    final applier = _RecordingProposalApplier();
    await tester.pumpWidget(
      _wrap(
        credentials: const LlmCredentials(
          profiles: <LlmProfile>[
            LlmProfile(
              id: 'profile_1',
              name: 'Runtime profile',
              provider: LlmProvider.openai,
              apiKey: 'sk-test',
              model: 'gpt-test',
            ),
          ],
          activeId: 'profile_1',
        ),
        runtimeRunner: _runner(native),
        proposalApplier: applier,
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Start check'));
    await tester.tap(find.text('Start check'));
    await tester.pumpAndSettle();

    expect(find.text('Record runtime proposal'), findsOneWidget);
    expect(find.text('Warning: Generated by runtime check'), findsOneWidget);

    await tester.ensureVisible(find.text('Apply proposal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply proposal'));
    await tester.pumpAndSettle();
    expect(find.text('Apply this proposal?'), findsOneWidget);

    await tester.tap(find.text('Apply proposal').last);
    await tester.pumpAndSettle();

    expect(applier.applied.single.proposalId, 'proposal_1');
    expect(find.text('Proposal apply: applied'), findsOneWidget);
  });
}

Widget _wrap({
  required LlmCredentials credentials,
  required AgentRuntimeProfileTurnRunner? runtimeRunner,
  ProposalApplier? proposalApplier,
  SecureKeyStore? keyStore,
  LlmConnectivityProbe? probe,
  bool supported = true,
}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(_preferences),
      deviceLlmPlatformSupportedProvider.overrideWithValue(supported),
      if (keyStore == null)
        llmCredentialsProvider.overrideWith(
          () => _FakeCredentialsNotifier(credentials),
        ),
      if (keyStore != null) secureKeyStoreProvider.overrideWithValue(keyStore),
      if (probe != null) llmConnectivityProbeProvider.overrideWithValue(probe),
      agentRuntimeProfileTurnRunnerProvider.overrideWithValue(runtimeRunner),
      if (proposalApplier != null)
        agentRuntimeProposalBridgeProvider.overrideWith((ref) async {
          return AgentRuntimeProposalBridge(applier: proposalApplier);
        }),
    ],
    child: MaterialApp(
      builder: (context, child) => buildTestAppTheme(
        context,
        AppMessenger.init(child: child ?? const SizedBox.shrink()),
      ),
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AiLlmCredentialsPage(),
    ),
  );
}

AgentRuntimeProfileTurnRunner _runner(_SettingsRuntimeBridge native) {
  return AgentRuntimeProfileTurnRunner(
    catalog: AgentRuntimeCatalog(
      generatedAt: DateTime.utc(2026, 6, 29, 10),
      activeDomains: const <DomainScope>[DomainScope.finance],
      agents: const <AgentRuntimeAgentSpec>[],
      tools: const <AgentRuntimeToolSpec>[],
      proposalKinds: const <AgentRuntimeProposalKindSpec>[],
      promptBlocks: const <AgentRuntimePromptBlockSpec>[],
    ),
    llmBridge: AgentRuntimeLlmBridge(
      bridge: native,
      profile: const LlmProfile(
        id: 'profile_1',
        name: 'Runtime profile',
        provider: LlmProvider.openai,
        apiKey: 'sk-test',
        model: 'gpt-test',
      ),
    ),
    stepRunner: AgentRuntimeNativeStepRunner(
      bridge: native,
      toolHost: AgentRuntimeToolHost(dispatcher: const _NoopDispatcher()),
    ),
  );
}

class _FakeCredentialsNotifier extends LlmCredentialsNotifier {
  _FakeCredentialsNotifier(this._credentials);

  final LlmCredentials _credentials;

  @override
  Future<LlmCredentials?> fetch() async => _credentials;
}

class _SettingsRuntimeBridge extends FakeAgentRuntimeNativeBridge {
  _SettingsRuntimeBridge({this.proposal})
    : super(
        profileResponse: const <String, Object?>{
          'protocol_version': 'agent.v1',
          'provider': 'openai',
          'model': 'gpt-test',
          'content': 'runtime reachable',
          'finish_reason': 'stop',
          'metadata': <String, Object?>{'profile': true},
        },
      );

  final Map<String, Object?>? proposal;
  final startRequests = <_StartRequest>[];

  @override
  Future<Map<String, Object?>> startProfileTurnSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  }) async {
    final response = await completeProfileLlm(request: llmRequest);
    final initialStep = _initialStep(
      request: const <String, Object?>{},
      agentId: agentId,
    );
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'llm_response': response,
      'snapshot': _snapshot(
        initialStep,
        maxEffectSteps: maxEffectSteps,
        maxSubagentDepth: maxSubagentDepth,
      ),
    };
  }

  @override
  Future<Map<String, Object?>> startRunSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    required int maxEffectSteps,
    required int maxSubagentDepth,
  }) async {
    return _snapshot(
      _initialStep(request: request, agentId: agentId),
      maxEffectSteps: maxEffectSteps,
      maxSubagentDepth: maxSubagentDepth,
    );
  }

  Map<String, Object?> _snapshot(
    Map<String, Object?> step, {
    required int maxEffectSteps,
    required int maxSubagentDepth,
  }) => <String, Object?>{
    'protocol_version': 'agent.v1',
    'snapshot_version': 1,
    'step': step,
    'limits': <String, Object?>{
      'max_effect_steps': maxEffectSteps,
      'max_subagent_depth': maxSubagentDepth,
    },
    'progress': const <String, Object?>{
      'dispatched_effect_count': 0,
      'subagent_depth': 0,
      'effect_budget_exhausted': false,
      'subagent_depth_exceeded': false,
    },
  };

  Map<String, Object?> _initialStep({
    required Map<String, Object?> request,
    required String agentId,
  }) {
    startRequests.add(_StartRequest(request, agentId));
    final proposal = this.proposal;
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'agent_id': agentId,
      'status': 'completed',
      'output': proposal == null
          ? request['input']
          : <String, Object?>{'proposal': proposal},
    };
  }
}

class _RecordingProposalApplier implements ProposalApplier {
  final applied = <ReadyProposalPlan>[];

  @override
  Future<ProposalApplyState> apply(ReadyProposalPlan plan) async {
    applied.add(plan);
    return ProposalApplyState(
      status: ProposalApplyStatus.applied,
      appliedEntityId: plan.payload['id']?.toString(),
      appliedTable: 'runtime_test',
      appliedAt: DateTime.utc(2026, 6, 29, 11),
      shortLabel: plan.summaryZh,
    );
  }

  @override
  Future<void> undo(ProposalApplyState state) async {}
}

class _NoopDispatcher implements DeviceToolDispatcher {
  const _NoopDispatcher();

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    return const <String, Object?>{'ok': true};
  }
}

class _StartRequest {
  const _StartRequest(this.request, this.agentId);

  final Map<String, Object?> request;
  final String agentId;
}

class _UnavailableKeyStore extends InMemoryKeyStore {
  bool fail = true;
  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('Secure storage unavailable');
    await super.write(key, value);
  }
}

class _RecordingProbe implements LlmConnectivityProbe {
  int calls = 0;

  @override
  Future<LlmProbeResult> probe(
    LlmProfile profile, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    calls++;
    return const LlmProbeResult(LlmProbeStatus.ok, 'Connected');
  }
}
