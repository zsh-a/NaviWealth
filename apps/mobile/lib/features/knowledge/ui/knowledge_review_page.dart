/// KnowledgeOS Review tab (`docs/knowledgeos-domain.md` §5).
///
/// 3 cards: due Routines (next_due_at within 7d), due Decisions
/// (review_date passed) and stale Assumptions (active && > 90d
/// unverified). Forui-only chrome — no Material.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../app/shell_chrome.dart';
import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../agents/assumption_agent.dart';
import '../agents/routine_due_agent.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_ai_suggestions_card.dart';
import '_widgets.dart';

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

class KnowledgeReviewPage extends ConsumerWidget {
  const KnowledgeReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.knowledgeReviewTitle,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.s16),
        children: const <Widget>[
          KnowledgeAiSuggestionsCard(),
          SizedBox(height: AppSpacing.s16),
          _DueRoutinesCard(),
          SizedBox(height: AppSpacing.s16),
          _DueReviewsCard(),
          SizedBox(height: AppSpacing.s16),
          _StaleAssumptionsCard(),
        ],
      ),
    );
  }
}

class _DueRoutinesCard extends ConsumerWidget {
  const _DueRoutinesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) return const SizedBox.shrink();
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        return repoAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => KnowledgeSection.group(
            title: l10n.knowledgeReviewRoutinesTitle,
            children: [
              Text(
                l10n.knowledgeReviewLoadFailed('$e'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          data: (repo) {
            return StreamBuilder<List<KnowledgeRoutine>>(
              // Watch + filter in-memory so a `markDone` bumps the list
              // immediately. The agent-side `listDueRoutines` is the same
              // query, only as a future.
              stream: repo.watchRoutines(ownerUserId: owner),
              builder: (context, snap) {
                final now = DateTime.now();
                final due = (snap.data ?? const <KnowledgeRoutine>[])
                    .where((r) => shouldShowRoutineInReview(r, now))
                    .toList(growable: false);
                final typography = context.theme.typography;
                final colors = context.theme.colors;
                return KnowledgeSection.group(
                  title: l10n.knowledgeReviewRoutinesTitle,
                  children: [
                    if (due.isEmpty)
                      Text(
                        l10n.knowledgeReviewRoutinesEmpty,
                        style: typography.sm.copyWith(
                          color: colors.mutedForeground,
                        ),
                      )
                    else
                      ...due
                          .take(kReviewCardMaxItems)
                          .map((r) => _DueRoutineRow(routine: r)),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _DueRoutineRow extends ConsumerStatefulWidget {
  const _DueRoutineRow({required this.routine});
  final KnowledgeRoutine routine;
  @override
  ConsumerState<_DueRoutineRow> createState() => _DueRoutineRowState();
}

class _DueRoutineRowState extends ConsumerState<_DueRoutineRow> {
  bool _busy = false;

  Future<void> _markDone() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final r = widget.routine;
      final next = stamp.now.add(Duration(days: r.intervalDays));
      await repo.upsertRoutine(
        KnowledgeRoutine(
          id: r.id,
          statement: r.statement,
          intervalDays: r.intervalDays,
          nextDueAt: next,
          lastDoneAt: stamp.now,
          scope: r.scope,
          status: r.status,
          createdAt: r.createdAt,
          sync: SyncMeta(
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        ),
      );
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.knowledgeReviewRoutineDone(_formatDate(next)),
        );
      }
    } catch (e) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.knowledgeReviewRoutineDoneFailed('$e'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    final now = DateTime.now();
    final days = widget.routine.daysUntilDue(now);
    final dueLabel = days < 0
        ? l10n.knowledgeRoutineOverdueDays(-days)
        : days == 0
        ? l10n.knowledgeRoutineDueToday
        : l10n.knowledgeRoutineDueInDays(days);
    final dueColor = days < 0 ? colors.destructive : colors.mutedForeground;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        children: [
          Icon(
            FLucideIcons.repeat,
            size: AppIconSizes.xs,
            color: colors.mutedForeground,
          ),
          const SizedBox(width: AppSpacing.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.routine.statement,
                  style: typography.sm,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  l10n.knowledgeReviewRoutineMeta(
                    dueLabel,
                    widget.routine.intervalDays,
                  ),
                  style: typography.xs.copyWith(color: dueColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          FButton(
            variant: FButtonVariant.outline,
            onPress: _busy ? null : _markDone,
            child: Text(_busy ? '...' : l10n.knowledgeReviewMarkDone),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

class _DueReviewsCard extends ConsumerWidget {
  const _DueReviewsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) return const SizedBox.shrink();
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        return repoAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => KnowledgeSection.group(
            title: l10n.knowledgeReviewDecisionsTitle,
            children: [
              Text(
                l10n.knowledgeReviewLoadFailed('$e'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          data: (repo) {
            return FutureBuilder(
              future: repo.listDueReviews(
                ownerUserId: owner,
                asOf: DateTime.now().toUtc(),
              ),
              builder: (context, snap) {
                final list = snap.data ?? const [];
                final typography = context.theme.typography;
                final colors = context.theme.colors;
                return KnowledgeSection.group(
                  title: l10n.knowledgeReviewDecisionsTitle,
                  children: [
                    if (list.isEmpty)
                      Text(
                        l10n.knowledgeReviewDecisionsEmpty,
                        style: typography.sm.copyWith(
                          color: colors.mutedForeground,
                        ),
                      )
                    else
                      ...list
                          .take(kReviewCardMaxItems)
                          .map(
                            (d) => Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.s4,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    FLucideIcons.calendar,
                                    size: AppIconSizes.xs,
                                    color: colors.mutedForeground,
                                  ),
                                  const SizedBox(width: AppSpacing.s4),
                                  Expanded(
                                    child: Text(
                                      d.question,
                                      style: typography.sm,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.s4),
                                  Text(
                                    l10n.knowledgeReviewDecisionOverdueDays(
                                      d.daysOverdue(DateTime.now().toUtc()) ??
                                          0,
                                    ),
                                    style: typography.xs.copyWith(
                                      color: colors.mutedForeground,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _StaleAssumptionsCard extends ConsumerWidget {
  const _StaleAssumptionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) return const SizedBox.shrink();
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        return repoAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => const SizedBox.shrink(),
          data: (repo) {
            return FutureBuilder(
              future: repo.listOpenAssumptions(ownerUserId: owner),
              builder: (context, snap) {
                final all = snap.data ?? const [];
                final now = DateTime.now().toUtc();
                final stale = all
                    .where(
                      (a) => a.daysSinceVerify(now) >= kAssumptionStaleDays,
                    )
                    .toList();
                final typography = context.theme.typography;
                final colors = context.theme.colors;
                return KnowledgeSection.group(
                  title: l10n.knowledgeReviewAssumptionsTitle,
                  children: [
                    if (stale.isEmpty)
                      Text(
                        l10n.knowledgeReviewAssumptionsEmpty(
                          kAssumptionStaleDays,
                        ),
                        style: typography.sm.copyWith(
                          color: colors.mutedForeground,
                        ),
                      )
                    else
                      ...stale
                          .take(kReviewCardMaxItems)
                          .map(
                            (a) => Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.s4,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      l10n.knowledgeReviewAssumptionStaleSummary(
                                        a.statement,
                                        a.daysSinceVerify(now),
                                        a.confidence.toStringAsFixed(2),
                                      ),
                                      style: typography.sm,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.s8),
                                  _VerifyAssumptionButton(assumption: a),
                                ],
                              ),
                            ),
                          ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _VerifyAssumptionButton extends ConsumerStatefulWidget {
  const _VerifyAssumptionButton({required this.assumption});

  final KnowledgeAssumption assumption;

  @override
  ConsumerState<_VerifyAssumptionButton> createState() =>
      _VerifyAssumptionButtonState();
}

class _VerifyAssumptionButtonState
    extends ConsumerState<_VerifyAssumptionButton> {
  bool _busy = false;

  Future<void> _verify() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final stamper = await ref.read(mutationStamperProvider.future);
      final stamp = await stamper.stamp();
      final a = widget.assumption;
      await repo.upsertAssumption(
        KnowledgeAssumption(
          id: a.id,
          statement: a.statement,
          confidence: a.confidence,
          scope: a.scope,
          evidenceIds: a.evidenceIds,
          status: a.status,
          declaredAt: a.declaredAt,
          lastVerifiedAt: stamp.now,
          mergedIntoId: a.mergedIntoId,
          sync: SyncMeta(
            ownerUserId: stamp.ownerUserId,
            updatedAt: stamp.now,
            updatedByDevice: stamp.deviceId,
            hlc: stamp.hlc,
          ),
        ),
      );
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.knowledgeReviewAssumptionVerified,
        );
      }
    } catch (e) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.knowledgeReviewAssumptionVerifyFailed('$e'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FButton(
      variant: FButtonVariant.outline,
      onPress: _busy ? null : _verify,
      child: Text(l10n.knowledgeReviewVerifyAssumption),
    );
  }
}
