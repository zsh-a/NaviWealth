/// App-level bridge for the native Rust agent-runtime contract helpers.
///
/// Generated FRB bindings expose primitive JSON string functions. This file is
/// the stable application seam: callers pass Dart maps and receive Dart maps,
/// while tests can replace the native bridge without loading the dylib.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/src/rust/api/agent_runtime.dart' as rust;

import '../core/ai/local/embedding/rust_gemma_embedder.dart';
import '../core/config/providers.dart';
import 'agent_runtime_catalog.dart';
import 'agent_runtime_tool_host.dart';

typedef LifeosNativeRuntimeInitializer =
    Future<void> Function({String? libraryPath});

final agentRuntimeNativeApiProvider = Provider<AgentRuntimeNativeApi>(
  (ref) => const FrbAgentRuntimeNativeApi(),
);

final agentRuntimeNativeBridgeProvider = Provider<AgentRuntimeNativeBridge>((
  ref,
) {
  final config = ref.watch(appConfigProvider);
  return FfiAgentRuntimeNativeBridge(
    api: ref.watch(agentRuntimeNativeApiProvider),
    initRuntime: initLifeosNativeRuntime,
    libraryPath: config.rustEmbedderLibraryPath.isEmpty
        ? null
        : config.rustEmbedderLibraryPath,
  );
});

final agentRuntimeNativeCatalogSummaryProvider =
    FutureProvider<Map<String, Object?>>((ref) async {
      final catalog = ref.watch(agentRuntimeCatalogProvider);
      final bridge = ref.watch(agentRuntimeNativeBridgeProvider);
      return bridge.catalogSummary(catalog.toJson());
    });

final agentRuntimeNativeStepRunnerProvider =
    Provider<AgentRuntimeNativeStepRunner>((ref) {
      return AgentRuntimeNativeStepRunner(
        bridge: ref.watch(agentRuntimeNativeBridgeProvider),
        toolHost: ref.watch(agentRuntimeToolHostProvider),
      );
    });

abstract interface class AgentRuntimeNativeApi {
  Future<String> protocolVersion();
  Future<String> catalogVersion();
  Future<String> catalogSummary({required String catalogJson});
  Future<String> validateRunRequest({required String requestJson});
  Future<String> validateTrace({required String traceJson});
  Future<String> validateToolSpec({required String toolJson});
  Future<String> validateLlmRequest({required String requestJson});
  Future<String> validateLlmResponse({required String responseJson});
  Future<String> completeMockLlm({
    required String requestJson,
    required String responseText,
  });
  Future<String> completeProfileLlm({required String requestJson});
  Future<String> startProfileTurnStep({
    required String catalogJson,
    required String llmRequestJson,
    required String agentId,
    required String runMetadataJson,
  });
  Future<String> startRunStep({
    required String catalogJson,
    required String requestJson,
    required String agentId,
  });
  Future<String> continueRunStep({
    required String catalogJson,
    required String previousStepJson,
    required String toolResponseJson,
    required String agentId,
  });
}

class FrbAgentRuntimeNativeApi implements AgentRuntimeNativeApi {
  const FrbAgentRuntimeNativeApi();

  @override
  Future<String> protocolVersion() => rust.agentRuntimeProtocolVersion();

  @override
  Future<String> catalogVersion() => rust.agentRuntimeCatalogVersion();

  @override
  Future<String> catalogSummary({required String catalogJson}) {
    return rust.agentRuntimeCatalogSummary(catalogJson: catalogJson);
  }

  @override
  Future<String> validateRunRequest({required String requestJson}) {
    return rust.agentRuntimeValidateRunRequest(requestJson: requestJson);
  }

  @override
  Future<String> validateTrace({required String traceJson}) {
    return rust.agentRuntimeValidateTrace(traceJson: traceJson);
  }

  @override
  Future<String> validateToolSpec({required String toolJson}) {
    return rust.agentRuntimeValidateToolSpec(toolJson: toolJson);
  }

  @override
  Future<String> validateLlmRequest({required String requestJson}) {
    return rust.agentRuntimeValidateLlmRequest(requestJson: requestJson);
  }

  @override
  Future<String> validateLlmResponse({required String responseJson}) {
    return rust.agentRuntimeValidateLlmResponse(responseJson: responseJson);
  }

