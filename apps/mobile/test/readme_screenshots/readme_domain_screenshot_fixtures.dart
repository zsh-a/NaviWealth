import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:naviwealth/core/ai/agents/agent_artifact.dart';
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/ai/contracts/memory_record.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/health/agents/morning_briefing_agent.dart';
import 'package:naviwealth/features/health/agents/providers.dart'
    as health_agent_providers;
import 'package:naviwealth/features/health/data/garmin/garmin_sync_controller.dart';
import 'package:naviwealth/features/health/data/providers.dart' as health_data;
import 'package:naviwealth/features/health/ui/health_today_providers.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart';
import 'package:naviwealth/features/knowledge/domain/knowledge_models.dart';

final _domainShowcaseNow = DateTime.utc(2026, 7, 12, 9, 30);

final _domainShowcaseSync = SyncMeta(
  ownerUserId: 'readme-user',
  updatedAt: _domainShowcaseNow,
  updatedByDevice: 'readme-device',
  hlc: const Hlc(
    wallMillis: 1783829400000,
    counter: 0,
    nodeId: 'readme-device',
  ),
);

final _knowledgeNotes = <KnowledgeNote>[
  KnowledgeNote(
    id: 'knowledge:decision',
    title: '将深度工作留给上午',
    bodyMd: '连续两周的复盘都显示，上午通常是最稳定的专注窗口。',
    tags: const <String>['kind:principle_candidate', 'focus'],
    projectTag: 'LifeOS',
    createdAt: _domainShowcaseNow.subtract(const Duration(hours: 2)),
    sync: _domainShowcaseSync,
  ),
  KnowledgeNote(
    id: 'knowledge:assumption',
    title: '现金缓冲是否需要提高到 12 个月？',
    bodyMd: '结合 FIRE 状态与未来一年的家庭计划，在月度复盘中验证这一假设。',
    tags: const <String>['kind:assumption_candidate', 'finance'],
    projectTag: '年度规划',
    createdAt: _domainShowcaseNow.subtract(const Duration(days: 1)),
    sync: _domainShowcaseSync,
  ),
  KnowledgeNote(
    id: 'knowledge:routine',
    title: '每周日连接健康、财富与行动复盘',
    bodyMd: '只保留需要决策的信号，并把结论转成下周行动。',
    tags: const <String>['kind:routine_candidate', 'review'],
    createdAt: _domainShowcaseNow.subtract(const Duration(days: 2)),
    sync: _domainShowcaseSync,
  ),
];

final _executionProject = ExecutionProject(
  id: 'execution:project',
  title: '完成季度 LifeOS 复盘',
  description: '连接健康、财富与执行数据',
  horizon: ExecutionHorizon.quarter,
  createdAt: _domainShowcaseNow.subtract(const Duration(days: 20)),
  sync: _domainShowcaseSync,
);

final _executionCommitment = ExecutionCommitment(
  id: 'execution:commitment',
  title: '每周保留两个深度工作时段',
  horizon: ExecutionHorizon.week,
  createdAt: _domainShowcaseNow.subtract(const Duration(days: 30)),
  sync: _domainShowcaseSync,
);

final _executionActions = <ExecutionAction>[
  ExecutionAction(
    id: 'execution:review',
    title: '整理本周复盘中的三个关键信号',
    note: '只保留会改变下一步行动的信息。',
    priority: ExecutionPriority.high,
    status: ExecutionActionStatus.doing,
    projectId: _executionProject.id,
    commitmentId: _executionCommitment.id,
    createdAt: _domainShowcaseNow.subtract(const Duration(days: 2)),
    sync: _domainShowcaseSync,
  ),
  ExecutionAction(
    id: 'execution:plan',
    title: '安排下周的深度工作时间块',
    priority: ExecutionPriority.normal,
    projectId: _executionProject.id,
    commitmentId: _executionCommitment.id,
    createdAt: _domainShowcaseNow.subtract(const Duration(days: 1)),
    sync: _domainShowcaseSync,
  ),
];

final _morningBriefing = AgentArtifact(
  id: 'health:morning-briefing',
  ownerUserId: 'readme-user',
  agentId: kMorningBriefingAgentId,
  domain: 'health',
  kind: AgentArtifactKind.briefing,
  severity: AgentArtifactSeverity.info,
  title: '晨间简报',
  summary: '恢复状态稳定。今天适合正常训练，并把最需要专注的工作放在上午。',
  insights: const <AgentInsight>[
    AgentInsight(title: '恢复趋势稳定', body: '睡眠与 HRV 保持在个人基线附近。'),
  ],
  evidence: const <AgentEvidenceRef>[
    AgentEvidenceRef(type: 'health_metric', id: 'health:hrv'),
  ],
  createdAt: _domainShowcaseNow,
);

List<Override> readmeDomainShowcaseOverrides() => <Override>[
  health_data.garminSyncControllerProvider.overrideWithBuild(
    (_, _) => const GarminInitial(),
  ),
  healthTodayMetricGridProvider.overrideWith(
    (_) async => HealthTodayMetricGridModel.empty(),
  ),
  recoverySignalProvider.overrideWith(
    (_) async => <String, Object?>{'score': 82, 'verdict': 'rested'},
  ),
  recoverySparklineProvider.overrideWith(
    (_) async => const <double>[48, 52, 50, 55, 57, 54, 59],
  ),
  weeklySummaryProvider.overrideWith((_) async => null),
  health_agent_providers.latestMorningBriefingProvider.overrideWith(
    (_) async => null as MemoryRecord?,
  ),
  health_agent_providers.latestMorningBriefingArtifactProvider.overrideWith(
    (_) async => _morningBriefing,
  ),
  health_agent_providers.latestRecoveryAlertArtifactProvider.overrideWith(
    (_) async => null,
  ),
  health_agent_providers.latestRecoveryAlertRunProvider.overrideWith(
    (_) async => null,
  ),
  health_agent_providers.latestWeeklySummaryArtifactProvider.overrideWith(
    (_) async => null,
  ),
  health_agent_providers.latestWeeklySummaryRunProvider.overrideWith(
    (_) async => null as AgentRunRecord?,
  ),
  knowledgeInboxNotesProvider.overrideWith(
    (_) => Stream<List<KnowledgeNote>>.value(_knowledgeNotes),
  ),
  executionTodayActionsProvider.overrideWith(
    (_) => Stream<List<ExecutionAction>>.value(_executionActions),
  ),
  executionOpenActionsProvider.overrideWith(
    (_) => Stream<List<ExecutionAction>>.value(_executionActions),
  ),
  executionProjectsProvider.overrideWith(
    (_) => Stream<List<ExecutionProject>>.value(<ExecutionProject>[
      _executionProject,
    ]),
  ),
  executionCommitmentsProvider.overrideWith(
    (_) => Stream<List<ExecutionCommitment>>.value(<ExecutionCommitment>[
      _executionCommitment,
    ]),
  ),
  executionRecentProgressProvider.overrideWith(
    (_) => Stream<List<ExecutionProgressEntry>>.value(
      const <ExecutionProgressEntry>[],
    ),
  ),
  executionActionRelationsProvider.overrideWith(
    (_) async => ExecutionRelations(
      actions: <String, ExecutionAction>{
        for (final action in _executionActions) action.id: action,
      },
      projects: <String, ExecutionProject>{
        _executionProject.id: _executionProject,
      },
      commitments: <String, ExecutionCommitment>{
        _executionCommitment.id: _executionCommitment,
      },
    ),
  ),
];
