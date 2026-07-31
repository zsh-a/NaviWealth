import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/agents/agent_artifact_routes.dart';
import '../../core/auth/domain_scope.dart';
import '../../core/lifeos/life_signal.dart';
import '../../features/finance/activity/data/activity_feed_provider.dart';
import '../../features/finance/agents/providers.dart' as agents;
import '../../features/finance/cashflow/domain/budget_signal.dart';
import '../../features/finance/composition/finance_route_paths.dart';
import '../../features/finance/data/repositories/providers.dart';
import '../../features/finance/domain/models/entry_kind.dart';
import '../../features/life/data/life_events_provider.dart';

const _journalFamily = 'fin:journal_entries';
const _budgetFamily = 'fin:budgets';
const _artifactFamily = 'finance:agent_artifacts';

DomainLifeSignalSlice financeLifeSignals(Ref ref, DateTime now) {
  final events = <LifeEvent>[];
  final evaluated = <String>{};
  final periodMonth = _monthKey(now);
  final budget = ref.watch(monthlyBudgetSignalProvider(periodMonth));
  if (_settled(budget)) evaluated.add(_budgetFamily);
  final budgetSignal = _settled(budget) ? budget.value : null;
  if (budgetSignal == BudgetSignal.strained ||
      budgetSignal == BudgetSignal.overBudget) {
    events.add(
      LifeEvent(
        id: 'sig-fin-budget-$periodMonth',
        at: now,
        domain: DomainScope.finance,
        template: LifeEventTemplate.financeBudgetPressure,
        params: <String>[budgetSignal!.wire, periodMonth],
        routePath: FinanceRoutes.planBudget,
        priority: LifeSignalPriority.high,
        actionSuggestion: LifeActionSuggestion(
          template: LifeActionTemplate.reviewFinanceBudget,
          sourceRowFamily: _budgetFamily,
          sourceRowId: 'month:$periodMonth',
        ),
      ),
    );
  }

  final activity = ref.watch(activityFeedProvider);
  if (_settled(activity)) evaluated.add(_journalFamily);
  final feed = _settled(activity) ? activity.value : null;
  if (feed != null) {
    final todayStart = DateTime(now.year, now.month, now.day);
    final rows = feed.entries
        .where((row) => !row.entry.date.toLocal().isBefore(todayStart))
        .toList(growable: false);
    if (rows.isNotEmpty) {
      var expenses = 0;
      var income = 0;
      for (final row in rows) {
        final kind = classifyEntryKind(
          postings: row.postings,
          resolveCategory: (id) => feed.accountsById[id]?.category,
        ).kind;
        if (kind == EntryKind.expense) expenses++;
        if (kind == EntryKind.income) income++;
      }
      events.add(
        LifeEvent(
          id: 'sig-fin-today',
          at: now,
          domain: DomainScope.finance,
          template: LifeEventTemplate.financeDaySummary,
          params: <String>['${rows.length}', '$expenses', '$income'],
          routePath: FinanceRoutes.activity,
          actionSuggestion: LifeActionSuggestion(
            template: LifeActionTemplate.reviewFinanceActivity,
            sourceRowFamily: _journalFamily,
            sourceRowId: 'day:${_dayKey(now)}',
          ),
        ),
      );
    }
  }

  final results = ref.watch(agents.latestFinanceAgentResultsProvider);
  if (_settled(results)) evaluated.add(_artifactFamily);
  final artifacts = _settled(results) ? results.value?.artifacts : null;
  if (artifacts != null && artifacts.isNotEmpty) {
    events.add(lifeEventForAgentArtifact(artifacts.first));
  }
  return DomainLifeSignalSlice(
    events: List<LifeEvent>.unmodifiable(events),
    evaluatedSourceFamilies: Set<String>.unmodifiable(evaluated),
  );
}

String? financeSourceRoute(String family, String rowId) {
  return switch (family) {
    _journalFamily when rowId.startsWith('day:') => FinanceRoutes.activity,
    _journalFamily => FinanceRoutes.activityEntry(rowId),
    _budgetFamily => FinanceRoutes.planBudget,
    'fin:accounts' => FinanceRoutes.wealthAccount(rowId),
    'fin:assets' => FinanceRoutes.wealthAsset(rowId),
    'fin:liabilities' => FinanceRoutes.wealthLiability(rowId),
    _artifactFamily => AgentArtifactRoutes.detail(rowId),
    _ => null,
  };
}

bool _settled<T>(AsyncValue<T> value) =>
    value.hasValue && !value.hasError && !value.isLoading;

String _dayKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String _monthKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}';
}
