/// KnowledgeOS Review tab (`docs/domains/knowledgeos-domain.md` §5).
///
/// 3 cards: due Routines (next_due_at within 7d), due Decisions
/// (review_date passed) and stale Assumptions (active && > 90d
/// unverified). Forui chrome with widget-layer pull-to-refresh.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_artifact_routes.dart';
import '../../../core/ai/agents/agent_finding_store.dart';
import '../../../core/ai/agents/agent_run_controller.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/ai/agents/ui/agent_result_card.dart';
import '../../../core/ai/agents/ui/agent_results_panel.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/auth/domain_scope.dart';
import '../../../core/auth/providers.dart' as core_auth;
import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../agents/providers.dart' as knowledge_agent_providers;
import '../application/knowledge_lifecycle_service.dart';
import '../composition/knowledge_route_paths.dart';
import '../data/inbox_triage_repository.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_ai_suggestions_card.dart';
import '_decision_lifecycle_sheet.dart';
import '_widgets.dart';
import 'knowledge_object_detail_page.dart';

part 'knowledge_review_assumptions.dart';
part 'knowledge_review_decisions.dart';
part 'knowledge_review_routines.dart';
part 'knowledge_review_selection.dart';

const int _kDecisionReviewRescheduleDays = 90;
const Duration kRoutineDueLookahead = Duration(days: 7);
const String _kReviewRoutineOrderPrefsKey = 'routine_order';
const String _kReviewDecisionOrderPrefsKey = 'decision_order';
const String _kReviewAssumptionOrderPrefsKey = 'assumption_order';

String _reviewOrderPrefsKey(WidgetRef ref, String family) {
  final owner = ref.read(activeUserIdProvider) ?? kLocalOnlyUserId;
  return 'knowledge.$owner.review.$family.v2';
}

final _reviewActionsRefreshProvider = StateProvider<int>((ref) => 0);

/// A single read model for the Review surface.
///
/// Review used to let every card resolve its own repository/future/stream.
/// That made the page appear in pieces and, more importantly, allowed the
/// empty state to disagree with the agent and finding stores. Keeping the
/// queue in one snapshot gives the page one loading/error grammar and one
/// source of truth for the attention count.
class KnowledgeReviewSnapshot {
  const KnowledgeReviewSnapshot({
    required this.ownerUserId,
    required this.dueRoutines,
    required this.dueDecisions,
    required this.staleAssumptions,
    required this.pendingSuggestions,
    required this.suggestionNotes,
    required this.agentResults,
    required this.findings,
  });

  final String ownerUserId;
  final List<KnowledgeRoutine> dueRoutines;
  final List<KnowledgeDecision> dueDecisions;
  final List<KnowledgeAssumption> staleAssumptions;
  final List<InboxTriageRecord> pendingSuggestions;
  final Map<String, KnowledgeNote?> suggestionNotes;
  final agent_providers.AgentResultBundle agentResults;
  final List<StoredAgentFinding> findings;

  int get pendingSuggestionCount => pendingSuggestions.fold(
    0,
    (total, record) => total + record.pending.length,
  );

  int get attentionCount =>
      dueRoutines.length +
      dueDecisions.length +
      staleAssumptions.length +
      pendingSuggestionCount +
      findings.length;

  bool get isEmpty =>
      attentionCount == 0 && agentResults.visibleEntries.isEmpty;
}

