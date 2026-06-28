import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';

import '../domain/execution_models.dart';
import '_tool_support.dart';

class ProposeActionStatusUpdateTool implements DeviceTool {
  const ProposeActionStatusUpdateTool();

  @override
  String get name => 'propose_action_status_update';

  @override
  String get description =>
      '建议更新一条已有 ExecutionOS Action 的状态。不会直接写库,返回 proposal envelope,'
      '用户确认后由 ExecutionProposalApplier 更新 Action。适合把用户指令中的完成、阻塞、'
      '恢复或放弃落到已有行动上。可选 progress_note 会在确认后同时记录一条进展。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'action_id': {'type': 'string', 'description': '要更新的 Action id。'},
      'status': {
        'type': 'string',
        'enum': ['todo', 'doing', 'blocked', 'done', 'dropped'],
        'description': '目标状态。',
      },
      'progress_note': {
        'type': 'string',
        'description': '可选进展记录；完成、阻塞或放弃时建议填写。',
      },
      'reason': {'type': 'string', 'description': '中文说明为什么建议更新状态。'},
    },
    'required': <String>['action_id', 'status', 'reason'],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final actionId = (input['action_id'] as String?)?.trim() ?? '';
    final statusRaw = (input['status'] as String?)?.trim() ?? '';
    final reason = (input['reason'] as String?)?.trim() ?? '';
    if (actionId.isEmpty || statusRaw.isEmpty || reason.isEmpty) {
      return badRequest('action_id / status / reason 必填。');
    }
    if (!ExecutionActionStatus.values.any((s) => s.wire == statusRaw)) {
      return badRequest('status 必须是 todo / doing / blocked / done / dropped。');
    }
    final status = ExecutionActionStatus.parse(statusRaw);
    final progressNote = (input['progress_note'] as String?)?.trim() ?? '';
    final payload = <String, Object?>{
      'action_id': actionId,
      'status': status.wire,
      if (progressNote.isNotEmpty) 'progress_note': progressNote,
      'reason': reason,
    };

    return proposalEnvelope(
      kind: 'execution_action_status_update',
      summaryZh: '建议更新 Action 状态:$actionId → ${status.wire} — $reason',
      payload: payload,
      note: '用户确认后更新已有 ExecutionOS Action；AI 不直接写入执行系统。',
    );
  }
}
