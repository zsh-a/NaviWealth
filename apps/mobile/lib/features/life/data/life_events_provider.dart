import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/features/execution/composition/execution_route_paths.dart';
import 'package:naviwealth/features/execution/data/providers.dart'
    as execution_data;
import 'package:naviwealth/features/execution/domain/execution_models.dart';
import 'package:naviwealth/features/finance/activity/data/activity_feed_provider.dart';
import 'package:naviwealth/features/finance/agents/providers.dart'
    as finance_agent_providers;
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/domain/models/entry_kind.dart';
import 'package:naviwealth/features/health/composition/health_route_paths.dart';
import 'package:naviwealth/features/health/ui/health_today_providers.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_route_paths.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart'
    as knowledge_data;
import 'package:naviwealth/features/life/domain/life_event.dart';

/// Signal-only life feed (max 7). No raw journal / note / action rows.
final lifeEventsProvider = Provider<List<LifeEvent>>((ref) {
  final optIns = ref.watch(auth.domainOptInsProvider).value;
  bool isActive(DomainScope scope) =>
      optIns?.contains(scope) ?? scope == DomainScope.finance;

  final events = <LifeEvent>[];
  final now = DateTime.now();

  if (isActive(DomainScope.health)) {
    final out = ref.watch(recoverySignalProvider).value;
    final verdict = out?['verdict']?.toString();
    if (verdict == 'strained') {
      final score = out?['score']?.toString();
      events.add(
        LifeEvent(
          id: 'sig-recovery',
          at: now,
          domain: DomainScope.health,
          template: LifeEventTemplate.recoveryAlert,
          params: [verdict!, ?score],
          routePath: HealthRoutes.today,
          priority: LifeSignalPriority.high,
        ),
      );
    }
  }

  if (isActive(DomainScope.execution)) {
    final actions =
        ref.watch(execution_data.executionTodayActionsProvider).value ??
        const <ExecutionAction>[];
    final open =
        ref.watch(execution_data.executionOpenActionsProvider).value ?? actions;
    final blocked = open
        .where((a) => a.status == ExecutionActionStatus.blocked)
        .length;
    if (blocked > 0) {
      events.add(
        LifeEvent(
          id: 'sig-exec-blocked',
          at: now,
          domain: DomainScope.execution,
          template: LifeEventTemplate.executionBlocked,
          params: ['$blocked'],
          routePath: ExecutionRoutes.today,
          priority: LifeSignalPriority.high,
        ),
      );
    }
    final due = open.where((a) => a.isDue(now)).length;
    if (due > 0) {
      events.add(
        LifeEvent(
          id: 'sig-exec-due',
          at: now,
          domain: DomainScope.execution,
          template: LifeEventTemplate.executionDue,
          params: ['$due'],
          routePath: ExecutionRoutes.today,
          priority: LifeSignalPriority.high,
        ),
      );
    }
  }

  if (isActive(DomainScope.finance)) {
    final feed = ref.watch(activityFeedProvider).value;
    if (feed != null) {
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEntries = feed.entries
          .where((row) {
            final d = row.entry.date.toLocal();
            return !d.isBefore(todayStart);
          })
          .toList(growable: false);

      if (todayEntries.isNotEmpty) {
        var expenseCount = 0;
        var incomeCount = 0;
        for (final row in todayEntries) {
          final kind = classifyEntryKind(
            postings: row.postings,
            resolveCategory: (id) => feed.accountsById[id]?.category,
          ).kind;
          if (kind == EntryKind.expense) expenseCount += 1;
          if (kind == EntryKind.income) incomeCount += 1;
        }
        events.add(
          LifeEvent(
            id: 'sig-fin-today',
            at: now,
            domain: DomainScope.finance,
            template: LifeEventTemplate.financeDaySummary,
            params: ['${todayEntries.length}', '$expenseCount', '$incomeCount'],
            routePath: FinanceRoutes.activity,
          ),
        );
      }
    }

    final agentBundle = ref
        .watch(finance_agent_providers.latestFinanceAgentResultsProvider)
        .value;
    final artifacts = agentBundle?.artifacts;
    if (artifacts != null && artifacts.isNotEmpty) {
      final primary = artifacts.first;
      final label = primary.title.trim();
      events.add(
        LifeEvent(
          id: 'sig-agent-${primary.id}',
          at: primary.createdAt,
          domain: DomainScope.finance,
          template: LifeEventTemplate.agentResult,
          params: [label],
          routePath: FinanceRoutes.home,
        ),
      );
    }
  }

  if (isActive(DomainScope.knowledge)) {
    final notes = ref.watch(knowledge_data.knowledgeInboxNotesProvider).value;
    final count = notes?.length ?? 0;
    if (count >= 3) {
      events.add(
        LifeEvent(
          id: 'sig-know-inbox',
          at: now,
          domain: DomainScope.knowledge,
          template: LifeEventTemplate.knowledgeInbox,
          params: ['$count'],
          routePath: KnowledgeRoutes.inbox,
        ),
      );
    }
  }

  events.sort((a, b) {
    final byPriority = a.priority.index.compareTo(b.priority.index);
    if (byPriority != 0) return byPriority;
    return b.at.compareTo(a.at);
  });
  return List.unmodifiable(events.take(7));
});

/// Compact hero metrics for the Life brief (no extra I/O).
final lifeHeroSummaryProvider = Provider<LifeHeroSummary>((ref) {
  final signals = ref.watch(lifeEventsProvider);
  final packs = ref.watch(activeDomainPacksProvider);
  final high = signals
      .where((e) => e.priority == LifeSignalPriority.high)
      .length;
  final byDomain = <DomainScope, int>{};
  final highByDomain = <DomainScope, int>{};
  for (final e in signals) {
    byDomain[e.domain] = (byDomain[e.domain] ?? 0) + 1;
    if (e.priority == LifeSignalPriority.high) {
      highByDomain[e.domain] = (highByDomain[e.domain] ?? 0) + 1;
    }
  }
  return LifeHeroSummary(
    domainCount: packs.length,
    signalCount: signals.length,
    highPriorityCount: high,
    signalCountByDomain: Map.unmodifiable(byDomain),
    highCountByDomain: Map.unmodifiable(highByDomain),
  );
});

@immutable
class LifeHeroSummary {
  const LifeHeroSummary({
    required this.domainCount,
    required this.signalCount,
    required this.highPriorityCount,
    this.signalCountByDomain = const {},
    this.highCountByDomain = const {},
  });

  final int domainCount;
  final int signalCount;
  final int highPriorityCount;
  final Map<DomainScope, int> signalCountByDomain;
  final Map<DomainScope, int> highCountByDomain;

  /// Stage number: high-priority count when any, else total signals.
  int get primaryMetric =>
      highPriorityCount > 0 ? highPriorityCount : signalCount;

  bool get hasAttention => highPriorityCount > 0;

  bool get isCalm => signalCount == 0;

  int signalsFor(DomainScope scope) => signalCountByDomain[scope] ?? 0;

  int highFor(DomainScope scope) => highCountByDomain[scope] ?? 0;
}

/// Active domains for the Life workbench chips.
final lifeWorkbenchDomainsProvider = Provider<List<DomainPack>>((ref) {
  return ref.watch(activeDomainPacksProvider);
});
