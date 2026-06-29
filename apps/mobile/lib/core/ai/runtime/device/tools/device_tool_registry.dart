/// Device tool registry + Drift-backed dispatcher.
///
/// D-1.2: the registry *class* and the dispatcher live here as
/// domain-neutral runtime. The *tool list* is composed per-domain via
/// [deviceToolsProvider] (`core/ai/composition/device_tools_provider.dart`)
/// — each LifeOS domain registers its tools in
/// `features/[domain]/ai_tools/`. The single shell exception is the Memory Layer pair
/// (`build_context_tool.dart` / `query_memory_tool.dart`) which is
/// cross-domain by design.
///
/// **Allow-list decision** (see §11): registry *membership* is the
/// device allow-list. `ToolDescriptor` is metadata for registered
/// tools; dispatch authority still comes from this list because a
/// missing implementation is the strongest possible deny.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../composition/tool_descriptor_lookup.dart';
import '../../../contracts/intent.dart' show RiskLevel;
import '../../../contracts/privacy_budget.dart' show BudgetTier;
import '../../../contracts/tool_descriptor.dart';
import '../anthropic/anthropic_wire.dart';
import '../device_tool_dispatcher.dart';
import '../device_tool_session.dart';
import 'ask_user_tool.dart';
import 'build_context_tool.dart';
import 'device_tool.dart';
import 'query_memory_tool.dart';

/// Per-tool dispatch backstop. Most device tools are local Drift reads
/// (sub-100ms), but a few can call FRB-backed LLM classifiers (for example
/// `propose_capture`) and an extended-thinking model can legitimately take
/// 30s+. Set high enough not to kill those mid-flight; it stays a safety net
/// against a genuinely hung tool. LLM-backed tools carry their own request
/// timeout + heuristic fallback inside.
const Duration kPerToolTimeout = Duration(seconds: 60);

/// Shell-only tools (cross-domain). Domain tool lists live under
/// `features/<domain>/ai_tools/`.
const List<DeviceTool> kShellDeviceToolsCore = <DeviceTool>[
  QueryMemoryTool(),
  BuildContextTool(),
  AskUserTool(),
];

/// Shell-only tool descriptors. Co-located with [kShellDeviceToolsCore]
/// so adding a shell tool is a single-file change. Merged into
/// `domainToolDescriptors` alongside each LifeOS domain's contribution.
const Map<String, ToolDescriptor> kShellToolDescriptors =
    <String, ToolDescriptor>{
      'query_memory': ToolDescriptor(
        name: 'query_memory',
        access: Access.read,
        risk: RiskLevel.info,
        requiresConfirmation: Confirmation.none,
        allowedContextTier: BudgetTier.small,
        domain: kDomainShell,
      ),
      'build_context': ToolDescriptor(
        name: 'build_context',
        access: Access.read,
        risk: RiskLevel.info,
        requiresConfirmation: Confirmation.none,
        allowedContextTier: BudgetTier.standard,
        domain: kDomainShell,
      ),
      // Interaction tool: no data side effect, but it pauses the agent loop
      // and hands a structured decision to the user (see `ask_user_tool.dart`).
      'ask_user': ToolDescriptor(
        name: 'ask_user',
        access: Access.read,
        risk: RiskLevel.info,
        requiresConfirmation: Confirmation.none,
        allowedContextTier: BudgetTier.small,
        domain: kDomainShell,
      ),
    };

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
    DeviceToolSession session,
    String name,
    Object? input,
  ) async {
    final tool = _registry.lookup(name);
    if (tool == null) {
      return _policyDenied(name, 'unknown_tool', '未注册的端侧工具：$name');
    }
    // §4.5 — external side effects are never auto-dispatched.
    final descriptor = _ref.read(toolDescriptorLookupProvider)(name);
    if (descriptor?.sideEffect == SideEffect.externalCall) {
      return _policyDenied(name, 'runtime_not_allowed', '该工具有外部副作用，端侧不自动执行。');
    }
    if (descriptor != null &&
        !name.startsWith('propose_') &&
        (descriptor.sideEffect == SideEffect.deviceLocalWrite ||
            descriptor.requiresConfirmation != Confirmation.none)) {
      return _policyDenied(
        name,
        'confirmation_required',
        '该工具需要用户确认，不能作为普通工具自动执行。',
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

  /// Stable `policy_denied` envelope retained from the retired backend
  /// contract so older UI/debug expectations keep the same shape.
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
