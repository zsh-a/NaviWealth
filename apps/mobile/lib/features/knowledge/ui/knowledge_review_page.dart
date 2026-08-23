/// KnowledgeOS Review tab (`docs/domains/knowledgeos-domain.md` §5).
///
/// 3 cards: due Routines (next_due_at within 7d), due Decisions
/// (review_date passed) and stale Assumptions (active && > 90d
/// unverified). Forui chrome with widget-layer pull-to-refresh.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/agents/agent_artifact_routes.dart';
import '../../../core/ai/agents/agent_run_controller.dart';
import '../../../core/ai/agents/ui/agent_results_panel.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../agents/providers.dart' as knowledge_agent_providers;
import '../application/knowledge_lifecycle_service.dart';
import '../composition/knowledge_route_paths.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_ai_suggestions_card.dart';
import '_decision_lifecycle_sheet.dart';
import '_widgets.dart';

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

final _knowledgeReviewIsEmptyProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  ref.watch(_reviewActionsRefreshProvider);
  ref.watch(aiSuggestionsRefreshProvider);
  final owner = await ref.watch(knowledgeOwnerUserIdProvider.future);
  final repo = await ref.watch(knowledgeRepositoryProvider.future);
  final triage = await ref.watch(inboxTriageRepositoryProvider.future);
  final results = await ref.watch(
    knowledge_agent_providers.latestKnowledgeReviewResultsProvider.future,
  );
  final now = DateTime.now();
  final routines = await repo.listDueRoutines(
    ownerUserId: owner,
    asOf: now.add(kRoutineDueLookahead),
  );
  final decisions = await repo.listDueReviews(
    ownerUserId: owner,
    asOf: now.toUtc(),
  );
  final assumptions = await repo.listOpenAssumptions(ownerUserId: owner);
  final pending = await triage.listPending(ownerUserId: owner);
  final hasStaleAssumption = assumptions.any(
    (item) =>
        item.daysSinceVerify(now.toUtc()) >= kKnowledgeAssumptionStaleDays,
  );
  return routines.isEmpty &&
      decisions.isEmpty &&
      !hasStaleAssumption &&
      pending.every((record) => record.pending.isEmpty) &&
      results.artifacts.isEmpty;
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
              children: const <Widget>[
                KnowledgeAiSuggestionsCard(),
                _DueRoutinesCard(),
                _DueReviewsCard(),
                _StaleAssumptionsCard(),
                _KnowledgeReviewAgentResultPanel(),
                _KnowledgeReviewCompleteState(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KnowledgeReviewCompleteState extends ConsumerWidget {
  const _KnowledgeReviewCompleteState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final empty = ref.watch(_knowledgeReviewIsEmptyProvider);
    return empty.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: AppSpacing.s12),
        child: KnowledgeSectionSkeleton(),
      ),
      error: (error, stackTrace) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.s12),
        child: AppEmptyState.inline(
          icon: FLucideIcons.refreshCw,
          title: userSafeErrorMessage(
            context,
            error,
            stackTrace: stackTrace,
            operation: 'load knowledge review state',
          ),
          tone: AppEmptyStateTone.error,
          retryLabel: AppLocalizations.of(context).commonRetry,
          onRetry: () => ref.invalidate(_knowledgeReviewIsEmptyProvider),
        ),
      ),
      data: (isEmpty) {
        if (!isEmpty) return const SizedBox.shrink();
        final l10n = AppLocalizations.of(context);
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s24),
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
      },
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
  ref.read(aiSuggestionsRefreshProvider.notifier).state++;
  ref.read(_reviewActionsRefreshProvider.notifier).state++;
  await Future.wait([
    ref.read(knowledgeRepositoryProvider.future),
    ref.read(inboxTriageRepositoryProvider.future),
  ]);
}

class _KnowledgeReviewAgentResultPanel extends ConsumerWidget {
  const _KnowledgeReviewAgentResultPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(
      knowledge_agent_providers.latestKnowledgeReviewResultsProvider,
    );
    // Signal-first Review surface: quiet while loading and when empty.
    return AgentResultsPanel(
      resultsAsync: resultsAsync,
      showPlaceholderStates: false,
      bottomGap: AppSpacing.s0,
      onReload: () => ref.invalidate(
        knowledge_agent_providers.latestKnowledgeReviewResultsProvider,
      ),
      onOpen: (artifact) =>
          context.push(AgentArtifactRoutes.detail(artifact.id)),
      onRunAgain: (agentId) => _retryKnowledgeAgent(ref, agentId),
    );
  }
}

Future<void> _retryKnowledgeAgent(WidgetRef ref, String agentId) async {
  final controller = await ref.read(agentRunControllerProvider.future);
  await controller.runOnceById(agentId);
  ref.invalidate(
    knowledge_agent_providers.latestKnowledgeReviewResultsProvider,
  );
}

void _toggleReviewSelection(Set<String> selectedIds, String id) {
  if (!selectedIds.add(id)) selectedIds.remove(id);
}
