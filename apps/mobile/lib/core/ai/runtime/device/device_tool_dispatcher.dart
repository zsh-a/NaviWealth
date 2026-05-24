/// Device tool dispatch contract (§4.6 W-D3).
///
/// Port of the backend `ToolDispatcher` trait. W-D4 supplies the real
/// implementation reading Drift; until then [UnavailableToolDispatcher]
/// returns a standard error tool_result so a model that calls a tool
/// degrades to "I can't read that yet" rather than crashing the turn —
/// the same shape `risk_policy` denials use on the backend.
library;

import 'device_session.dart';

abstract class DeviceToolDispatcher {
  /// Execute `name(input)` against local data. Returns the JSON-able
  /// output the loop serialises into a `tool_result` block. Must never
  /// throw — surface failures as an `{error, code, message}` map so the
  /// model can react.
  Future<Object?> dispatch(DeviceSession session, String name, Object? input);
}

/// Placeholder until W-D4. With no tool schemas advertised the model
/// shouldn't call tools at all; this is the safety net if it does.
class UnavailableToolDispatcher implements DeviceToolDispatcher {
  const UnavailableToolDispatcher();

  @override
  Future<Object?> dispatch(
    DeviceSession session,
    String name,
    Object? input,
  ) async => <String, Object?>{
    'error': 'tool_unavailable',
    'code': 'tool_unavailable',
    'tool': name,
    'message':
        '端侧工具尚未接入（W-D4 待落地）。请直接基于已知信息回答，'
        '或告诉用户该数据当前在本机模式下不可用。',
  };
}
