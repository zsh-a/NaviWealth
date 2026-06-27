import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';

import '../domain/execution_models.dart';
import '_tool_support.dart';

class ProposeProgressTool implements DeviceTool {
  const ProposeProgressTool();

  @override
  String get name => 'propose_progress';

  @override
  String get description =>
      '建议记录一条 ExecutionOS ProgressEntry。不会直接写库,返回 proposal envelope,'
      '用户确认后由 ExecutionProposalApplier 创建 ProgressEntry。适合把复盘、阻塞、'
      '范围变化或完成情况记录到执行系统,可选关联 Action / Project / Commitment。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'note': {'type': 'string', 'description': '进展记录正文。'},
      'kind': {
        'type': 'string',
        'enum': ['checkin', 'blocker', 'scopeChange', 'completion', 'dropped'],
        'default': 'checkin',
      },
      'action_id': {'type': 'string', 'description': '可选 Action id。'},
      'project_id': {'type': 'string', 'description': '可选 Project id。'},
      'commitment_id': {'type': 'string', 'description': '可选 Commitment id。'},
      'reason': {
        'type': 'string',
        'description': '中文说明为什么建议记录这个 ProgressEntry。',
      },
    },
    'required': <String>['note', 'reason'],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final note = (input['note'] as String?)?.trim() ?? '';
    final reason = (input['reason'] as String?)?.trim() ?? '';
    if (note.isEmpty || reason.isEmpty) {
      return badRequest('note / reason 必填。');
    }
    final kind = ExecutionProgressKind.parse(
      (input['kind'] as String?)?.trim() ?? 'checkin',
    );
    final summary = '建议记录 Progress:"${shortText(note)}" — $reason';
    final payload = <String, Object?>{'note': note, 'kind': kind.wire};
    addOptionalString(payload, 'action_id', input['action_id']);
    addOptionalString(payload, 'project_id', input['project_id']);
    addOptionalString(payload, 'commitment_id', input['commitment_id']);
    payload['reason'] = reason;

    return proposalEnvelope(
      kind: 'execution_progress',
      summaryZh: summary,
      payload: payload,
      note: '用户确认后记录 ExecutionOS 进展；AI 不直接写入执行系统。',
    );
  }
}
