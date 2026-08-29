import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';

import '../domain/execution_models.dart';
import '_tool_support.dart';

/// User-facing Plan proposal. The existing project/commitment rows remain the
/// compatibility storage layer; `cadence` chooses the backing row without
/// exposing those implementation names in Assistant conversations.
class ProposePlanTool implements DeviceTool {
  const ProposePlanTool();

  @override
  String get name => 'propose_plan';

  @override
  String get description =>
      '建议新建一个 ExecutionOS Plan。bounded 表示有明确交付边界，ongoing '
      '表示持续维护；不会直接写库，用户确认后才创建。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'title': {'type': 'string', 'description': '计划名称。'},
      'description': {'type': 'string', 'description': '可选背景或范围。'},
      'cadence': {
        'type': 'string',
        'enum': ['bounded', 'ongoing'],
        'default': 'bounded',
        'description': '有明确完成边界，或需要持续维护。',
      },
      'horizon': {
        'type': 'string',
        'enum': ['week', 'month', 'quarter', 'open'],
        'default': 'open',
      },
      'target_date': {'type': 'string', 'description': '可选 ISO8601 目标日期。'},
      'parent_plan_id': {
        'type': 'string',
        'description': 'ongoing 计划可选的上级 bounded plan id。',
      },
      'source_domain': {'type': 'string', 'description': '可选来源域。'},
      'source_row_family': {
        'type': 'string',
        'description': '可选来源 row family。',
      },
      'source_row_id': {'type': 'string', 'description': '可选来源 row id。'},
      'source_label': {'type': 'string', 'description': '可选来源快照标签。'},
      'reason': {'type': 'string', 'description': '为什么建议建立这个计划。'},
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
    final cadence = (input['cadence'] as String?)?.trim() ?? 'bounded';
    if (cadence != 'bounded' && cadence != 'ongoing') {
      return badRequest('cadence 只支持 bounded / ongoing。');
    }
    final description = (input['description'] as String?)?.trim() ?? '';
    final horizon = ExecutionHorizon.parse(
      (input['horizon'] as String?)?.trim() ?? 'open',
    );
    final targetDate = optionalIsoDate(input['target_date']);
    final payload = <String, Object?>{
      'title': title,
      if (description.isNotEmpty) 'description': description,
      'horizon': horizon.wire,
      if (targetDate != null)
        'target_date': targetDate.toUtc().toIso8601String(),
      'reason': reason,
    };
    if (cadence == 'ongoing') {
      addOptionalString(payload, 'project_id', input['parent_plan_id']);
    }
    addSourceRefPayload(payload, input);

    return proposalEnvelope(
      kind: cadence == 'ongoing' ? 'execution_commitment' : 'execution_project',
      summaryZh:
          '建议新建${cadence == 'ongoing' ? '持续' : ''}计划：'
          '"${shortText(title)}" — $reason',
      payload: payload,
      note: '用户确认后创建 Plan；底层兼容存储类型不会暴露为新的产品概念。',
    );
  }
}
