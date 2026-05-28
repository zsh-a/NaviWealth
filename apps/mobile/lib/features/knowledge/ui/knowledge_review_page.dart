/// KnowledgeOS Review tab (`docs/knowledgeos-domain.md` §5).
///
/// 2 cards: due Decisions (review_date passed) and stale Assumptions
/// (active && > 90d unverified). Forui-only chrome — no Material.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../design_system/design_system.dart';
import '../agents/assumption_agent.dart';
import '../data/providers.dart';

class KnowledgeReviewPage extends ConsumerWidget {
  const KnowledgeReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FScaffold(
      header: const FHeader.nested(title: Text('Review · KnowledgeOS')),
      childPad: false,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.s16),
        children: const <Widget>[
          _DueReviewsCard(),
          SizedBox(height: AppSpacing.s16),
          _StaleAssumptionsCard(),
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
          error: (e, _) => _CardShell(
            title: 'To-review decisions',
            children: [Text('加载失败:$e')],
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
                return _CardShell(
                  title: 'To-review decisions',
                  children: [
                    if (list.isEmpty)
                      Text(
                        '当前无到期 decision。',
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
                                    ),
                                  ),
                                  Text(
                                    '${d.daysOverdue(DateTime.now().toUtc()) ?? 0}d',
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
                return _CardShell(
                  title: 'Unverified assumptions',
                  children: [
                    if (stale.isEmpty)
                      Text(
                        '所有 active 假设都在 $kAssumptionStaleDays 天内校验过。',
                        style: typography.sm
                            .copyWith(color: colors.mutedForeground),
                      )
                    else
                      ...stale.take(5).map(
                            (a) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                '· ${a.statement} (${a.daysSinceVerify(now)}d, conf ${a.confidence.toStringAsFixed(2)})',
                                style: typography.sm,
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

class _CardShell extends StatelessWidget {
  const _CardShell({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final typography = context.theme.typography;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: typography.md.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.s8),
          ...children,
        ],
      ),
    );
  }
}
