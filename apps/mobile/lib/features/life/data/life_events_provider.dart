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
import 'package:naviwealth/features/finance/cashflow/domain/budget_signal.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/finance/data/repositories/providers.dart';
import 'package:naviwealth/features/finance/domain/models/entry_kind.dart';
import 'package:naviwealth/features/health/composition/health_route_paths.dart';
import 'package:naviwealth/features/health/ui/health_today_providers.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_route_paths.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart'
    as knowledge_data;
import 'package:naviwealth/features/life/domain/life_event.dart';

const String kLifeHealthMetricSourceFamily = 'health:health_metrics';
const String kLifeFinanceJournalSourceFamily = 'fin:journal_entries';
const String kLifeFinanceBudgetSourceFamily = 'fin:budgets';
const String kLifeAgentArtifactSourceFamily = 'agent_artifacts';
const String kLifeKnowledgeNoteSourceFamily = 'know:knowledge_notes';

/// Complete candidate observation used by both the Life feed and deterministic
/// Action outcome comparison. No raw journal / note / action rows are exposed.
final lifeSignalSnapshotProvider = Provider<LifeSignalSnapshot>((ref) {
  final optIns = ref.watch(auth.domainOptInsProvider).value;
  bool isActive(DomainScope scope) =>
      optIns?.contains(scope) ?? scope == DomainScope.finance;

  final events = <LifeEvent>[];
  final evaluatedSourceFamilies = <String>{};
  final now = DateTime.now().toUtc();

  if (isActive(DomainScope.health)) {
    final recovery = ref.watch(recoverySignalProvider);
    if (_isSettledValue(recovery)) {
      evaluatedSourceFamilies.add(kLifeHealthMetricSourceFamily);
    }
    final out = _isSettledValue(recovery) ? recovery.value : null;
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
          actionSuggestion: LifeActionSuggestion(
            template: LifeActionTemplate.protectRecovery,
            sourceRowFamily: kLifeHealthMetricSourceFamily,
            sourceRowId: 'recovery:${_dayKey(now)}',
          ),
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
    final periodMonth = _monthKey(now);
    final budget = ref.watch(monthlyBudgetSignalProvider(periodMonth));
    if (_isSettledValue(budget)) {
      evaluatedSourceFamilies.add(kLifeFinanceBudgetSourceFamily);
    }
    final budgetSignal = _isSettledValue(budget) ? budget.value : null;
    if (budgetSignal == BudgetSignal.strained ||
        budgetSignal == BudgetSignal.overBudget) {
      events.add(
        LifeEvent(
          id: 'sig-fin-budget-$periodMonth',
          at: now,
          domain: DomainScope.finance,
          template: LifeEventTemplate.financeBudgetPressure,
          params: [budgetSignal!.wire, periodMonth],
          routePath: FinanceRoutes.planBudget,
          priority: LifeSignalPriority.high,
          actionSuggestion: LifeActionSuggestion(
            template: LifeActionTemplate.reviewFinanceBudget,
            sourceRowFamily: kLifeFinanceBudgetSourceFamily,
            sourceRowId: 'month:$periodMonth',
          ),
        ),
      );
    }

    final activity = ref.watch(activityFeedProvider);
    if (_isSettledValue(activity)) {
      evaluatedSourceFamilies.add(kLifeFinanceJournalSourceFamily);
    }
    final feed = _isSettledValue(activity) ? activity.value : null;
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
            actionSuggestion: LifeActionSuggestion(
              template: LifeActionTemplate.reviewFinanceActivity,
              sourceRowFamily: kLifeFinanceJournalSourceFamily,
              sourceRowId: 'day:${_dayKey(now)}',
            ),
          ),
        );
      }
    }

    final agentResults = ref.watch(
      finance_agent_providers.latestFinanceAgentResultsProvider,
    );
    if (_isSettledValue(agentResults)) {
      evaluatedSourceFamilies.add(kLifeAgentArtifactSourceFamily);
    }
    final agentBundle = _isSettledValue(agentResults)
        ? agentResults.value
        : null;
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
          actionSuggestion: LifeActionSuggestion(
            template: LifeActionTemplate.reviewAgentInsight,
            sourceRowFamily: kLifeAgentArtifactSourceFamily,
            sourceRowId: primary.id,
          ),
        ),
      );
    }
  }

  if (isActive(DomainScope.knowledge)) {
    final inboxNotes = ref.watch(knowledge_data.knowledgeInboxNotesProvider);
    if (_isSettledValue(inboxNotes)) {
      evaluatedSourceFamilies.add(kLifeKnowledgeNoteSourceFamily);
    }
    final notes = _isSettledValue(inboxNotes) ? inboxNotes.value : null;
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
          actionSuggestion: const LifeActionSuggestion(
            template: LifeActionTemplate.reviewKnowledgeInbox,
            sourceRowFamily: kLifeKnowledgeNoteSourceFamily,
            sourceRowId: 'inbox',
          ),
        ),
      );
    }
  }

  events.sort((a, b) {
    final byPriority = a.priority.index.compareTo(b.priority.index);
    if (byPriority != 0) return byPriority;
    return b.at.compareTo(a.at);
  });
  return LifeSignalSnapshot(
    observedAt: now,
    events: List.unmodifiable(events),
    evaluatedSourceFamilies: Set.unmodifiable(evaluatedSourceFamilies),
  );
});

/// Signal-only Life feed candidates. Outcome evaluation consumes the snapshot
/// above so loading/error absence can never masquerade as a cleared signal.
final lifeEventCandidatesProvider = Provider<List<LifeEvent>>((ref) {
  return ref.watch(lifeSignalSnapshotProvider).events;
});

/// Bounded signal set rendered by the Life hub. Outcome evaluation uses the
/// complete candidate set above so a lower-ranked active signal is never
/// mistaken for a cleared outcome merely because the UI shows seven rows.
final lifeEventsProvider = Provider<List<LifeEvent>>((ref) {
  return List.unmodifiable(ref.watch(lifeEventCandidatesProvider).take(7));
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

String _dayKey(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

String _monthKey(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  return '${local.year}-$month';
}

bool _isSettledValue<T>(AsyncValue<T> value) =>
    value.hasValue && !value.hasError && !value.isLoading;
