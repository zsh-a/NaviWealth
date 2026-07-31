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
import '../../../core/ai/agents/agent_run_store.dart';
import '../../../core/ai/agents/ui/agent_results_panel.dart';
import '../../../core/ai/llm_credentials/providers.dart';
import '../../../core/auth/current_user.dart';
import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../agents/providers.dart' as knowledge_agent_providers;
import '../agents/review_agent.dart';
import '../agents/routine_due_agent.dart';
import '../composition/knowledge_route_paths.dart';
import '../data/knowledge_review_preferences.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_ai_suggestions_card.dart';
import '_widgets.dart';

part 'knowledge_review_assumptions.dart';
part 'knowledge_review_decisions.dart';
part 'knowledge_review_routines.dart';
part 'knowledge_review_selection.dart';

const int _kDecisionReviewRescheduleDays = 90;
const String _kReviewRoutineOrderPrefsKey = 'routine_order';
const String _kReviewDecisionOrderPrefsKey = 'decision_order';
const String _kReviewAssumptionOrderPrefsKey = 'assumption_order';

String _reviewOrderPrefsKey(WidgetRef ref, String family) {
  final owner = ref.read(activeUserIdProvider) ?? kLocalOnlyUserId;
  return 'knowledge.$owner.review.$family.v2';
}

