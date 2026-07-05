import 'dart:io';

import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_llm_stream_bridge.dart';
import 'package:naviwealth/app/agent_runtime/bridges/agent_runtime_native_bridge.dart';
import 'package:naviwealth/app/agent_runtime/catalog/agent_runtime_catalog.dart';
import 'package:naviwealth/app/agent_runtime/chat/frb_chat_runner.dart';
import 'package:naviwealth/app/agent_runtime/tools/agent_runtime_tool_host.dart';
import 'package:naviwealth/core/ai/contracts/contracts.dart';
import 'package:naviwealth/core/ai/llm_credentials/llm_credentials.dart';
import 'package:naviwealth/core/ai/local/embedding/rust_gemma_embedder.dart';
import 'package:naviwealth/core/ai/runtime/device/device_tool_dispatcher.dart';
import 'package:naviwealth/core/lifeos/domain_pack.dart';

final class RealLlmE2eConfig {
  RealLlmE2eConfig._(this._env);

  factory RealLlmE2eConfig.fromEnvironment() {
    return RealLlmE2eConfig.fromMap(Platform.environment);
  }

  factory RealLlmE2eConfig.fromMap(Map<String, String> env) {
    return RealLlmE2eConfig._(Map<String, String>.unmodifiable(env));
  }

  final Map<String, String> _env;

  bool get enabled => _enabledFlag && apiKey.isNotEmpty;

  bool get _enabledFlag {
    final value = (_env['RUN_REAL_LLM_E2E'] ?? '').toLowerCase();
    return value == '1' || value == 'true' || value == 'yes';
  }

  String get apiKey => _env['E2E_LLM_API_KEY'] ?? '';

  LlmProvider get provider => LlmProvider.parse(_env['E2E_LLM_PROVIDER']);

