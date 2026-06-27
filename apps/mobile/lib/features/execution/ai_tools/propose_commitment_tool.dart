import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';

import '../domain/execution_models.dart';
import '_tool_support.dart';

class ProposeCommitmentTool implements DeviceTool {
  const ProposeCommitmentTool();

  @override
  String get name => 'propose_commitment';

  @override
  String get description =>
      '建议新建一个 ExecutionOS Commitment。不会直接写库,返回 proposal envelope,'
      '用户确认后由 ExecutionProposalApplier 创建 Commitment。适合表达较长期、'
      '需要持续跟进的承诺,可选关联 Project。source_* 字段可选,用于中性跨域引用。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'title': {'type': 'string', 'description': '承诺名称。'},
      'description': {'type': 'string', 'description': '可选承诺背景或范围。'},
      'horizon': {
        'type': 'string',
        'enum': ['week', 'month', 'quarter', 'open'],
        'default': 'open',
      },
      'target_date': {'type': 'string', 'description': '可选 ISO8601 目标日期。'},
      'project_id': {'type': 'string', 'description': '可选 Project id。'},
      'source_domain': {'type': 'string', 'description': '可选来源域。'},
      'source_row_family': {
        'type': 'string',
        'description': '可选来源 row family。',
      },
      'source_row_id': {'type': 'string', 'description': '可选来源 row id。'},
      'source_label': {'type': 'string', 'description': '可选来源快照标签。'},
      'reason': {'type': 'string', 'description': '中文说明为什么建议这个 Commitment。'},
    },
    'required': <String>['title', 'reason'],
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final title = (input['title'] as String?)?.trim() ?? '';
    final reason = (input['reason'] as String?)?.trim() ?? '';
    if (title.isEmpty || reason.isEmpty) {
      return badRequest('title / reason 必填。');
    }
    final description = (input['description'] as String?)?.trim() ?? '';
    final horizon = ExecutionHorizon.parse(
      (input['horizon'] as String?)?.trim() ?? 'open',
    );
    final targetDate = optionalIsoDate(input['target_date']);
    final summary = '建议新建 Commitment:"${shortText(title)}" — $reason';
    final payload = <String, Object?>{
      'title': title,
      if (description.isNotEmpty) 'description': description,
      'horizon': horizon.wire,
      if (targetDate != null)
        'target_date': targetDate.toUtc().toIso8601String(),
    };
    addOptionalString(payload, 'project_id', input['project_id']);
    addSourceRefPayload(payload, input);
    payload['reason'] = reason;

    return proposalEnvelope(
      kind: 'execution_commitment',
      summaryZh: summary,
      payload: payload,
      note: '用户确认后创建 ExecutionOS Commitment；AI 不直接写入执行系统。',
    );
  }
}
