import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';

class FakeAgentRuntimeNativeBridge implements AgentRuntimeHostBridge {
  FakeAgentRuntimeNativeBridge({
    Map<String, Object?>? profileResponse,
    this.profileError,
  }) : _profileResponse = profileResponse;

  final Map<String, Object?>? _profileResponse;
  final Object? profileError;
  final llmRequests = <Map<String, Object?>>[];
  final profileTurnRequests = <AgentRuntimeProfileTurnStartRequest>[];
  final runRequests = <AgentRuntimeRunStartRequest>[];
  final continuations = <AgentRuntimeRunContinuation>[];
  var completeProfileCalls = 0;
  Map<String, Object?> lastRequest = const <String, Object?>{};

  int get completeCalls => completeProfileCalls;

  @override
  Future<String> protocolVersion() async => kAgentRuntimeProtocolVersion;

  @override
  Future<String> catalogVersion() async => kAgentRuntimeCatalogVersion;

  @override
  Future<Map<String, Object?>> catalogSummary(
    Map<String, Object?> catalog,
  ) async => catalog;

  @override
  Future<Map<String, Object?>> validateRunRequest(
    Map<String, Object?> request,
  ) async => request;

  @override
  Future<Map<String, Object?>> validateTrace(
    Map<String, Object?> trace,
  ) async => trace;

  @override
  Future<Map<String, Object?>> validateToolSpec(
    Map<String, Object?> tool,
  ) async => tool;

  @override
  Future<Map<String, Object?>> validateLlmRequest(
    Map<String, Object?> request,
  ) async {
    llmRequests.add(request);
    lastRequest = request;
    return request;
  }

  @override
  Future<Map<String, Object?>> validateLlmResponse(
    Map<String, Object?> response,
  ) async => response;

  @override
  Future<Map<String, Object?>> completeMockLlm({
    required Map<String, Object?> request,
    required String responseText,
  }) async {
    llmRequests.add(request);
    lastRequest = request;
    return <String, Object?>{
      'protocol_version': kAgentRuntimeProtocolVersion,
      'provider': request['provider'],
      'model': request['model'],
      'content': responseText,
      'finish_reason': 'stop',
      'metadata': <String, Object?>{'mock': true},
    };
  }

