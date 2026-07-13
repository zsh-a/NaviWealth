import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naviwealth/core/auth/domain_scope.dart';
import 'package:naviwealth/core/auth/providers.dart' as auth;
import 'package:naviwealth/core/lifeos/domain_pack.dart';
import 'package:naviwealth/features/execution/composition/execution_route_paths.dart';
import 'package:naviwealth/features/execution/data/providers.dart'
    as execution_data;
import 'package:naviwealth/features/finance/activity/data/activity_feed_provider.dart';
import 'package:naviwealth/features/finance/application/read_models/dashboard_providers.dart';
import 'package:naviwealth/features/finance/composition/finance_route_paths.dart';
import 'package:naviwealth/features/health/composition/health_route_paths.dart';
import 'package:naviwealth/features/health/ui/health_today_providers.dart';
import 'package:naviwealth/features/knowledge/composition/knowledge_route_paths.dart';
import 'package:naviwealth/features/knowledge/data/providers.dart'
    as knowledge_data;
import 'package:naviwealth/features/life/domain/life_event.dart';

/// Aggregates recent cross-domain signals into a single timeline.
///
/// Soft-fail per domain: inactive opt-ins or load errors simply omit that
/// domain's rows so the Life hub stays usable. Copy is localized in the UI
/// via [LifeEvent.template].
final lifeEventsProvider = Provider<List<LifeEvent>>((ref) {
  final optIns = ref.watch(auth.domainOptInsProvider).value;
  bool isActive(DomainScope scope) =>
      optIns?.contains(scope) ?? scope == DomainScope.finance;

  final events = <LifeEvent>[];

  if (isActive(DomainScope.finance)) {
    final snap = ref.watch(dashboardSnapshotProvider).value;
    if (snap != null && !snap.isEmpty) {
      events.add(
        LifeEvent(
          id: 'fin-networth',
          at: DateTime.now(),
          domain: DomainScope.finance,
          template: LifeEventTemplate.netWorth,
          params: [snap.baseCurrency],
          routePath: FinanceRoutes.home,
          kind: LifeEventKind.finance,
        ),
      );
    }

    final feed = ref.watch(activityFeedProvider).value;
    if (feed != null) {
      for (final row in feed.entries.take(5)) {
        final entry = row.entry;
        final title = entry.narration.trim().isEmpty
            ? (entry.payee?.trim().isNotEmpty == true
                  ? entry.payee!.trim()
                  : entry.id)
            : entry.narration.trim();
        events.add(
          LifeEvent(
            id: 'fin-act-${entry.id}',
            at: entry.date,
            domain: DomainScope.finance,
            template: LifeEventTemplate.financeActivity,
            title: title,
            routePath: FinanceRoutes.activityEntry(entry.id),
            kind: LifeEventKind.finance,
          ),
        );
      }
    }
  }

  if (isActive(DomainScope.health)) {
    final out = ref.watch(recoverySignalProvider).value;
    if (out != null) {
      final verdict = out['verdict']?.toString() ?? 'insufficient_data';
      final score = out['score']?.toString();
      events.add(
        LifeEvent(
          id: 'health-recovery',
          at: DateTime.now(),
          domain: DomainScope.health,
          template: LifeEventTemplate.recovery,
          params: [verdict, ?score],
          routePath: HealthRoutes.today,
          kind: LifeEventKind.health,
        ),
      );
    }
  }

  if (isActive(DomainScope.knowledge)) {
    final notes = ref.watch(knowledge_data.knowledgeInboxNotesProvider).value;
    if (notes != null) {
      for (final note in notes.take(3)) {
        events.add(
          LifeEvent(
            id: 'know-${note.id}',
            at: note.createdAt,
            domain: DomainScope.knowledge,
            template: LifeEventTemplate.knowledgeCapture,
            title: note.title.trim(),
            routePath: KnowledgeRoutes.inbox,
            kind: LifeEventKind.knowledge,
          ),
        );
      }
    }
  }

  if (isActive(DomainScope.execution)) {
    final actions = ref
        .watch(execution_data.executionTodayActionsProvider)
        .value;
    if (actions != null) {
      for (final action in actions.take(4)) {
        events.add(
          LifeEvent(
            id: 'exec-${action.id}',
            at: action.createdAt,
            domain: DomainScope.execution,
            template: LifeEventTemplate.executionAction,
            title: action.title,
            params: [action.status.name],
            routePath: ExecutionRoutes.action(action.id),
            kind: LifeEventKind.execution,
          ),
        );
      }
    }
  }

  events.sort((a, b) => b.at.compareTo(a.at));
  return List.unmodifiable(events.take(16));
});

/// Active domains for the Life workbench grid.
final lifeWorkbenchDomainsProvider = Provider<List<DomainPack>>((ref) {
  return ref.watch(activeDomainPacksProvider);
});
