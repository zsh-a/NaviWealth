/// Regression: dispatching `propose_capture` through a dispatcher holding a
/// ProviderContainer ref must NOT raise a CircularDependencyError.
///
/// The dispatcher holds `ref`; the tool reads `captureClassifierProvider`.
/// Before the FRB migration that classifier depended on the legacy chat
/// runtime provider, which could make the provider graph depend on itself. It
/// now depends on the FRB profile bridge seam and falls back to the heuristic
/// when that seam is absent.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naviwealth/core/ai/composition/device_tools_provider.dart';
import 'package:naviwealth/core/ai/runtime/device/anthropic/anthropic_wire.dart';
import 'package:naviwealth/core/ai/runtime/device/device_session.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool_registry.dart';
import 'package:naviwealth/features/knowledge/ai_tools/propose_capture_tool.dart';

final _dispatchProposeCaptureProvider = FutureProvider<Object?>((ref) async {
  final registry = DeviceToolRegistry(ref.watch(deviceToolsProvider));
  final dispatcher = DriftDeviceToolDispatcher(ref: ref, registry: registry);
  return dispatcher.dispatch(
    DeviceSession(messages: const <AnthropicChatMessage>[]),
    'propose_capture',
    <String, Object?>{'text': '观察 MA、MSFT、MCD 的期权交易机会'},
  );
});

void main() {
  test('propose_capture dispatch via provider ref does not cycle', () async {
    final container = ProviderContainer(
      overrides: [
        deviceToolsProvider.overrideWith(
          (ref) => const <DeviceTool>[ProposeCaptureTool()],
        ),
      ],
    );
    addTearDown(container.dispose);

    final out = await container.read(_dispatchProposeCaptureProvider.future);

    final map = (out! as Map).cast<String, Object?>();
    // The pre-fix failure surfaced as {'error': 'CircularDependency…',
    // 'code': 'tool_error'}. Assert we got a real envelope instead.
    expect(map['code'], isNot('tool_error'));
    expect(map['error']?.toString() ?? '', isNot(contains('Circular')));
    expect(map['kind'], isNotNull); // capture envelope kind
  });
}
