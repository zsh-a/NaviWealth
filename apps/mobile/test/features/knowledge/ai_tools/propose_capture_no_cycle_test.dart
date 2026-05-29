/// Regression: dispatching `propose_capture` through the device runtime's
/// dispatcher must NOT raise a CircularDependencyError.
///
/// The dispatcher holds `deviceLlmRuntimeProvider`'s `ref`; the tool reads
/// `captureClassifierProvider`. Before the fix that classifier depended on
/// `deviceLlmRuntimeProvider` (→ the runtime depended on itself). It now
/// depends on the lighter `deviceLlmClientProvider`, breaking the cycle.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/device_tools_provider.dart';
import 'package:naviwealth/core/ai/composition/system_prompt_blocks.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_client.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/llm_stream_event.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/features/ai_chat/data/providers.dart';
import 'package:naviwealth/features/knowledge/ai_tools/propose_capture_tool.dart';

class _FakeConfig implements DeviceLlmConfig {
  const _FakeConfig();
  @override
  String get model => 'test-model';
}

/// Returns plain text → the LLM classifier fails to parse JSON and
/// silently degrades to the heuristic. We only care that the dispatch
/// completes without a circular-dependency error.
class _FakeClient implements DeviceLlmClient {
  @override
  DeviceLlmConfig get config => const _FakeConfig();

  @override
  Stream<LlmStreamEvent> streamMessages(
    AnthropicRequest request, {
    CancelToken? cancelToken,
  }) => throw UnimplementedError();

  @override
  Future<AnthropicCompletion> complete(
    AnthropicRequest request, {
    CancelToken? cancelToken,
  }) async => const AnthropicCompletion(
    content: <Object?>[
      <String, Object?>{'type': 'text', 'text': 'not json'},
    ],
  );
}

void main() {
  test('propose_capture dispatch via runtime ref does not cycle', () async {
    final container = ProviderContainer(
      overrides: [
        // Non-null client so the runtime materialises; captureClassifier
        // depends on THIS, not the runtime.
        deviceLlmClientProvider.overrideWithValue(_FakeClient()),
        deviceToolsProvider.overrideWith(
          (ref) => const <DeviceTool>[ProposeCaptureTool()],
        ),
        assembledSystemPromptProvider.overrideWithValue(''),
      ],
    );
    addTearDown(container.dispose);

    final runtime = container.read(deviceLlmRuntimeProvider);
    expect(runtime, isNotNull);

    final out = await runtime!.dispatcher.dispatch(
      DeviceSession(messages: const <AnthropicChatMessage>[]),
      'propose_capture',
      <String, Object?>{'text': '观察 MA、MSFT、MCD 的期权交易机会'},
    );

    final map = (out! as Map).cast<String, Object?>();
    // The pre-fix failure surfaced as {'error': 'CircularDependency…',
    // 'code': 'tool_error'}. Assert we got a real envelope instead.
    expect(map['code'], isNot('tool_error'));
    expect(map['error']?.toString() ?? '', isNot(contains('Circular')));
    expect(map['kind'], isNotNull); // capture envelope kind
  });
}
