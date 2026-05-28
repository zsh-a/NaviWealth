/// KnowledgeOS Review tab (`docs/knowledgeos-domain.md` §5).
///
/// 3 cards: due Routines (next_due_at within 7d), due Decisions
/// (review_date passed) and stale Assumptions (active && > 90d
/// unverified). Forui-only chrome — no Material.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../agents/assumption_agent.dart';
import '../agents/routine_due_agent.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_ai_suggestions_card.dart';
import '_widgets.dart';

class KnowledgeReviewPage extends ConsumerWidget {
  const KnowledgeReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FScaffold(
      header: const FHeader.nested(title: Text('复盘 · KnowledgeOS')),
      childPad: false,
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
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) return const SizedBox.shrink();
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        return repoAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => KnowledgeSection.group(
            title: '本周到期的 Routine',
            children: [
              Text(
                '加载失败：$e',
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
                final asOf = now.add(kRoutineDueLookahead);
                final due = (snap.data ?? const <KnowledgeRoutine>[])
                    .where(
                      (r) =>
                          r.status == RoutineStatus.active &&
                          !r.nextDueAt.isAfter(asOf),
                    )
                    .toList(growable: false);
                final typography = context.theme.typography;
                final colors = context.theme.colors;
                return KnowledgeSection.group(
                  title: '本周到期的 Routine',
                  children: [
                    if (due.isEmpty)
                      Text(
                        '未来 7 天内没有到期的 Routine。',
                        style: typography.sm
                            .copyWith(color: colors.mutedForeground),
                      )
                    else
                      ...due.take(5).map(
                            (r) => _DueRoutineRow(routine: r),
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    final now = DateTime.now();
    final days = widget.routine.daysUntilDue(now);
    final dueLabel = days < 0
        ? '已逾期 ${-days} 天'
        : days == 0
            ? '今日到期'
            : '$days 天后';
    final dueColor = days < 0 ? colors.destructive : colors.mutedForeground;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            FLucideIcons.repeat,
            size: 14,
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
                  '$dueLabel · 每 ${widget.routine.intervalDays} 天',
                  style: typography.xs.copyWith(color: dueColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          FButton(
            variant: FButtonVariant.outline,
            onPress: _busy ? null : _markDone,
            child: Text(_busy ? '...' : '已处理'),
          ),
        ],
      ),
    );
  }
}

class _DueReviewsCard extends ConsumerWidget {
  const _DueReviewsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<String>(
      future: ref.watch(currentUserIdProvider)(),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) return const SizedBox.shrink();
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        return repoAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => KnowledgeSection.group(
            title: '待复盘的 Decision',
            children: [
              Text(
                '加载失败：$e',
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
                  title: '待复盘的 Decision',
                  children: [
                    if (list.isEmpty)
                      Text(
                        '当前没有到期的 Decision。',
                        style: typography.sm
                            .copyWith(color: colors.mutedForeground),
                      )
                    else
                      ...list.take(5).map(
                            (d) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    FLucideIcons.calendar,
                                    size: 14,
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
                                    '${d.daysOverdue(DateTime.now().toUtc()) ?? 0} 天',
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
                  title: '未校验的 Assumption',
                  children: [
                    if (stale.isEmpty)
                      Text(
                        '所有 active 的 Assumption 都在 $kAssumptionStaleDays 天内校验过。',
                        style: typography.sm
                            .copyWith(color: colors.mutedForeground),
                      )
                    else
                      ...stale.take(5).map(
                            (a) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                '· ${a.statement}（${a.daysSinceVerify(now)} 天, conf ${a.confidence.toStringAsFixed(2)}）',
                                style: typography.sm,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
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