  @override
  Future<Map<String, Object?>> completeProfileLlm({
    required Map<String, Object?> request,
  }) async {
    completeProfileCalls += 1;
    llmRequests.add(request);
    lastRequest = request;
    final error = profileError;
    if (error != null) throw error;
    return _profileResponse ??
        <String, Object?>{
          'protocol_version': kAgentRuntimeProtocolVersion,
          'provider': request['provider'],
          'model': request['model'],
          'content': 'profile response',
          'finish_reason': 'stop',
          'metadata': <String, Object?>{'profile': true},
        };
  }

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
    final initialStep = _initialStepForLlmResponse(response, agentId);
    profileTurnRequests.add(
      AgentRuntimeProfileTurnStartRequest(
        catalog: catalog,
        llmRequest: llmRequest,
        agentId: agentId,
        runMetadata: runMetadata,
        initialStep: initialStep,
      ),
    );
    return <String, Object?>{
      'protocol_version': kAgentRuntimeProtocolVersion,
      'llm_response': response,
      'snapshot': _snapshot(
        step: initialStep,
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
    runRequests.add(
      AgentRuntimeRunStartRequest(
        catalog: catalog,
        request: request,
        agentId: agentId,
      ),
    );
    final input = request['input'];
    final effect = input is Map<String, Object?> ? input['effect'] : null;
    final step = effect is Map<String, Object?>
        ? <String, Object?>{
            'protocol_version': kAgentRuntimeProtocolVersion,
            'run_id': 'run_1',
            'agent_id': agentId,
            'step_index': 0,
            'status': 'effect_requested',
            'effect': effect,
          }
        : <String, Object?>{
            'protocol_version': kAgentRuntimeProtocolVersion,
            'run_id': 'run_1',
            'agent_id': agentId,
            'step_index': 0,
            'status': 'completed',
            'output': input,
          };
    return _snapshot(
      step: step,
      maxEffectSteps: maxEffectSteps,
      maxSubagentDepth: maxSubagentDepth,
    );
  }

  @override
  Future<Map<String, Object?>> continueRunSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> snapshot,
    required Map<String, Object?> effectResponse,
    required String agentId,
  }) async {
    final previousStep = Map<String, Object?>.from(snapshot['step']! as Map);
    continuations.add(
      AgentRuntimeRunContinuation(
        previousStep: previousStep,
        effectResponse: effectResponse,
      ),
    );
    final limits = Map<String, Object?>.from(snapshot['limits']! as Map);
    final progress = Map<String, Object?>.from(snapshot['progress']! as Map);
    final dispatched = (progress['dispatched_effect_count']! as int) + 1;
    return _snapshot(
      step: <String, Object?>{
        'protocol_version': kAgentRuntimeProtocolVersion,
        'run_id': previousStep['run_id'],
        'agent_id': agentId,
        'step_index': dispatched,
        'status': 'completed',
        'output': <String, Object?>{
          'effect': previousStep['effect'],
          'effect_result': effectResponse['result'],
          'effect_response': effectResponse,
        },
      },
      maxEffectSteps: limits['max_effect_steps']! as int,
      maxSubagentDepth: limits['max_subagent_depth']! as int,
      dispatchedEffectCount: dispatched,
    );
  }

  @override
  Future<Map<String, Object?>> cancelRunSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> snapshot,
    required String agentId,
    required String reason,
  }) async {
    final step = Map<String, Object?>.from(snapshot['step']! as Map);
    return <String, Object?>{
      ...snapshot,
      'step': <String, Object?>{
        ...step,
        'status': 'cancelled',
        'effect': null,
        'error': <String, Object?>{'code': 'user_cancel', 'message': reason},
      },
    };
  }

  @override
  Future<Map<String, Object?>> startRequestedSubagentSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> parentSnapshot,
  }) => throw UnsupportedError('subagent not configured by this fake');

  @override
  Future<Map<String, Object?>> resumeParentFromSubagentSnapshot({
    required Map<String, Object?> catalog,
    required Map<String, Object?> parentSnapshot,
    required Map<String, Object?> childSnapshot,
  }) => throw UnsupportedError('subagent not configured by this fake');

  Map<String, Object?> _initialStepForLlmResponse(
    Map<String, Object?> llmResponse,
    String agentId,
  ) {
    final metadata = llmResponse['metadata'];
    final effects = metadata is Map<String, Object?>
        ? metadata['effects']
        : null;
    final effect = effects is List && effects.isNotEmpty ? effects.first : null;
    if (effect is Map<String, Object?>) {
      return <String, Object?>{
        'protocol_version': kAgentRuntimeProtocolVersion,
        'run_id': 'run_1',
        'agent_id': agentId,
        'step_index': 0,
        'status': 'effect_requested',
        'effect': effect,
      };
    }
    return <String, Object?>{
      'protocol_version': kAgentRuntimeProtocolVersion,
      'run_id': 'run_1',
      'agent_id': agentId,
      'step_index': 0,
      'status': 'completed',
      'output': <String, Object?>{
        'content': llmResponse['content'],
        'llm_response': llmResponse,
      },
    };
  }
}

Map<String, Object?> _snapshot({
  required Map<String, Object?> step,
  required int maxEffectSteps,
  required int maxSubagentDepth,
  int dispatchedEffectCount = 0,
}) => <String, Object?>{
  'protocol_version': kAgentRuntimeProtocolVersion,
  'snapshot_version': 1,
  'step': step,
  'limits': <String, Object?>{
    'max_effect_steps': maxEffectSteps,
    'max_subagent_depth': maxSubagentDepth,
  },
  'progress': <String, Object?>{
    'dispatched_effect_count': dispatchedEffectCount,
    'subagent_depth': 0,
    'effect_budget_exhausted': false,
    'subagent_depth_exceeded': false,
  },
};

class AgentRuntimeProfileTurnStartRequest {
  const AgentRuntimeProfileTurnStartRequest({
    required this.catalog,
    required this.llmRequest,
    required this.agentId,
    required this.runMetadata,
    required this.initialStep,
  });

  final Map<String, Object?> catalog;
  final Map<String, Object?> llmRequest;
  final String agentId;
  final Map<String, Object?> runMetadata;
  final Map<String, Object?> initialStep;
}

class AgentRuntimeRunStartRequest {
  const AgentRuntimeRunStartRequest({
    required this.catalog,
    required this.request,
    required this.agentId,
  });

  final Map<String, Object?> catalog;
  final Map<String, Object?> request;
  final String agentId;
}

class AgentRuntimeRunContinuation {
  const AgentRuntimeRunContinuation({
    required this.previousStep,
    required this.effectResponse,
  });

  final Map<String, Object?> previousStep;
  final Map<String, Object?> effectResponse;
}
