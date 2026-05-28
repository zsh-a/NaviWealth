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

