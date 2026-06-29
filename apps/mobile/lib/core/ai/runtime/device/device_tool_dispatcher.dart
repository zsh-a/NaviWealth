/// Device tool dispatch contract.
///
/// Production chat uses the Drift-backed dispatcher in
/// `device/tools/device_tool_registry.dart`. [UnavailableToolDispatcher]
/// remains the default safety net for tests and shell-only construction:
/// it returns a standard error tool_result instead of crashing a turn if
/// a model somehow calls a tool that was not wired into the runtime.
library;

import 'device_tool_session.dart';

abstract class DeviceToolDispatcher {
  /// Execute `name(input)` against local data. Returns the JSON-able
  /// output the loop serialises into a `tool_result` block. Must never
  /// throw — surface failures as an `{error, code, message}` map so the
  /// model can react.
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  );
}

/// Placeholder. With no tool schemas advertised the model
/// shouldn't call tools at all; this is the safety net if it does.
class UnavailableToolDispatcher implements DeviceToolDispatcher {
  const UnavailableToolDispatcher();

  @override
  Future<Object?> dispatch(
    DeviceToolSession session,
    String name,
    Object? input,
  ) async => <String, Object?>{
    'error': 'tool_unavailable',
    'code': 'tool_unavailable',
    'tool': name,
    'message':
        '端侧工具尚未接入。请直接基于已知信息回答，'
        '或告诉用户该数据当前在本机模式下不可用。',
  };
}
