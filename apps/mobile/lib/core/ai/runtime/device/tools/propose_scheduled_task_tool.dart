import 'package:uuid/uuid.dart';

import '../../../../auth/current_user.dart';
import '../../../../auth/domain_scope.dart';
import '../../../../auth/providers.dart' as auth;
import '../../../agents/scheduled_agent_task.dart';
import '../../../composition/proposal_envelope.dart';
import 'device_tool.dart';

/// Returns a proposal only. No task runs before the shared confirmation path.
class ProposeScheduledTaskTool implements DeviceTool {
  const ProposeScheduledTaskTool();
  @override
  String get name => 'propose_scheduled_task';
  @override
  String get description =>
      'Only when the user explicitly requests recurring assistance, propose a weekly read-only LLM report. '
      'Ask for missing time/domain/goal. Never claim the task is active before confirmation. '
      'It uses the current model profile and device local time; runs on foreground catch-up, not guaranteed in background.';
  @override
  Map<String, Object?> get inputSchema => const {
    'type': 'object',
    'additionalProperties': false,
    'required': [
      'title',
      'instructions',
      'domain',
      'weekday',
      'hour',
      'minute',
    ],
    'properties': {
      'title': {'type': 'string', 'maxLength': 100},
      'instructions': {'type': 'string', 'maxLength': 4000},
      'domain': {
        'type': 'string',
        'enum': ['finance', 'health', 'knowledge', 'execution'],
      },
      'weekday': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 7,
        'description': 'ISO weekday, Monday=1',
      },
      'hour': {'type': 'integer', 'minimum': 0, 'maximum': 23},
      'minute': {'type': 'integer', 'minimum': 0, 'maximum': 59},
    },
  };
  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final domain = DomainScope.tryParse(input['domain'] as String? ?? '');
    if (domain == null ||
        !(await ctx.ref.read(auth.domainOptInsProvider.future))
            .contains(domain)) {
      return proposalBadRequest('所选领域尚未启用。');
    }
    final proposalId = const Uuid().v4();
    final ScheduledAgentTask task;
    try {
      task = ScheduledAgentTask.fromJson({
        ...input,
        'id': 'user_task:$proposalId',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'revision': 1,
      });
    } on Object {
      return proposalBadRequest('请提供任务目标、领域和有效的每周执行时间。');
    }
    final time =
        '${task.schedule.preferredHourLocal.toString().padLeft(2, '0')}:${task.schedule.minuteLocal.toString().padLeft(2, '0')}';
    return readyPlan(
      proposalId: proposalId,
      kind: 'scheduled_task',
      summaryZh:
          '${task.title} · 每周${['一', '二', '三', '四', '五', '六', '日'][task.schedule.weekdayLocal! - 1]} $time\n'
          '${task.instructions}\n只读范围：${task.domain.wire}；使用当前模型服务；设备本地时间；回到前台时补跑。',
      payload: {
        'owner_user_id': await ctx.ref.read(currentUserIdProvider)(),
        'task': task.toJson(),
      },
      note: '确认后才启用。相关数据会发送至当前配置的模型服务，可能产生费用。',
    );
  }
}
