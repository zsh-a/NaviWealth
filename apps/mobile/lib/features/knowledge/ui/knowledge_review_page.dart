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

import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_run_store.dart';
import '../../../core/ai/agents/providers.dart' as agent_providers;
import '../../../core/ai/agents/ui/agent_result_card.dart';
import '../../../core/format/formatters.dart';
import '../../../core/shell/shell_chrome.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../agents/assumption_agent.dart';
import '../agents/providers.dart' as knowledge_agent_providers;
import '../agents/routine_due_agent.dart';
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
  const KnowledgeReviewPage({super.key, this.initialAgentArtifactId});

  final String? initialAgentArtifactId;

  @override
  ConsumerState<KnowledgeReviewPage> createState() =>
      _KnowledgeReviewPageState();
}

class _KnowledgeReviewPageState extends ConsumerState<KnowledgeReviewPage>
    with KnowledgeFabScrollHideMixin {
  String? _openedInitialArtifactId;

  @override
  Widget build(BuildContext context) {
    _maybeOpenInitialArtifactSheet();
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.knowledgeReviewTitle,
      child: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: onScrollUpdate,
              child: KnowledgePullToRefresh(
                onRefresh: () => _refreshReview(ref),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: shellTabContentPadding(
                    context,
                    bottom: AppSpacing.s64 + AppSpacing.s16,
                  ),
                  children: const <Widget>[
                    _KnowledgeReviewAgentResultPanel(),
                    SizedBox(height: AppSpacing.s16),
                    KnowledgeAiSuggestionsCard(),
                    SizedBox(height: AppSpacing.s16),
                    _DueRoutinesCard(),
                    SizedBox(height: AppSpacing.s16),
                    _DueReviewsCard(),
                    SizedBox(height: AppSpacing.s16),
                    _StaleAssumptionsCard(),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: AppSpacing.s16,
            bottom: shellTabFloatingActionBottom(context),
            child: KnowledgeFloatingActionMotion(
              hidden: fabHidden,
              child: const _ReviewActionsFab(),
            ),
          ),
        ],
      ),
    );
  }

  void _maybeOpenInitialArtifactSheet() {
    final artifactId = widget.initialAgentArtifactId;
    if (artifactId == null ||
        artifactId.isEmpty ||
        _openedInitialArtifactId == artifactId) {
      return;
    }
    _openedInitialArtifactId = artifactId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final store = await ref.read(
        agent_providers.agentArtifactStoreProvider.future,
      );
      final artifact = await store.read(artifactId);
      if (!mounted || artifact == null) return;
      final l10n = AppLocalizations.of(context);
      final metaLabel = _knowledgeAgentArtifactUpdated(
        l10n,
        artifact.createdAt,
      );
      await showAgentArtifactSheet(
        context: context,
        artifact: artifact,
        subtitle: metaLabel,
        onVisibilityChanged: () {
          ref.invalidate(
            knowledge_agent_providers.latestKnowledgeReviewArtifactProvider,
          );
          ref.invalidate(
            knowledge_agent_providers.latestKnowledgeReviewArtifactsProvider,
          );
        },
      );
    });
  }
}

Future<void> _refreshReview(WidgetRef ref) async {
  ref.invalidate(knowledgeRepositoryProvider);
  ref.invalidate(inboxTriageRepositoryProvider);
  ref.invalidate(
    knowledge_agent_providers.latestKnowledgeReviewArtifactProvider,
  );
  ref.invalidate(
    knowledge_agent_providers.latestKnowledgeReviewArtifactsProvider,
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
    final artifactAsync = ref.watch(
      knowledge_agent_providers.latestKnowledgeReviewArtifactsProvider,
    );
    final runAsync = ref.watch(
      knowledge_agent_providers.latestKnowledgeReviewRunProvider,
    );
    return artifactAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (artifacts) {
        if (artifacts.isNotEmpty) {
          return _KnowledgeReviewAgentResultList(artifacts: artifacts);
        }
        return runAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (record) {
            if (record == null) return const SizedBox.shrink();
            return _KnowledgeReviewAgentRunStatusCard(record: record);
          },
        );
      },
    );
  }
}

class _KnowledgeReviewAgentResultList extends StatelessWidget {
  const _KnowledgeReviewAgentResultList({required this.artifacts});