final knowledgeReviewSnapshotProvider =
    FutureProvider.autoDispose<KnowledgeReviewSnapshot>((ref) async {
      ref.watch(_reviewActionsRefreshProvider);
      ref.watch(aiSuggestionsRefreshProvider);
      // Resolve every provider dependency before the first async gap. An
      // auto-disposed snapshot can be invalidated while a repository is
      // opening; calling ref.watch/read after that gap would use a disposed
      // Ref and turn a normal refresh/navigation into an uncaught error.
      final ownerFuture = ref.watch(knowledgeOwnerUserIdProvider.future);
      final repoFuture = ref.watch(knowledgeRepositoryProvider.future);
      final triageFuture = ref.watch(inboxTriageRepositoryProvider.future);
      final optIns = ref.watch(core_auth.domainOptInsProvider).value;
      final agentResultsFuture = ref.watch(
        knowledge_agent_providers.latestKnowledgeReviewResultsProvider.future,
      );
      final findingStoreFuture = optIns?.contains(DomainScope.knowledge) == true
          ? ref.watch(agent_providers.agentFindingStoreProvider.future)
          : null;

      final owner = await ownerFuture;
      final repo = await repoFuture;
      final triage = await triageFuture;
      final now = DateTime.now();
      final findingsFuture = findingStoreFuture == null
          ? Future.value(const <StoredAgentFinding>[])
          : findingStoreFuture.then(
              (store) => store.listOpen(
                ownerUserId: owner,
                domain: 'knowledge',
                limit: 100,
              ),
            );

      // Start all independent reads together. The page should wait once for a
      // coherent snapshot instead of revealing one section at a time.
      final values = await Future.wait<Object>([
        repo.listDueRoutines(
          ownerUserId: owner,
          asOf: now.add(kRoutineDueLookahead),
        ),
        repo.listDueReviews(ownerUserId: owner, asOf: now.toUtc()),
        repo.listOpenAssumptions(ownerUserId: owner),
        triage.listPending(ownerUserId: owner),
        agentResultsFuture,
        findingsFuture,
      ]);

      final dueRoutines = (values[0] as List<KnowledgeRoutine>)
          .where((routine) => shouldShowRoutineInReview(routine, now))
          .toList(growable: false);
      final dueDecisions = values[1] as List<KnowledgeDecision>;
      final openAssumptions = values[2] as List<KnowledgeAssumption>;
      final staleAssumptions = openAssumptions
          .where(
            (assumption) =>
                assumption.daysSinceVerify(now.toUtc()) >=
                kKnowledgeAssumptionStaleDays,
          )
          .toList(growable: false);
      final pendingSuggestions = (values[3] as List<InboxTriageRecord>)
          .where((record) => record.pending.isNotEmpty)
          .toList(growable: false);
      final noteEntries = await Future.wait(
        pendingSuggestions.map(
          (record) async => MapEntry(
            record.noteId,
            await repo.findNote(ownerUserId: owner, id: record.noteId),
          ),
        ),
      );
      final suggestionNotes = <String, KnowledgeNote?>{
        for (final entry in noteEntries) entry.key: entry.value,
      };

      return KnowledgeReviewSnapshot(
        ownerUserId: owner,
        dueRoutines: dueRoutines,
        dueDecisions: dueDecisions,
        staleAssumptions: staleAssumptions,
        pendingSuggestions: pendingSuggestions,
        suggestionNotes: Map<String, KnowledgeNote?>.unmodifiable(
          suggestionNotes,
        ),
        agentResults: values[4] as agent_providers.AgentResultBundle,
        findings: values[5] as List<StoredAgentFinding>,
      );
    });

@visibleForTesting
bool shouldShowRoutineInReview(
  KnowledgeRoutine routine,
  DateTime now, {
  Duration lookahead = kRoutineDueLookahead,
}) {
  if (routine.status != RoutineStatus.active) return false;
  final doneAt = routine.lastDoneAt;
  if (doneAt != null && _isSameLocalDay(doneAt, now)) return false;
  return !routine.nextDueAt.toUtc().isAfter(now.add(lookahead).toUtc());
}

bool _isSameLocalDay(DateTime a, DateTime b) {
  final localA = a.toLocal();
  final localB = b.toLocal();
  return localA.year == localB.year &&
      localA.month == localB.month &&
      localA.day == localB.day;
}

List<T> _orderedReviewItems<T>({
  required List<T> items,
  required List<String> order,
  required String Function(T item) idOf,
}) {
  final indexById = <String, int>{
    for (var i = 0; i < order.length; i++) order[i]: i,
  };
  final out = List<T>.of(items);
  out.sort((a, b) {
    final ai = indexById[idOf(a)];
    final bi = indexById[idOf(b)];
    if (ai == null && bi == null) return 0;
    if (ai == null) return 1;
    if (bi == null) return -1;
    return ai.compareTo(bi);
  });
  return out;
}

Future<void> _persistReviewOrder({
  required WidgetRef ref,
  required String prefsKey,
  required List<String> visibleIds,
}) async {
  final prefs = ref.read(sharedPreferencesProvider);
  final stored = prefs.getStringList(prefsKey) ?? const <String>[];
  final visible = visibleIds.toSet();
  await prefs.setStringList(prefsKey, <String>[
    ...visibleIds,
    for (final id in stored)
      if (!visible.contains(id)) id,
  ]);
  ref.read(_reviewActionsRefreshProvider.notifier).state++;
}

class KnowledgeReviewPage extends ConsumerStatefulWidget {
  const KnowledgeReviewPage({super.key});

  @override
  ConsumerState<KnowledgeReviewPage> createState() =>
      _KnowledgeReviewPageState();
}

