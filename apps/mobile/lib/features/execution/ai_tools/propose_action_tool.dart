import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';

import '../domain/execution_models.dart';
import '_tool_support.dart';

class ProposeActionTool implements DeviceTool {
  const ProposeActionTool();

  @override
  String get name => 'propose_action';

  @override
  String get description =>
      '建议新建一条 ExecutionOS Action。不会直接写库,返回 proposal envelope,'
      '用户确认后由 ExecutionProposalApplier 创建 Action。适合把 Finance/Health/Knowledge '
      '洞察、决策或计划转成一个具体下一步。source_* 字段可选,用于中性跨域引用。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'title': {'type': 'string', 'description': '具体下一步,动词开头。'},
      'note': {'type': 'string', 'description': '可选备注或背景。'},
      'priority': {
        'type': 'string',
        'enum': ['low', 'normal', 'high'],
        'default': 'normal',
      },
      'due_at': {'type': 'string', 'description': '可选 ISO8601 截止时间。'},
      'scheduled_for': {'type': 'string', 'description': '可选 ISO8601 计划执行日。'},
      'project_id': {'type': 'string', 'description': '可选 Project id。'},
      'commitment_id': {'type': 'string', 'description': '可选 Commitment id。'},
      'source_domain': {'type': 'string', 'description': '可选来源域。'},
      'source_row_family': {
        'type': 'string',
        'description': '可选来源 row family。',
      },
      'source_row_id': {'type': 'string', 'description': '可选来源 row id。'},
      'source_label': {'type': 'string', 'description': '可选来源快照标签。'},
      'reason': {'type': 'string', 'description': '中文说明为什么建议这个 Action。'},
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
    final priorityRaw = (input['priority'] as String?)?.trim() ?? 'normal';
    final priority = ExecutionPriority.parse(priorityRaw);
    final dueAt = _parseIso(input['due_at']);
    final scheduledFor = _parseIso(input['scheduled_for']);
    final note = (input['note'] as String?)?.trim() ?? '';
    final summary = '建议新建 Action:"${shortText(title)}" — $reason';

    return proposalEnvelope(
      kind: 'execution_action',
      summaryZh: summary,
      payload: <String, Object?>{
        'title': title,
        if (note.isNotEmpty) 'note': note,
        'priority': priority.wire,
        if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
        if (scheduledFor != null)
          'scheduled_for': scheduledFor.toUtc().toIso8601String(),
        if (_string(input['project_id']) != null)
          'project_id': _string(input['project_id']),
        if (_string(input['commitment_id']) != null)
          'commitment_id': _string(input['commitment_id']),
        if (_string(input['source_domain']) != null)
          'source_domain': _string(input['source_domain']),
        if (_string(input['source_row_family']) != null)
          'source_row_family': _string(input['source_row_family']),
        if (_string(input['source_row_id']) != null)
          'source_row_id': _string(input['source_row_id']),
        if (_string(input['source_label']) != null)
          'source_label': _string(input['source_label']),
        'reason': reason,
      },
      note: '用户确认后创建 ExecutionOS Action；AI 不直接写入执行系统。',
    );
  }
}

DateTime? _parseIso(Object? raw) =>
    raw is String && raw.trim().isNotEmpty ? DateTime.tryParse(raw) : null;

String? _string(Object? raw) {
  final value = raw is String ? raw.trim() : '';
  return value.isEmpty ? null : value;
}