  final List<AgentArtifact> artifacts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < artifacts.length; i++) ...[
          _KnowledgeReviewAgentResultCard(artifact: artifacts[i]),
          if (i != artifacts.length - 1) const SizedBox(height: AppSpacing.s8),
        ],
      ],
    );
  }
}

class _KnowledgeReviewAgentRunStatusCard extends StatelessWidget {
  const _KnowledgeReviewAgentRunStatusCard({required this.record});

  final AgentRunRecord record;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reference = record.finishedAt ?? record.startedAt;
    return AgentRunStatusCard(
      record: record,
      metaLabel: _knowledgeAgentArtifactUpdated(l10n, reference),
    );
  }
}

class _KnowledgeReviewAgentResultCard extends ConsumerWidget {
  const _KnowledgeReviewAgentResultCard({required this.artifact});

  final AgentArtifact artifact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final metaLabel = _knowledgeAgentArtifactUpdated(l10n, artifact.createdAt);
    return AgentResultCard(
      artifact: artifact,
      metaLabel: metaLabel,
      onOpen: () => showAgentArtifactSheet(
        context: context,
        artifact: artifact,
        subtitle: metaLabel,
        onVisibilityChanged: () {
          ref.invalidate(
            knowledge_agent_providers.latestKnowledgeReviewArtifactProvider,
          );
          ref.invalidate(
            knowledge_agent_providers.latestKnowledgeReviewArtifactsProvider,
          );
        },
      ),
    );
  }
}

/// Icon-only FAB that opens the review batch-actions sheet.
class _ReviewActionsFab extends ConsumerWidget {
  const _ReviewActionsFab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return KnowledgeFloatingActionSurface(
      icon: FLucideIcons.listChecks,
      tooltip: AppLocalizations.of(context).knowledgeReviewBatchActions,
      onPress: () => _openActionsSheet(context, ref),
    );
  }

  Future<void> _openActionsSheet(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    await showAppSheet<void>(
      context: context,
      title: l10n.knowledgeReviewTitle,
      builder: (sheetContext) => AppActionSheetList(
        children: [
          AppActionSheetTile(
            icon: FLucideIcons.checkCheck,
            title: l10n.knowledgeReviewMarkAllDone,
            subtitle: l10n.knowledgeReviewRoutinesTitle,
            onPress: () async {
              Navigator.of(sheetContext).pop();
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
              await _markRoutinesDone(
                context: context,
                ref: ref,
                routines: routines,
              );
            },
          ),
          AppActionSheetTile(
            icon: FLucideIcons.calendarCheck,
            title: l10n.knowledgeReviewMarkAllDecisionsReviewed,
            subtitle: l10n.knowledgeReviewDecisionsTitle,
            onPress: () async {
              Navigator.of(sheetContext).pop();
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
          AppActionSheetTile(
            icon: FLucideIcons.badgeCheck,
            title: l10n.knowledgeReviewVerifyAllAssumptions,
            subtitle: l10n.knowledgeReviewAssumptionsTitle,
            onPress: () async {
              Navigator.of(sheetContext).pop();
              final assumptions = await _loadReviewAssumptions(ref);
              if (!context.mounted) return;
              if (assumptions.isEmpty) {
                AppMessenger.show(
                  context,
                  ToastKind.info,
                  l10n.knowledgeReviewAssumptionsEmpty(kAssumptionStaleDays),
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
        ],
      ),
    );
  }
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
      .where((a) => a.daysSinceVerify(now) >= kAssumptionStaleDays)
      .toList(growable: false);
}

void _toggleReviewSelection(Set<String> selectedIds, String id) {
  if (!selectedIds.add(id)) selectedIds.remove(id);
}

String _knowledgeAgentArtifactUpdated(AppLocalizations l10n, DateTime when) {
  return AppFormatters.relativeTime(
    when,
    justNow: l10n.aiChatRelativeJustNow,
    minutesAgo: l10n.aiChatRelativeMinutesAgo,
    hoursAgo: l10n.aiChatRelativeHoursAgo,
    daysAgo: l10n.aiChatRelativeDaysAgo,
    dateFallback: (d) {
      final mm = d.month.toString().padLeft(2, '0');
      final dd = d.day.toString().padLeft(2, '0');
      return '$mm-$dd';
    },
  );
}
