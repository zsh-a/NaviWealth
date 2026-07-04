import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';

class FakeAgentRuntimeNativeBridge implements AgentRuntimeNativeBridge {
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
  ) async {
    return catalog;
  }

  @override
  Future<Map<String, Object?>> validateRunRequest(
    Map<String, Object?> request,
  ) async {
    return request;
  }

  @override
  Future<Map<String, Object?>> validateTrace(Map<String, Object?> trace) async {
    return trace;
  }

  @override
  Future<Map<String, Object?>> validateToolSpec(
    Map<String, Object?> tool,
  ) async {
    return tool;
  }

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
  ) async {
    return response;
  }

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
  Future<Map<String, Object?>> startProfileTurnStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
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
      'step': initialStep,
    };
  }

  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    runRequests.add(
      AgentRuntimeRunStartRequest(
        catalog: catalog,
        request: request,
        agentId: agentId,
      ),
    );
    final input = request['input'];
    if (input is Map<String, Object?>) {
      final effect = input['effect'];
      if (effect is Map<String, Object?>) {
        return <String, Object?>{
          'protocol_version': kAgentRuntimeProtocolVersion,
          'run_id': 'run_1',
          'agent_id': agentId,
          'status': 'effect_requested',
          'effect': effect,
        };
      }
    }
    return <String, Object?>{
      'protocol_version': kAgentRuntimeProtocolVersion,
      'run_id': 'run_1',
      'agent_id': agentId,
      'status': 'completed',
      'output': input,
    };
  }

  @override
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> effectResponse,
    required String agentId,
  }) async {
    continuations.add(
      AgentRuntimeRunContinuation(
        previousStep: previousStep,
        effectResponse: effectResponse,
      ),
    );
    return <String, Object?>{
      'protocol_version': kAgentRuntimeProtocolVersion,
      'run_id': previousStep['run_id'],
      'agent_id': agentId,
      'status': effectResponse['error'] == null ? 'completed' : 'failed',
      'output': <String, Object?>{
        'effect': previousStep['effect'],
        'effect_result': effectResponse['result'],
        'effect_response': effectResponse,
      },
    };
  }

  Map<String, Object?> _initialStepForLlmResponse(
    Map<String, Object?> llmResponse,
    String agentId,
  ) {
    final metadata = llmResponse['metadata'];
    if (metadata is Map<String, Object?>) {
      final effects = metadata['effects'];
      final effect = effects is List && effects.isNotEmpty
          ? effects.first
          : null;
      if (effect is Map<String, Object?>) {
        return <String, Object?>{
          'protocol_version': kAgentRuntimeProtocolVersion,
          'run_id': 'run_1',
          'agent_id': agentId,
          'status': 'effect_requested',
          'effect': effect,
        };
      }
    }
    return <String, Object?>{
      'protocol_version': kAgentRuntimeProtocolVersion,
      'run_id': 'run_1',
      'agent_id': agentId,
      'status': 'completed',
      'output': <String, Object?>{
        'content': llmResponse['content'],
        'llm_response': llmResponse,
      },
    };
  }
}

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
