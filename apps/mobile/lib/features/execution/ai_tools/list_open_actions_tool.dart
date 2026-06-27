import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';
import '../domain/execution_models.dart';

class ListOpenActionsTool implements DeviceTool {
  const ListOpenActionsTool();

  @override
  String get name => 'list_open_actions';

  @override
  String get description =>
      '列出 ExecutionOS 中尚未完成的 Action(todo/doing/blocked)。'
      '用于回答「我现在有哪些 todo / 下一步 / 阻塞项」。可选 limit。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 200, 'default': 50},
    },
  };

  @override
  Future<Object?> invoke(
    DeviceToolContext ctx,
    Map<String, Object?> input,
  ) async {
    final repo = await ctx.ref.read(executionRepositoryProvider.future);
    final ownerUserId = await ctx.ref.read(currentUserIdProvider)();
    final limit = (input['limit'] is num)
        ? (input['limit'] as num).toInt().clamp(1, 200)
        : 50;
    final actions = await repo.listOpenActions(
      ownerUserId: ownerUserId,
      limit: limit,
    );
    return <String, Object?>{
      'actions': actions.map(_actionJson).toList(growable: false),
    };
  }
}

Map<String, Object?> _actionJson(ExecutionAction a) => <String, Object?>{
  'id': a.id,
  'title': a.title,
  'note': a.note,
  'status': a.status.wire,
  'priority': a.priority.wire,
  'due_at': a.dueAt?.toUtc().toIso8601String(),
  'scheduled_for': a.scheduledFor?.toUtc().toIso8601String(),
  'project_id': a.projectId,
  'commitment_id': a.commitmentId,
  'source_domain': a.source.domain,
  'source_row_family': a.source.rowFamily,
  'source_row_id': a.source.rowId,
  'source_label': a.source.labelSnapshot,
  'created_at': a.createdAt.toUtc().toIso8601String(),
};