  @override
  Future<String> completeMockLlm({
    required String requestJson,
    required String responseText,
  }) {
    return rust.agentRuntimeCompleteMockLlm(
      requestJson: requestJson,
      responseText: responseText,
    );
  }

  @override
  Future<String> completeProfileLlm({required String requestJson}) {
    return rust.agentRuntimeCompleteProfileLlm(requestJson: requestJson);
  }

  @override
  Future<String> startProfileTurnStep({
    required String catalogJson,
    required String llmRequestJson,
    required String agentId,
    required String runMetadataJson,
  }) {
    return rust.agentRuntimeStartProfileTurnStep(
      catalogJson: catalogJson,
      llmRequestJson: llmRequestJson,
      agentId: agentId,
      runMetadataJson: runMetadataJson,
    );
  }

  @override
  Future<String> startRunStep({
    required String catalogJson,
    required String requestJson,
    required String agentId,
  }) {
    return rust.agentRuntimeStartRunStep(
      catalogJson: catalogJson,
      requestJson: requestJson,
      agentId: agentId,
    );
  }

  @override
  Future<String> continueRunStep({
    required String catalogJson,
    required String previousStepJson,
    required String toolResponseJson,
    required String agentId,
  }) {
    return rust.agentRuntimeContinueRunStep(
      catalogJson: catalogJson,
      previousStepJson: previousStepJson,
      toolResponseJson: toolResponseJson,
      agentId: agentId,
    );
  }
}

abstract interface class AgentRuntimeNativeBridge {
  Future<String> protocolVersion();
  Future<String> catalogVersion();
  Future<Map<String, Object?>> catalogSummary(Map<String, Object?> catalog);
  Future<Map<String, Object?>> validateRunRequest(Map<String, Object?> request);
  Future<Map<String, Object?>> validateTrace(Map<String, Object?> trace);
  Future<Map<String, Object?>> validateToolSpec(Map<String, Object?> tool);
  Future<Map<String, Object?>> validateLlmRequest(Map<String, Object?> request);
  Future<Map<String, Object?>> validateLlmResponse(
    Map<String, Object?> response,
  );
  Future<Map<String, Object?>> completeMockLlm({
    required Map<String, Object?> request,
    required String responseText,
  });
  Future<Map<String, Object?>> completeProfileLlm({
    required Map<String, Object?> request,
  });
  Future<Map<String, Object?>> startProfileTurnStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
  });
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  });
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> toolResponse,
    required String agentId,
  });
}

class FfiAgentRuntimeNativeBridge implements AgentRuntimeNativeBridge {
  FfiAgentRuntimeNativeBridge({
    required AgentRuntimeNativeApi api,
    required LifeosNativeRuntimeInitializer initRuntime,
    String? libraryPath,
  }) : _api = api,
       _initRuntime = initRuntime,
       _libraryPath = libraryPath;

  final AgentRuntimeNativeApi _api;
  final LifeosNativeRuntimeInitializer _initRuntime;
  final String? _libraryPath;

  Future<void>? _initFuture;

  @override
  Future<String> protocolVersion() async {
    await _ensureInitialized();
    return _api.protocolVersion();
  }

  @override
  Future<String> catalogVersion() async {
    await _ensureInitialized();
    return _api.catalogVersion();
  }

