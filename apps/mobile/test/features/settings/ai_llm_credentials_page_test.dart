import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/app/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime_runner.dart';
import 'package:naviwealth/app/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';
import 'package:naviwealth/core/ai/llm_credentials/providers.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/design_system/design_system.dart';
import 'package:naviwealth/features/settings/ui/ai_llm_credentials_page.dart';
import 'package:naviwealth/l10n/gen/app_localizations.dart';

void main() {
  testWidgets('shows runtime check unavailable without active profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(credentials: const LlmCredentials(), runtimeRunner: null),
    );
    await tester.pumpAndSettle();

    expect(find.text('Agent runtime'), findsOneWidget);
    expect(
      find.text(
        'Save and activate a provider profile before checking the agent runtime.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('runs active profile through FRB profile turn runner surface', (
    tester,
  ) async {
    final native = _FakeNativeBridge();
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

    await tester.ensureVisible(find.text('Check runtime'));
    await tester.tap(find.text('Check runtime'));
    await tester.pumpAndSettle();

    expect(native.llmRequests, hasLength(1));
    expect(native.startRequests.single.agentId, 'settings_llm_runtime_check');
    expect(find.text('Native step: completed'), findsOneWidget);
    expect(find.text('runtime reachable'), findsOneWidget);
  });
}

Widget _wrap({
  required LlmCredentials credentials,
  required AgentRuntimeProfileTurnRunner? runtimeRunner,
}) {
  return ProviderScope(
    overrides: [
      deviceLlmPlatformSupportedProvider.overrideWithValue(true),
      llmCredentialsProvider.overrideWith(
        () => _FakeCredentialsNotifier(credentials),
      ),
      agentRuntimeProfileTurnRunnerProvider.overrideWithValue(runtimeRunner),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const AiLlmCredentialsPage(),
    ),
  );
}

AgentRuntimeProfileTurnRunner _runner(_FakeNativeBridge native) {
  return AgentRuntimeProfileTurnRunner(
    catalog: AgentRuntimeCatalog(
      generatedAt: DateTime.utc(2026, 6, 29, 10),
      activeDomains: const <String>['finance'],
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

class _FakeNativeBridge implements AgentRuntimeNativeBridge {
  final llmRequests = <Map<String, Object?>>[];
  final startRequests = <_StartRequest>[];

  @override
  Future<String> protocolVersion() async => 'agent.v1';

  @override
  Future<String> catalogVersion() async => 'agent_catalog.v1';

  @override
  Future<Map<String, Object?>> catalogSummary(
    Map<String, Object?> catalog,
  ) async {
    return catalog;
  }

  @override
  Future<Map<String, Object?>> completeMockLlm({
    required Map<String, Object?> request,
    required String responseText,
  }) async {
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'provider': request['provider'],
      'model': request['model'],
      'content': responseText,
      'finish_reason': 'stop',
    };
  }

  @override
  Future<Map<String, Object?>> completeProfileLlm({
    required Map<String, Object?> request,
  }) async {
    llmRequests.add(request);
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'provider': request['provider'],
      'model': request['model'],
      'content': 'runtime reachable',
      'finish_reason': 'stop',
      'metadata': <String, Object?>{'profile': true},
    };
  }

  @override
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> toolResponse,
    required String agentId,
  }) async {
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'agent_id': agentId,
      'status': 'completed',
    };
  }

  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    startRequests.add(_StartRequest(request, agentId));
    return <String, Object?>{
      'protocol_version': 'agent.v1',
      'agent_id': agentId,
      'status': 'completed',
      'output': request['input'],
    };
  }

  @override
  Future<Map<String, Object?>> validateLlmRequest(
    Map<String, Object?> request,
  ) async {
    return request;
  }

  @override
  Future<Map<String, Object?>> validateLlmResponse(
    Map<String, Object?> response,
  ) async {
    return response;
  }

  @override
  Future<Map<String, Object?>> validateRunRequest(
    Map<String, Object?> request,
  ) async {
    return request;
  }

  @override
  Future<Map<String, Object?>> validateToolSpec(
    Map<String, Object?> tool,
  ) async {
    return tool;
  }

  @override
  Future<Map<String, Object?>> validateTrace(Map<String, Object?> trace) async {
    return trace;
  }
}

class _NoopDispatcher implements DeviceToolDispatcher {
  const _NoopDispatcher();

  @override
  Future<Object?> dispatch(
    DeviceSession session,
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