final _reviewActionsRefreshProvider = StateProvider<int>((ref) => 0);

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
    // Blueprint §8.2: creation/bulk entry points live in the page header —
    // the Knowledge-only FAB is retired app-wide.
    return ShellTabScaffold(
      title: l10n.knowledgeReviewTitle,
      actions: [
        ShellHeaderActionSpec(
          icon: FLucideIcons.checkCheck,
          label: l10n.knowledgeReviewTitle,
          onPress: () => _showReviewActionsSheet(context, ref),
        ),
      ],
      child: ShellTabPause(
        routePath: KnowledgeRoutes.review,
        child: AppAtmosphere(
          child: AppRefreshIndicator(
            onRefresh: () => _refreshReview(ref),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: shellTabContentPadding(context, top: AppSpacing.s8),
              children: const <Widget>[
                _KnowledgeReviewOverview(),
                SizedBox(height: AppPageRhythm.module),
                _KnowledgeReviewAgentResultPanel(),
                KnowledgeAiSuggestionsCard(),
                _DueRoutinesCard(),
                _DueReviewsCard(),
                _StaleAssumptionsCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KnowledgeReviewSnapshot {
  const _KnowledgeReviewSnapshot({
    required this.routineCount,
    required this.decisionCount,
    required this.assumptionCount,
    required this.suggestionCount,
    required this.agentFindingCount,
    required this.lastRun,
    required this.aiAvailable,
  });

  final int routineCount;
  final int decisionCount;
  final int assumptionCount;
  final int suggestionCount;
  final int agentFindingCount;
  final AgentRunRecord? lastRun;
  final bool aiAvailable;

  int get attentionCount =>
      routineCount +
      decisionCount +
      assumptionCount +
      suggestionCount +
      agentFindingCount;
}

final _knowledgeReviewSnapshotProvider =
    FutureProvider.autoDispose<_KnowledgeReviewSnapshot>((ref) async {
      ref.watch(_reviewActionsRefreshProvider);
      ref.watch(aiSuggestionsRefreshProvider);
      final preferences = ref.watch(knowledgeReviewPreferencesProvider);
      final aiAvailable = ref.watch(deviceLlmAvailableProvider);
      final owner = await ref.watch(knowledgeOwnerUserIdProvider.future);
      final repo = await ref.watch(knowledgeRepositoryProvider.future);
      final triage = await ref.watch(inboxTriageRepositoryProvider.future);
      final resultBundle = await ref.watch(
        knowledge_agent_providers.latestKnowledgeReviewResultsProvider.future,
      );
      final now = DateTime.now().toUtc();
      final routines = await repo.listDueRoutines(
        ownerUserId: owner,
        asOf: now.add(kRoutineDueLookahead),
        excludeDoneSince: DateTime(now.year, now.month, now.day),
        limit: 1000,
      );
      final decisions = await repo.listDueReviews(
        ownerUserId: owner,
        asOf: now,
        limit: 1000,
      );
      final assumptions = await repo.listOpenAssumptions(ownerUserId: owner);
      final pending = await triage.listPending(ownerUserId: owner);
      return _KnowledgeReviewSnapshot(
        routineCount: routines.length,
        decisionCount: decisions.length,
        assumptionCount: assumptions
            .where(
              (item) =>
                  item.daysSinceVerify(now) >= preferences.staleAssumptionDays,
            )
            .length,
        suggestionCount: pending.fold<int>(
          0,
          (sum, record) => sum + record.pending.length,
        ),
        agentFindingCount: resultBundle.artifacts.length,
        lastRun: resultBundle.latestRun,
        aiAvailable: aiAvailable,
      );
    });

class _KnowledgeReviewOverview extends ConsumerWidget {
  const _KnowledgeReviewOverview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(_knowledgeReviewSnapshotProvider);
    return snapshot.when(
      loading: () =>
          const KnowledgeLoadingState(density: KnowledgeStateDensity.section),
      error: (error, stackTrace) => KnowledgeErrorState(
        title: userSafeErrorMessage(
          context,
          error,
          stackTrace: stackTrace,
          operation: 'load knowledge review overview',
        ),
        onRetry: () => ref.invalidate(_knowledgeReviewSnapshotProvider),
        density: KnowledgeStateDensity.section,
      ),
      data: (value) {
        final lastRun = value.lastRun;
        final isAllClear = value.attentionCount == 0;
        return KnowledgeSection.group(
          title: l10n.knowledgeReviewOverviewTitle,
          trailing: AppBadge(
            label: isAllClear
                ? l10n.knowledgeReviewAllClearBadge
                : '${value.attentionCount}',
            icon: isAllClear ? FLucideIcons.circleCheck : FLucideIcons.bell,
            size: AppBadgeSize.compact,
            tone: isAllClear ? AppBadgeTone.success : AppBadgeTone.warning,
          ),
          children: [
            Text(
              isAllClear
                  ? l10n.knowledgeReviewAllClearBody
                  : l10n.knowledgeReviewAttentionSummary(
                      value.routineCount,
                      value.decisionCount,
                      value.assumptionCount,
                      value.suggestionCount,
                    ),
              style: context.theme.typography.body.sm,
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              lastRun == null
                  ? l10n.knowledgeReviewAgentNotRun
                  : l10n.knowledgeReviewLastRun(
                      knowledgeDate(
                        context,
                        lastRun.finishedAt ?? lastRun.startedAt,
                        long: true,
                      ),
                    ),
              style: context.captionStyle,
            ),
            if (!value.aiAvailable) ...[
              const SizedBox(height: AppSpacing.s4),
              Text(
                l10n.knowledgeReviewAiUnavailable,
                style: context.captionStyle,
              ),
            ],
            const SizedBox(height: AppSpacing.s12),
            FButton(
              variant: FButtonVariant.outline,
              onPress: () => _retryKnowledgeAgent(ref, kKnowledgeReviewAgentId),
              child: Text(l10n.knowledgeReviewRunNow),
            ),
          ],
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

/// Icon-only FAB that opens the adaptive review batch-actions menu.
Future<void> _showReviewActionsSheet(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.knowledgeReviewTitle,
    builder: (sheetContext) {
      final actions = _reviewBulkActions(context, ref, l10n);
      return AppActionSheetList(
        children: [
          for (final action in actions)
            AppActionSheetTile(
              icon: action.icon,
              title: action.title,
              subtitle: action.subtitle,
              onPress: () {
                Navigator.of(sheetContext).pop();
                action.onPress();
              },
            ),
        ],
      );
    },
  );
}

List<AppAdaptiveAction> _reviewBulkActions(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
) {
  return <AppAdaptiveAction>[
    AppAdaptiveAction(
      icon: FLucideIcons.checkCheck,
      title: l10n.knowledgeReviewMarkAllDone,
      subtitle: l10n.knowledgeReviewRoutinesTitle,
      onPress: () async {
        final routines = await _loadReviewRoutines(ref);
        if (!context.mounted) return;
        if (routines.isEmpty) {
          AppMessenger.show(
            context,
            ToastKind.info,
            l10n.knowledgeReviewRoutinesEmpty,
          );
          return;
        }
        await _markRoutinesDone(context: context, ref: ref, routines: routines);
      },
    ),
  ];
}

Future<String> _reviewOwner(WidgetRef ref) => ref.read(currentUserIdProvider)();

Future<List<KnowledgeRoutine>> _loadReviewRoutines(WidgetRef ref) async {
  final owner = await _reviewOwner(ref);
  final repo = await ref.read(knowledgeRepositoryProvider.future);
  final now = DateTime.now();
  return repo.listDueRoutines(
    ownerUserId: owner,
    asOf: now.add(kRoutineDueLookahead).toUtc(),
    excludeDoneSince: DateTime(now.year, now.month, now.day),
    limit: 1000,
  );
}

void _toggleReviewSelection(Set<String> selectedIds, String id) {
  if (!selectedIds.add(id)) selectedIds.remove(id);
}