  @override
  Future<Map<String, Object?>> catalogSummary(
    Map<String, Object?> catalog,
  ) async {
    await _ensureInitialized();
    final json = await _api.catalogSummary(catalogJson: jsonEncode(catalog));
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> validateRunRequest(
    Map<String, Object?> request,
  ) async {
    await _ensureInitialized();
    final json = await _api.validateRunRequest(
      requestJson: jsonEncode(request),
    );
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> validateTrace(Map<String, Object?> trace) async {
    await _ensureInitialized();
    final json = await _api.validateTrace(traceJson: jsonEncode(trace));
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> validateToolSpec(
    Map<String, Object?> tool,
  ) async {
    await _ensureInitialized();
    final json = await _api.validateToolSpec(toolJson: jsonEncode(tool));
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> validateLlmRequest(
    Map<String, Object?> request,
  ) async {
    await _ensureInitialized();
    final json = await _api.validateLlmRequest(
      requestJson: jsonEncode(request),
    );
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> validateLlmResponse(
    Map<String, Object?> response,
  ) async {
    await _ensureInitialized();
    final json = await _api.validateLlmResponse(
      responseJson: jsonEncode(response),
    );
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> completeMockLlm({
    required Map<String, Object?> request,
    required String responseText,
  }) async {
    await _ensureInitialized();
    final json = await _api.completeMockLlm(
      requestJson: jsonEncode(request),
      responseText: responseText,
    );
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> completeProfileLlm({
    required Map<String, Object?> request,
  }) async {
    await _ensureInitialized();
    final json = await _api.completeProfileLlm(
      requestJson: jsonEncode(request),
    );
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> startProfileTurnStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> llmRequest,
    required String agentId,
    required Map<String, Object?> runMetadata,
  }) async {
    await _ensureInitialized();
    final json = await _api.startProfileTurnStep(
      catalogJson: jsonEncode(catalog),
      llmRequestJson: jsonEncode(llmRequest),
      agentId: agentId,
      runMetadataJson: jsonEncode(runMetadata),
    );
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> startRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) async {
    await _ensureInitialized();
    final json = await _api.startRunStep(
      catalogJson: jsonEncode(catalog),
      requestJson: jsonEncode(request),
      agentId: agentId,
    );
    return _decodeObject(json);
  }

  @override
  Future<Map<String, Object?>> continueRunStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> previousStep,
    required Map<String, Object?> toolResponse,
    required String agentId,
  }) async {
    await _ensureInitialized();
    final json = await _api.continueRunStep(
      catalogJson: jsonEncode(catalog),
      previousStepJson: jsonEncode(previousStep),
      toolResponseJson: jsonEncode(toolResponse),
      agentId: agentId,
    );
    return _decodeObject(json);
  }

  Future<void> _ensureInitialized() {
    return _initFuture ??= _initRuntime(libraryPath: _libraryPath);
  }
}

class AgentRuntimeNativeStepRunner {
  const AgentRuntimeNativeStepRunner({
    required AgentRuntimeNativeBridge bridge,
    required AgentRuntimeToolHost toolHost,
    int defaultMaxToolSteps = 4,
  }) : _bridge = bridge,
       _toolHost = toolHost,
       _defaultMaxToolSteps = defaultMaxToolSteps;

  final AgentRuntimeNativeBridge _bridge;
  final AgentRuntimeToolHost _toolHost;
  final int _defaultMaxToolSteps;

  AgentRuntimeNativeBridge get bridge => _bridge;

  Future<Map<String, Object?>> startAndDispatchFirstToolStep({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
  }) {
    return runUntilTerminal(
      catalog: catalog,
      request: request,
      agentId: agentId,
      maxToolSteps: 1,
    );
  }

  Future<Map<String, Object?>> runUntilTerminal({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    int? maxToolSteps,
  }) async {
    return (await runUntilTerminalWithTrace(
      catalog: catalog,
      request: request,
      agentId: agentId,
      maxToolSteps: maxToolSteps,
    )).terminalStep;
  }

  Future<AgentRuntimeNativeStepRunResult> runUntilTerminalWithTrace({
    required Map<String, Object?> catalog,
    required Map<String, Object?> request,
    required String agentId,
    int? maxToolSteps,
  }) async {
    final step = await _bridge.startRunStep(
      catalog: catalog,
      request: request,
      agentId: agentId,
    );
    return continueUntilTerminalWithTrace(
      catalog: catalog,
      initialStep: step,
      agentId: agentId,
      maxToolSteps: maxToolSteps,
    );
  }

  Future<Map<String, Object?>> continueUntilTerminal({
    required Map<String, Object?> catalog,
    required Map<String, Object?> initialStep,
    required String agentId,
    int? maxToolSteps,
  }) async {
    return (await continueUntilTerminalWithTrace(
      catalog: catalog,
      initialStep: initialStep,
      agentId: agentId,
      maxToolSteps: maxToolSteps,
    )).terminalStep;
  }

  Future<AgentRuntimeNativeStepRunResult> continueUntilTerminalWithTrace({
    required Map<String, Object?> catalog,
    required Map<String, Object?> initialStep,
    required String agentId,
    int? maxToolSteps,
  }) async {
    final limit = maxToolSteps ?? _defaultMaxToolSteps;
    if (limit < 0) {
      throw RangeError.value(limit, 'maxToolSteps', 'must be non-negative');
    }

    var step = initialStep;
    var dispatched = 0;
    final steps = <Map<String, Object?>>[step];
    final toolResponses = <Map<String, Object?>>[];
    var budgetExhausted = false;

    while (step['status'] == 'tool_call_requested') {
      if (dispatched >= limit) {
        step = _toolBudgetExhaustedStep(step, limit);
        steps.add(step);
        budgetExhausted = true;
        return AgentRuntimeNativeStepRunResult(
          terminalStep: step,
          steps: steps,
          toolResponses: toolResponses,
          nativeTraceEvents: _nativeTraceEvents(steps),
          dispatchedToolCount: dispatched,
          budgetExhausted: budgetExhausted,
        );
      }
      dispatched += 1;

      final response = await _dispatchToolCall(step);
      toolResponses.add(response);
      step = await _bridge.continueRunStep(
        catalog: catalog,
        previousStep: step,
        toolResponse: response,
        agentId: agentId,
      );
      steps.add(step);
    }

    return AgentRuntimeNativeStepRunResult(
      terminalStep: step,
      steps: steps,
      toolResponses: toolResponses,
      nativeTraceEvents: _nativeTraceEvents(steps),
      dispatchedToolCount: dispatched,
      budgetExhausted: budgetExhausted,
    );
  }

  Future<Map<String, Object?>> _dispatchToolCall(
    Map<String, Object?> step,
  ) async {
    final toolCall = _expectObject(step['tool_call'], 'tool_call');
    final name = toolCall['name'];
    if (name is! String || name.isEmpty) {
      throw const FormatException('native tool_call.name is required');
    }

    final responseLine = await _toolHost.handleLine(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': _toolCallId(toolCall, step),
        'method': 'tool.call',
        'params': <String, Object?>{
          'name': name,
          'input': toolCall['input'] ?? const <String, Object?>{},
        },
      }),
    );
    return _decodeObject(responseLine);
  }
}

class AgentRuntimeNativeStepRunResult {
  const AgentRuntimeNativeStepRunResult({
    required this.terminalStep,
    this.steps = const <Map<String, Object?>>[],
    this.toolResponses = const <Map<String, Object?>>[],
    this.nativeTraceEvents = const <Map<String, Object?>>[],
    this.dispatchedToolCount = 0,
    this.budgetExhausted = false,
  });

  final Map<String, Object?> terminalStep;
  final List<Map<String, Object?>> steps;
  final List<Map<String, Object?>> toolResponses;
  final List<Map<String, Object?>> nativeTraceEvents;
  final int dispatchedToolCount;
  final bool budgetExhausted;

  Map<String, Object?> toJson() => <String, Object?>{
    'terminal_step': terminalStep,
    'steps': steps,
    'tool_responses': toolResponses,
    'native_trace_events': nativeTraceEvents,
    'dispatched_tool_count': dispatchedToolCount,
    'budget_exhausted': budgetExhausted,
  };
}

List<Map<String, Object?>> _nativeTraceEvents(
  Iterable<Map<String, Object?>> steps,
) {
  return [for (final step in steps) ?_objectOrNull(step['trace_event'])];
}

Map<String, Object?> _toolBudgetExhaustedStep(
  Map<String, Object?> step,
  int maxToolSteps,
) {
  return <String, Object?>{
    ...step,
    'status': 'failed',
    'error': <String, Object?>{
      'code': 'tool_call_budget_exhausted',
      'message': 'agent runtime tool-call budget exhausted',
      'max_tool_steps': maxToolSteps,
    },
  };
}

Map<String, Object?> _decodeObject(String json) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException(
      'native agent-runtime response is not an object',
    );
  }
  return decoded;
}

Map<String, Object?>? _objectOrNull(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

Map<String, Object?> _expectObject(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  throw FormatException(
    'native agent-runtime response field $field is not an object',
  );
}

Object _toolCallId(Map<String, Object?> toolCall, Map<String, Object?> step) {
  final explicitId = toolCall['tool_call_id'];
  if (explicitId is String && explicitId.isNotEmpty) return explicitId;
  final runId = step['run_id'];
  if (runId is String && runId.isNotEmpty) return runId;
  return 'tool_call';
}