  String? get model {
    final value = _env['E2E_LLM_MODEL']?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? get baseUrl {
    final value = _env['E2E_LLM_BASE_URL']?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? get nativeLibraryPath {
    final value =
        (_env['E2E_LIFEOS_NATIVE_LIBRARY_PATH'] ??
                _env['RUST_EMBEDDER_LIBRARY_PATH'])
            ?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  int get maxToolRounds => _readInt('E2E_LLM_MAX_TOOL_ROUNDS', 8);

  Duration get timeout =>
      Duration(seconds: _readInt('E2E_LLM_TIMEOUT_SECONDS', 180));

  LlmProfile get profile => LlmProfile(
    id: 'real_llm_e2e',
    name: 'Real LLM E2E',
    provider: provider,
    apiKey: apiKey,
    baseUrl: baseUrl,
    model: model,
  );

  String get notEnabledReason {
    if (!_enabledFlag) {
      return 'RUN_REAL_LLM_E2E is not enabled';
    }
    if (apiKey.isEmpty) {
      return 'E2E_LLM_API_KEY is empty';
    }
    return 'real LLM E2E is enabled';
  }

  int _readInt(String key, int fallback) {
    final raw = _env[key];
    if (raw == null) return fallback;
    return int.tryParse(raw) ?? fallback;
  }
}

FrbChatRunner realLlmFrbChatRunner({
  required RealLlmE2eConfig config,
  required List<Map<String, Object?>> tools,
  required DeviceToolDispatcher dispatcher,
  required String agentId,
}) {
  final nativeBridge = FfiAgentRuntimeNativeBridge(
    api: const FrbAgentRuntimeNativeApi(),
    initRuntime: initLifeosNativeRuntime,
    libraryPath: config.nativeLibraryPath,
  );
  final llmBridge = AgentRuntimeLlmBridge(
    bridge: nativeBridge,
    profile: config.profile,
  );
  final streamBridge = AgentRuntimeLlmStreamBridge(
    llmBridge: llmBridge,
    initRuntime: initLifeosNativeRuntime,
    libraryPath: config.nativeLibraryPath,
  );
  final toolHost = AgentRuntimeToolHost(dispatcher: dispatcher);
  return FrbChatRunner(
    streamBridge: streamBridge,
    tools: tools,
    toolLineHandler: toolHost.handleLine,
    maxToolRounds: config.maxToolRounds,
    agentId: agentId,
  );
}

Map<String, Object?> e2eToolSpec({
  required String name,
  required String description,
  List<String> required = const <String>[],
  Map<String, Object?> properties = const <String, Object?>{},
  String risk = 'read_only',
}) {
  return <String, Object?>{
    'name': name,
    'description': description,
    'input_schema': <String, Object?>{
      'type': 'object',
      if (required.isNotEmpty) 'required': required,
      'properties': properties,
      'additionalProperties': true,
    },
    'risk': risk,
  };
}

List<Map<String, Object?>> domainPackE2eToolSpecs({
  required List<DomainPack> packs,
  required Set<String> selectedNames,
}) {
  final specs = <Map<String, Object?>>[
    for (final pack in packs)
      for (final tool in pack.deviceTools)
        if (selectedNames.contains(tool.name))
          AgentRuntimeToolSpec.fromTool(
            tool,
            descriptor: pack.toolDescriptors[tool.name],
          ).toJson(),
  ];
  _assertSelectedToolsExist(specs, selectedNames);
  return specs;
}

void _assertSelectedToolsExist(
  List<Map<String, Object?>> specs,
  Set<String> selectedNames,
) {
  final foundNames = {
    for (final spec in specs)
      if (spec['name'] is String) spec['name'] as String,
  };
  final missing = selectedNames.difference(foundNames);
  if (missing.isNotEmpty) {
    throw StateError('Missing DomainPack E2E tools: ${missing.join(', ')}');
  }
  final seenNames = <String>{};
  final duplicateNames = <String>{};
  for (final spec in specs) {
    final name = spec['name'];
    if (name is! String) continue;
    if (!seenNames.add(name)) duplicateNames.add(name);
  }
  if (duplicateNames.isNotEmpty) {
    throw StateError(
      'Duplicate DomainPack E2E tools: ${duplicateNames.join(', ')}',
    );
  }
}

final class ScenarioTurnResult {
  const ScenarioTurnResult(this.events);

  final List<AiChatEvent> events;

  String get text =>
      events.whereType<TextEvent>().map((event) => event.text).join().trim();

  DoneEvent? get done {
    for (final event in events.reversed) {
      if (event is DoneEvent) return event;
    }
    return null;
  }

  List<String> get toolCalls =>
      events.whereType<ToolCallEvent>().map((event) => event.name).toList();

  List<ErrorEvent> get errors => events.whereType<ErrorEvent>().toList();

  List<SpanEvent> get spans => events.whereType<SpanEvent>().toList();

  String diagnosticText() {
    return events
        .map((event) {
          return switch (event) {
            TextEvent(:final text) => text,
            ToolCallEvent(:final name) => 'tool_call:$name',
            ToolResultEvent(:final name) => 'tool_result:$name',
            ErrorEvent(:final code, :final message) => 'error:$code:$message',
            DoneEvent(:final stopReason, :final rounds) =>
              'done:$stopReason:$rounds',
            SpanEvent(:final name, :final status) => 'span:$name:$status',
            _ => event.runtimeType.toString(),
          };
        })
        .join('\n');
  }
}

typedef ScenarioProgressReporter = void Function(AiChatEvent event);

final class ScenarioTurnProgressPrinter {
  ScenarioTurnProgressPrinter(this.label, {IOSink? output})
    : _output = output ?? stdout {
    _write('start');
  }

  final String label;
  final IOSink _output;
  final Stopwatch _watch = Stopwatch()..start();
  int _visibleTextChars = 0;
  int _reportedVisibleTextChars = 0;
  int _thinkingChars = 0;
  int _reportedThinkingChars = 0;

  void call(AiChatEvent event) {
    switch (event) {
      case ThinkingDeltaEvent(:final text):
        _thinkingChars += text.length;
        _maybeReportThinking(force: false);
      case TextEvent(:final text):
        _visibleTextChars += text.length;
        _maybeReportText(force: false);
      case ToolCallStartEvent(:final name):
        _write('tool_call_start $name');
      case ToolCallEvent(:final name):
        _write('tool_call $name');
      case ToolResultEvent(:final name):
        _write('tool_result $name');
      case UsageEvent(:final usage):
        _write(
          'usage input=${usage.input} output=${usage.output} '
          'cache_read=${usage.cacheRead} cache_write=${usage.cacheWrite} '
          'total=${usage.total}',
        );
      case ProgressEvent(:final progress):
        final ratio = progress.normalisedRatio;
        final ratioText = ratio == null
            ? 'indeterminate'
            : '${(ratio * 100).round()}%';
        final detail = progress.detail;
        _write(
          detail == null
              ? 'progress ${progress.label} $ratioText'
              : 'progress ${progress.label} $ratioText - $detail',
        );
      case SpanEvent(:final kind, :final name, :final status, :final tokens):
        final tokenText = tokens == null ? '' : ' tokens=${tokens.total}';
        _write('span $kind $name $status$tokenText');
      case ErrorEvent(:final code, :final message):
        _maybeReportThinking(force: true);
        _maybeReportText(force: true);
        _write('error ${code ?? 'unknown'} ${_singleLine(message)}');
      case DoneEvent(:final stopReason, :final rounds):
        _maybeReportThinking(force: true);
        _maybeReportText(force: true);
        _write('done stop=$stopReason rounds=$rounds');
      case ToolCallDeltaEvent():
        break;
    }
  }

  void _maybeReportThinking({required bool force}) {
    if (_thinkingChars == _reportedThinkingChars) return;
    if (!force && _thinkingChars - _reportedThinkingChars < 240) return;
    _reportedThinkingChars = _thinkingChars;
    _write('thinking_chars=$_thinkingChars');
  }

  void _maybeReportText({required bool force}) {
    if (_visibleTextChars == _reportedVisibleTextChars) return;
    if (!force && _visibleTextChars - _reportedVisibleTextChars < 240) return;
    _reportedVisibleTextChars = _visibleTextChars;
    _write('assistant_text_chars=$_visibleTextChars');
  }

  void _write(String message) {
    _output.writeln('[real-llm-e2e][$label +${_elapsed()}] $message');
  }

  String _elapsed() {
    final elapsed = _watch.elapsed;
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    final millis = elapsed.inMilliseconds
        .remainder(1000)
        .toString()
        .padLeft(3, '0');
    return '$minutes:$seconds.$millis';
  }
}

Future<ScenarioTurnResult> collectScenarioTurn(
  Stream<AiChatEvent> stream, {
  required Duration timeout,
  ScenarioProgressReporter? progress,
}) async {
  final events = <AiChatEvent>[];
  await for (final event in stream.timeout(timeout)) {
    events.add(event);
    progress?.call(event);
  }
  return ScenarioTurnResult(events);
}

String _singleLine(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}
