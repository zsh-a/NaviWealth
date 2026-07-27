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
import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../agents/providers.dart' as knowledge_agent_providers;
import '../agents/routine_due_agent.dart';
import '../composition/knowledge_route_paths.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_ai_suggestions_card.dart';
import '_widgets.dart';

part 'knowledge_review_assumptions.dart';
part 'knowledge_review_decisions.dart';
part 'knowledge_review_routines.dart';
part 'knowledge_review_selection.dart';

const int _kDecisionReviewRescheduleDays = 90;
const String _kReviewRoutineOrderPrefsKey = 'knowledge.review.routine_order.v1';
const String _kReviewDecisionOrderPrefsKey =
    'knowledge.review.decision_order.v1';
const String _kReviewAssumptionOrderPrefsKey =
    'knowledge.review.assumption_order.v1';

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
                _KnowledgeReviewAgentResultPanel(),
                SizedBox(height: AppPageRhythm.module),
                KnowledgeAiSuggestionsCard(),
                SizedBox(height: AppPageRhythm.module),
                _DueRoutinesCard(),
                SizedBox(height: AppPageRhythm.module),
                _DueReviewsCard(),
                SizedBox(height: AppPageRhythm.module),
                _StaleAssumptionsCard(),
              ],
            ),
          ),
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
    AppAdaptiveAction(
      icon: FLucideIcons.calendarCheck,
      title: l10n.knowledgeReviewMarkAllDecisionsReviewed,
      subtitle: l10n.knowledgeReviewDecisionsTitle,
      onPress: () async {
        final decisions = await _loadReviewDecisions(ref);
        if (!context.mounted) return;
        if (decisions.isEmpty) {
          AppMessenger.show(
            context,
            ToastKind.info,
            l10n.knowledgeReviewDecisionsEmpty,
          );
          return;
        }
        await _markDecisionsReviewed(
          context: context,
          ref: ref,
          decisions: decisions,
        );
      },
    ),
    AppAdaptiveAction(
      icon: FLucideIcons.badgeCheck,
      title: l10n.knowledgeReviewVerifyAllAssumptions,
      subtitle: l10n.knowledgeReviewAssumptionsTitle,
      onPress: () async {
        final assumptions = await _loadReviewAssumptions(ref);
        if (!context.mounted) return;
        if (assumptions.isEmpty) {
          AppMessenger.show(
            context,
            ToastKind.info,
            l10n.knowledgeReviewAssumptionsEmpty(kKnowledgeAssumptionStaleDays),
          );
          return;
        }
        await _verifyAssumptions(
          context: context,
          ref: ref,
          assumptions: assumptions,
        );
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

Future<List<KnowledgeDecision>> _loadReviewDecisions(WidgetRef ref) async {
  final owner = await _reviewOwner(ref);
  final repo = await ref.read(knowledgeRepositoryProvider.future);
  return repo.listDueReviews(
    ownerUserId: owner,
    asOf: DateTime.now().toUtc(),
    limit: 1000,
  );
}

Future<List<KnowledgeAssumption>> _loadReviewAssumptions(WidgetRef ref) async {
  final owner = await _reviewOwner(ref);
  final repo = await ref.read(knowledgeRepositoryProvider.future);
  final now = DateTime.now().toUtc();
  final all = await repo.listOpenAssumptions(ownerUserId: owner);
  return all
      .where((a) => a.daysSinceVerify(now) >= kKnowledgeAssumptionStaleDays)
      .toList(growable: false);
}

void _toggleReviewSelection(Set<String> selectedIds, String id) {
  if (!selectedIds.add(id)) selectedIds.remove(id);
}