class _KnowledgeReviewPageState extends ConsumerState<KnowledgeReviewPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reviewAsync = ref.watch(knowledgeReviewSnapshotProvider);
    return ShellTabScaffold(
      title: l10n.knowledgeReviewTitle,
      child: ShellTabPause(
        routePath: KnowledgeRoutes.review,
        child: AppAtmosphere(
          child: AppRefreshIndicator(
            onRefresh: () => _refreshReview(ref),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: shellTabContentPadding(context, top: AppSpacing.s8),
              children: <Widget>[
                reviewAsync.when(
                  loading: () => const _KnowledgeReviewLoadingState(),
                  error: (error, stackTrace) => Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.s8),
                    child: AppEmptyState.inline(
                      icon: FLucideIcons.refreshCw,
                      title: userSafeErrorMessage(
                        context,
                        error,
                        stackTrace: stackTrace,
                        operation: 'load knowledge review',
                      ),
                      tone: AppEmptyStateTone.error,
                      retryLabel: l10n.commonRetry,
                      onRetry: () =>
                          ref.invalidate(knowledgeReviewSnapshotProvider),
                    ),
                  ),
                  data: (snapshot) =>
                      _KnowledgeReviewContent(snapshot: snapshot),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KnowledgeReviewLoadingState extends StatelessWidget {
  const _KnowledgeReviewLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        KnowledgeSectionSkeleton(),
        SizedBox(height: AppSpacing.s12),
        KnowledgeSectionSkeleton(),
        SizedBox(height: AppSpacing.s12),
        KnowledgeSectionSkeleton(),
      ],
    );
  }
}

class _KnowledgeReviewContent extends StatelessWidget {
  const _KnowledgeReviewContent({required this.snapshot});

  final KnowledgeReviewSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[];
    if (snapshot.attentionCount > 0) {
      sections.add(_KnowledgeReviewOverview(snapshot: snapshot));
    }
    if (snapshot.agentResults.visibleEntries.isNotEmpty) {
      sections.add(_KnowledgeReviewAgentResults(bundle: snapshot.agentResults));
    }
    if (snapshot.pendingSuggestions.isNotEmpty) {
      sections.add(
        KnowledgeAiSuggestionsCard(
          records: snapshot.pendingSuggestions,
          notesById: snapshot.suggestionNotes,
        ),
      );
    }
    if (snapshot.findings.isNotEmpty) {
      sections.add(_KnowledgeReviewFindingsCard(findings: snapshot.findings));
    }
    if (snapshot.dueRoutines.isNotEmpty) {
      sections.add(_DueRoutinesCard(routines: snapshot.dueRoutines));
    }
    if (snapshot.dueDecisions.isNotEmpty) {
      sections.add(_DueReviewsCard(decisions: snapshot.dueDecisions));
    }
    if (snapshot.staleAssumptions.isNotEmpty) {
      sections.add(
        _StaleAssumptionsCard(assumptions: snapshot.staleAssumptions),
      );
    }
    if (snapshot.isEmpty) {
      sections.add(const _KnowledgeReviewCompleteState());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < sections.length; index++) ...[
          if (index > 0) const SizedBox(height: AppSpacing.s12),
          sections[index],
        ],
      ],
    );
  }
}

class _KnowledgeReviewOverview extends StatelessWidget {
  const _KnowledgeReviewOverview({required this.snapshot});

  final KnowledgeReviewSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final latestRun = snapshot.agentResults.latestRun;
    return KnowledgeSection.group(
      title: l10n.knowledgeReviewOverviewTitle,
      trailing: AppBadge(
        label: '${snapshot.attentionCount}',
        icon: FLucideIcons.listChecks,
        size: AppBadgeSize.compact,
        tone: AppBadgeTone.info,
      ),
      children: [
        Text(
          l10n.knowledgeReviewAttentionSummary(
            snapshot.dueRoutines.length,
            snapshot.dueDecisions.length,
            snapshot.staleAssumptions.length,
            snapshot.pendingSuggestionCount,
            snapshot.findings.length,
          ),
          style: context.bodyCaptionStyle,
        ),
        if (latestRun != null) ...[
          const SizedBox(height: AppSpacing.s8),
          Text(
            l10n.knowledgeReviewLastRun(
              knowledgeDate(
                context,
                latestRun.finishedAt ?? latestRun.startedAt,
                long: true,
              ),
            ),
            style: context.captionStyle,
          ),
        ],
      ],
    );
  }
}

class _KnowledgeReviewAgentResults extends ConsumerWidget {
  const _KnowledgeReviewAgentResults({required this.bundle});

  final agent_providers.AgentResultBundle bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return AgentResultsSection(
      bundle: bundle,
      metaLabelBuilder: (at) => agentResultMetaLabel(l10n, at),
      summaryMaxLines: 3,
      onOpen: (artifact) => _openAgentArtifact(context, ref, artifact),
      onRetry: (agentId) => _retryKnowledgeAgent(context, ref, agentId),
    );
  }
}

Future<void> _retryKnowledgeAgent(
  BuildContext context,
  WidgetRef ref,
  String agentId,
) async {
  final controller = await ref.read(agentRunControllerProvider.future);
  if (!context.mounted) return;
  await controller.runOnceById(agentId);
  if (!context.mounted) return;
  ref.invalidate(
    knowledge_agent_providers.latestKnowledgeReviewResultsProvider,
  );
  ref.invalidate(knowledgeReviewSnapshotProvider);
}

