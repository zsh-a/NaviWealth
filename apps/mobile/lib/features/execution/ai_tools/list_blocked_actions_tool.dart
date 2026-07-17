import 'package:naviwealth/core/ai/contracts/evidence_anchor.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';
import '../domain/execution_models.dart';
import '_read_support.dart';

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
    final projects = await repo.listActiveProjects(ownerUserId: ownerUserId);
    final commitments = await repo.listActiveCommitments(
      ownerUserId: ownerUserId,
    );
    final blockedActions = actions
        .where((a) => a.status == ExecutionActionStatus.blocked)
        .take(limit)
        .toList(growable: false);
    final blocked = blockedActions
        .map(
          (a) => <String, Object?>{
            'id': a.id,
            'title': a.title,
            'note': a.note,
            'priority': a.priority.wire,
            'due_at': a.dueAt?.toUtc().toIso8601String(),
            'project_id': a.projectId,
            'project_title': executionProjectTitle(projects, a.projectId),
            'commitment_id': a.commitmentId,
            'commitment_title': executionCommitmentTitle(
              commitments,
              a.commitmentId,
            ),
            'source_label': a.source.labelSnapshot,
          },
        )
        .toList(growable: false);
    return withEvidence(
      result: <String, Object?>{'actions': blocked},
      anchors: blockedActions
          .take(8)
          .map(
            (action) => EvidenceAnchor(
              entityTable: 'execution_actions',
              entityId: action.id,
              label: action.title,
            ),
          ),
    );
  }
}
