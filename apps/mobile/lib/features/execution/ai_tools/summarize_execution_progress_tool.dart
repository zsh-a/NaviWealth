import 'package:naviwealth/core/ai/contracts/evidence_anchor.dart';
import 'package:naviwealth/core/ai/runtime/device/tools/device_tool.dart';
import 'package:naviwealth/core/auth/current_user.dart';

import '../data/providers.dart';
import '../domain/execution_models.dart';
import '_read_support.dart';

class SummarizeExecutionProgressTool implements DeviceTool {
  const SummarizeExecutionProgressTool();

  @override
  String get name => 'summarize_execution_progress';

  @override
  String get description =>
      '汇总近期 ExecutionOS 进展:open actions 数量、blocked 数量、active projects/commitments 数量、'
      '最近 progress entries。用于周复盘和执行状态总结。';

  @override
  Map<String, Object?> get inputSchema => <String, Object?>{
    'type': 'object',
    'properties': {
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 100, 'default': 20},
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
        ? (input['limit'] as num).toInt().clamp(1, 100)
        : 20;
    final actions = await repo.listOpenActions(ownerUserId: ownerUserId);
    final projects = await repo.listActiveProjects(ownerUserId: ownerUserId);
    final commitments = await repo.listActiveCommitments(
      ownerUserId: ownerUserId,
    );
    final progress = await repo.listRecentProgress(
      ownerUserId: ownerUserId,
      limit: limit,
    );
    return withEvidence(
      result: <String, Object?>{
        'open_action_count': actions.length,
        'blocked_action_count': actions
            .where((a) => a.status == ExecutionActionStatus.blocked)
            .length,
        'active_project_count': projects.length,
        'active_commitment_count': commitments.length,
        'active_projects': projects
            .map(executionProjectJson)
            .take(20)
            .toList(growable: false),
        'active_commitments': commitments
            .map(
              (commitment) =>
                  executionCommitmentJson(commitment, projects: projects),
            )
            .take(20)
            .toList(growable: false),
        'recent_progress': progress
            .map(
              (p) => <String, Object?>{
                'id': p.id,
                'action_id': p.actionId,
                'project_id': p.projectId,
                'project_title': executionProjectTitle(projects, p.projectId),
                'commitment_id': p.commitmentId,
                'commitment_title': executionCommitmentTitle(
                  commitments,
                  p.commitmentId,
                ),
                'kind': p.kind.wire,
                'note': p.note,
                'created_at': p.createdAt.toUtc().toIso8601String(),
              },
            )
            .toList(growable: false),
      },
      anchors: <EvidenceAnchor>[
        for (final action in actions.take(4))
          EvidenceAnchor(
            entityTable: 'execution_actions',
            entityId: action.id,
            label: action.title,
          ),
        for (final entry in progress.take(4))
          EvidenceAnchor(
            entityTable: 'execution_progress',
            entityId: entry.id,
            label: entry.note,
          ),
      ],
    );
  }
}
