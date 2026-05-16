/// Device tool registry + Drift-backed dispatcher (§4.6 W-D4).
///
/// Port of `apps/backend/src/ai/tools/registry.rs`: an id→tool map, a
/// `schemas()` feed for the agent loop, a per-tool timeout, and the
/// **exact** backend error envelopes (`policy_denied` / `tool_timeout`)
/// so the model sees the same failure shapes on device and cloud.
///
/// **Allow-list decision** (see §11): registry *membership* is the
/// device allow-list — a tool runs on device iff a Drift-backed port
/// is registered here. The `ToolDescriptor.allowed_runtimes` field
/// stays `cloud_only` on both sides until W-D7 reconciles it with the
/// backend (a frozen-code change), so it is *not* used as the gate; a
/// missing impl is a stronger guarantee than a metadata flag. The
/// dispatcher still refuses `external_call` side-effects as
/// defense-in-depth (§4.5 — ExternalSideEffect is never LLM-triggered).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../contracts/tool_descriptor.dart';
import '../anthropic/anthropic_wire.dart';
import '../device_session.dart';
import '../device_tool_dispatcher.dart';
import 'device_tool.dart';
import 'get_anomaly_flags_tool.dart';
import 'get_asset_allocation_tool.dart';
import 'get_holdings_tool.dart';
import 'get_recurring_patterns_tool.dart';
import 'list_payment_accounts_tool.dart';

/// Mirrors backend `PER_TOOL_TIMEOUT_MS`.
const Duration kPerToolTimeout = Duration(seconds: 15);

/// Canonical device-dispatchable tool set. Registry membership *is* the
/// device allow-list (§11): a tool runs on device iff a Drift-backed
/// port is registered here. Single source for the provider and the
/// W-D6 static-contract test (every name must resolve in the shared
/// `tool_descriptor.dart` mirror).
const List<DeviceTool> kDeviceTools = <DeviceTool>[
  ListPaymentAccountsTool(),
  GetHoldingsTool(),
  GetAssetAllocationTool(),
  GetAnomalyFlagsTool(),
  GetRecurringPatternsTool(),
];

DeviceToolRegistry defaultDeviceToolRegistry() =>
    DeviceToolRegistry(kDeviceTools);

class DeviceToolRegistry {
  DeviceToolRegistry(Iterable<DeviceTool> tools)
    : _tools = {for (final t in tools) t.name: t};

  final Map<String, DeviceTool> _tools;

  DeviceTool? lookup(String name) => _tools[name];

  Iterable<String> get names => _tools.keys;

  /// Tool schemas fed to [AnthropicRequest.tools]. Sorted by name for
  /// stable prompts / golden tests, like the backend `schemas()`.
  List<AnthropicToolSchema> schemas() {
    final out = [
      for (final t in _tools.values)
        AnthropicToolSchema(
          name: t.name,
          description: t.description,
          inputSchema: t.inputSchema,
        ),
    ];
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }
}

/// [DeviceToolDispatcher] backed by the device registry + Riverpod.
class DriftDeviceToolDispatcher implements DeviceToolDispatcher {
  DriftDeviceToolDispatcher({
    required Ref ref,
    required DeviceToolRegistry registry,
    Duration perToolTimeout = kPerToolTimeout,
  }) : _ref = ref,
       _registry = registry,
       _timeout = perToolTimeout;

  final Ref _ref;
  final DeviceToolRegistry _registry;
  final Duration _timeout;

  @override
  Future<Object?> dispatch(
    DeviceSession session,
    String name,
    Object? input,
  ) async {
    final tool = _registry.lookup(name);
    if (tool == null) {
      return _policyDenied(name, 'unknown_tool', '未注册的端侧工具：$name');
    }
    // §4.5 — external side effects are never auto-dispatched.
    if (lookupToolDescriptor(name)?.sideEffect == SideEffect.externalCall) {
      return _policyDenied(
        name,
        'runtime_not_allowed',
        '该工具有外部副作用，端侧不自动执行。',
      );
    }

    final args = input is Map
        ? input.map((k, v) => MapEntry(k.toString(), v))
        : <String, Object?>{};
    try {
      return await tool
          .invoke(DeviceToolContext(ref: _ref, session: session), args)
          .timeout(
            _timeout,
            onTimeout: () => <String, Object?>{
              'error':
                  "tool '$name' timed out after ${_timeout.inMilliseconds}ms",
              'code': 'tool_timeout',
              'tool': name,
            },
          );
    } catch (e) {
      return <String, Object?>{'error': '$e', 'code': 'tool_error'};
    }
  }

  /// Exact backend `policy_denied_result` envelope.
  Map<String, Object?> _policyDenied(
    String tool,
    String policy,
    String message,
  ) => <String, Object?>{
    'error': {
      'code': 'policy_denied',
      'policy': policy,
      'tool': tool,
      'message': message,
    },
    'policy_denied': true,
  };
}
