import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:naviwealth/core/ai/agents/agent_run_store.dart';
import 'package:naviwealth/core/sync/hlc.dart';
import 'package:naviwealth/core/sync/sync_meta.dart';
import 'package:naviwealth/core/time/current_time_provider.dart';
import 'package:naviwealth/features/execution/data/providers.dart';
import 'package:naviwealth/features/execution/domain/execution_models.dart';
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
    id: 'knowledge:focus-window',
    title: '将深度工作留给上午',
    bodyMd: '连续两周的复盘都显示，上午通常是最稳定的专注窗口。',
    tags: const <String>['focus', 'work'],
    createdAt: _domainShowcaseNow.subtract(const Duration(hours: 2)),
    sync: _domainShowcaseSync,
  ),
  KnowledgeNote(
    id: 'knowledge:cash-buffer',
    title: '现金缓冲是否需要提高到 12 个月？',
    bodyMd: '结合 FIRE 状态与未来一年的家庭计划，在月度复盘中验证这一假设。',
    tags: const <String>['finance', 'planning'],
    createdAt: _domainShowcaseNow.subtract(const Duration(days: 1)),
    sync: _domainShowcaseSync,
  ),
  KnowledgeNote(
    id: 'knowledge:weekly-review',
    title: '每周日连接健康、财富与行动复盘',
    bodyMd: '只保留需要决策的信号，并把结论转成下周行动。',
    tags: const <String>['lifeos', 'review'],
    createdAt: _domainShowcaseNow.subtract(const Duration(days: 2)),
    sync: _domainShowcaseSync,
  ),
];

final _executionPlan = ExecutionPlan(
  id: 'execution:plan',
  title: '完成季度 LifeOS 复盘',
  description: '连接健康、财富与执行数据',
  horizon: ExecutionHorizon.quarter,
  createdAt: _domainShowcaseNow.subtract(const Duration(days: 20)),
  sync: _domainShowcaseSync,
);

final _executionActions = <ExecutionAction>[
  ExecutionAction(
    id: 'execution:review',
    title: '整理本周复盘中的三个关键信号',
    note: '只保留会改变下一步行动的信息。',
    priority: ExecutionPriority.high,
    status: ExecutionActionStatus.doing,
    planId: _executionPlan.id,
    createdAt: _domainShowcaseNow.subtract(const Duration(days: 2)),
    sync: _domainShowcaseSync,
  ),
  ExecutionAction(
    id: 'execution:plan',
    title: '安排下周的深度工作时间块',
    priority: ExecutionPriority.normal,
    planId: _executionPlan.id,
    createdAt: _domainShowcaseNow.subtract(const Duration(days: 1)),
    sync: _domainShowcaseSync,
  ),
];

List<Override> readmeDomainShowcaseOverrides() => <Override>[
  currentTimeProvider.overrideWithBuild((_, _) => _domainShowcaseNow),
  knowledgeDueReviewsProvider.overrideWith(
    (_) => Stream.value(const <KnowledgeDecision>[]),
  ),
  healthHasAnyDataProvider.overrideWith((_) async => true),
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
  knowledgeNotesProvider.overrideWith(
    (_) => Stream<List<KnowledgeNote>>.value(_knowledgeNotes),
  ),
  executionTodayActionsProvider.overrideWith(
    (_) => Stream<List<ExecutionAction>>.value(_executionActions),
  ),
  executionOpenActionsProvider.overrideWith(
    (_) => Stream<List<ExecutionAction>>.value(_executionActions),
  ),
  executionPlansProvider.overrideWith(
    (_) => Stream<List<ExecutionPlan>>.value(<ExecutionPlan>[_executionPlan]),
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
      plans: <String, ExecutionPlan>{_executionPlan.id: _executionPlan},
    ),
  ),
];