void _openAgentArtifact(
  BuildContext context,
  WidgetRef ref,
  AgentArtifact artifact,
) {
  unawaited(
    context.push(AgentArtifactRoutes.detail(artifact.id)).then((_) {
      if (context.mounted) ref.invalidate(knowledgeReviewSnapshotProvider);
    }),
  );
}

class _KnowledgeReviewFindingsCard extends StatelessWidget {
  const _KnowledgeReviewFindingsCard({required this.findings});

  final List<StoredAgentFinding> findings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visible = findings.take(kReviewCardMaxItems).toList(growable: false);
    return KnowledgeSection.group(
      title: l10n.knowledgeAgentContradictionTitle,
      trailing: AppBadge(
        label: '${findings.length}',
        icon: FLucideIcons.triangleAlert,
        size: AppBadgeSize.compact,
        tone: AppBadgeTone.warning,
      ),
      children: [
        _ReviewCountHint(
          visibleCount: visible.length,
          totalCount: findings.length,
        ),
        const SizedBox(height: AppSpacing.s8),
        for (var index = 0; index < visible.length; index++) ...[
          if (index > 0) ...[
            const AppDivider(horizontalPadding: AppSpacing.s0),
            const SizedBox(height: AppSpacing.s8),
          ],
          _KnowledgeFindingRow(finding: visible[index]),
        ],
      ],
    );
  }
}

class _KnowledgeFindingRow extends StatelessWidget {
  const _KnowledgeFindingRow({required this.finding});

  final StoredAgentFinding finding;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final subjectKind = finding.payload['subject_kind'] as String?;
    final subjectId = finding.payload['subject_id'] as String?;
    final subjectLabel = finding.payload['subject_label'] as String?;
    final detail = finding.payload['detail'] as String?;
    final route = _findingRoute(subjectKind, subjectId);
    final title = finding.kind == 'assumption_invalidated'
        ? l10n.knowledgeAgentContradictionInsightInvalidatedTitle
        : l10n.knowledgeAgentContradictionInsightPrincipleTitle;
    final fallback = [
      subjectKind,
      subjectId,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');

    return Semantics(
      button: route != null,
      label: subjectLabel ?? fallback,
      child: AppTappable(
        onPress: route == null ? null : () => context.push(route),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                FLucideIcons.triangleAlert,
                size: AppIconSizes.xs,
                color: colors.destructive,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.captionLabelStyle),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      subjectLabel?.isNotEmpty == true
                          ? subjectLabel!
                          : fallback,
                      style: context.rowTitleStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (detail?.isNotEmpty == true) ...[
                      const SizedBox(height: AppSpacing.s2),
                      Text(
                        detail!,
                        style: context.captionStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (route != null) ...[
                const SizedBox(width: AppSpacing.s8),
                Icon(
                  FLucideIcons.chevronRight,
                  size: AppIconSizes.xs,
                  color: colors.mutedForeground,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String? _findingRoute(String? kind, String? id) {
  if (kind == null || id == null || id.isEmpty) return null;
  if (kind == KnowledgeEntryKind.decision.name) {
    return KnowledgeRoutes.decision(id);
  }
  if (KnowledgeObjectKind.parse(kind) != null) {
    return KnowledgeRoutes.object(kind, id);
  }
  return null;
}

class _KnowledgeReviewCompleteState extends StatelessWidget {
  const _KnowledgeReviewCompleteState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s12),
      child: AppEmptyState(
        icon: FLucideIcons.circleCheckBig,
        title: l10n.knowledgeReviewAllClearBadge,
        message: l10n.knowledgeReviewAllClearBody,
        action: AppQuietButton(
          label: l10n.knowledgeReviewBrowseLibrary,
          prefix: const Icon(FLucideIcons.library, size: AppIconSizes.xs),
          onPress: () => context.go(KnowledgeRoutes.library),
        ),
      ),
    );
  }
}

Future<void> _refreshReview(WidgetRef ref) async {
  ref.invalidate(knowledgeRepositoryProvider);
  ref.invalidate(inboxTriageRepositoryProvider);
  ref.invalidate(
    knowledge_agent_providers.latestKnowledgeReviewResultsProvider,
  );
  ref.invalidate(knowledge_agent_providers.latestKnowledgeReviewRunProvider);
  ref.invalidate(knowledgeReviewSnapshotProvider);
  ref.read(aiSuggestionsRefreshProvider.notifier).state++;
  ref.read(_reviewActionsRefreshProvider.notifier).state++;
  await ref.read(knowledgeReviewSnapshotProvider.future);
}

void _toggleReviewSelection(Set<String> selectedIds, String id) {
  if (!selectedIds.add(id)) selectedIds.remove(id);
}
