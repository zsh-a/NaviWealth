import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';
import '../domain/execution_models.dart';

class ListBlockedActionsTool implements DeviceTool {
  const ListBlockedActionsTool();

  @override
  String get name => 'list_blocked_actions';

  @override
  String get description =>
      '列出 ExecutionOS 中 status=blocked 的 Action。用于定位当前执行阻塞。';

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
      limit: 200,
    );
    final blocked = actions
        .where((a) => a.status == ExecutionActionStatus.blocked)
        .take(limit)
        .map(
          (a) => <String, Object?>{
            'id': a.id,
            'title': a.title,
            'note': a.note,
            'priority': a.priority.wire,
            'due_at': a.dueAt?.toUtc().toIso8601String(),
            'source_label': a.source.labelSnapshot,
          },
        )
        .toList(growable: false);
    return <String, Object?>{'actions': blocked};
  }
}
