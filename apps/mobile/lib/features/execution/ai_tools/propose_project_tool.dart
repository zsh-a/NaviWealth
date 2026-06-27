import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';

import '../domain/execution_models.dart';
import '_tool_support.dart';

class ProposeProjectTool implements DeviceTool {
  const ProposeProjectTool();

  @override
  String get name => 'propose_project';

  @override
  String get description =>
      '建议新建一个 ExecutionOS Project。不会直接写库,返回 proposal envelope,'
      '用户确认后由 ExecutionProposalApplier 创建 Project。适合把一组可交付事项'
      '收束成有边界的执行容器。source_* 字段可选,用于中性跨域引用。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'title': {'type': 'string', 'description': '项目名称。'},
      'description': {'type': 'string', 'description': '可选项目背景或范围。'},
      'horizon': {
        'type': 'string',
        'enum': ['week', 'month', 'quarter', 'open'],
        'default': 'open',
      },
      'target_date': {'type': 'string', 'description': '可选 ISO8601 目标日期。'},
      'source_domain': {'type': 'string', 'description': '可选来源域。'},
      'source_row_family': {
        'type': 'string',
        'description': '可选来源 row family。',
      },
      'source_row_id': {'type': 'string', 'description': '可选来源 row id。'},
      'source_label': {'type': 'string', 'description': '可选来源快照标签。'},
      'reason': {'type': 'string', 'description': '中文说明为什么建议这个 Project。'},
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
    final summary = '建议新建 Project:"${shortText(title)}" — $reason';
    final payload = <String, Object?>{
      'title': title,
      if (description.isNotEmpty) 'description': description,
      'horizon': horizon.wire,
      if (targetDate != null)
        'target_date': targetDate.toUtc().toIso8601String(),
    };
    addSourceRefPayload(payload, input);
    payload['reason'] = reason;

    return proposalEnvelope(
      kind: 'execution_project',
      summaryZh: summary,
      payload: payload,
      note: '用户确认后创建 ExecutionOS Project；AI 不直接写入执行系统。',
    );
  }
}
