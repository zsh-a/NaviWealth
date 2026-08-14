part of 'knowledge_review_page.dart';

class _DueReviewsCard extends ConsumerWidget {
  const _DueReviewsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<String>(
      future: ref.watch(knowledgeOwnerUserIdProvider.future),
      builder: (context, ownerSnap) {
        if (!ownerSnap.hasData) return const SizedBox.shrink();
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        return repoAsync.when(
          // loading: intentionally empty — the card only appears when reviews
          // are due; a skeleton would flash for a usually-hidden section.
          loading: () => const SizedBox.shrink(),
          error: (e, stackTrace) => KnowledgeSection.group(
            title: l10n.knowledgeReviewDecisionsTitle,
            children: [
              AppEmptyState.inline(
                icon: FLucideIcons.circleX,
                title: userSafeErrorMessage(
                  context,
                  e,
                  stackTrace: stackTrace,
                  operation: 'load decision reviews',
                ),
                tone: AppEmptyStateTone.error,
                retryLabel: l10n.commonRetry,
                onRetry: () => ref.invalidate(knowledgeRepositoryProvider),
              ),
            ],
          ),
          data: (repo) {
            final tick = ref.watch(_reviewActionsRefreshProvider);
            return FutureBuilder<List<KnowledgeDecision>>(
              key: ValueKey<int>(tick),
              future: repo.listDueReviews(
                ownerUserId: owner,
                asOf: DateTime.now().toUtc(),
              ),
              builder: (context, snap) {
                if (snap.hasError) {
                  return KnowledgeSection.group(
                    title: l10n.knowledgeReviewDecisionsTitle,
                    children: [
                      AppEmptyState.inline(
                        icon: FLucideIcons.circleX,
                        title: userSafeErrorMessage(
                          context,
                          snap.error!,
                          stackTrace: snap.stackTrace,
                          operation: 'load decision reviews',
                        ),
                        tone: AppEmptyStateTone.error,
                      ),
                    ],
                  );
                }
                if (!snap.hasData) return const SizedBox.shrink();
                final list = snap.data ?? const [];
                if (list.isEmpty) return const SizedBox.shrink();
                final orderPrefsKey = _reviewOrderPrefsKey(
                  ref,
                  _kReviewDecisionOrderPrefsKey,
                );
                final ordered = _orderedReviewItems<KnowledgeDecision>(
                  items: list,
                  order:
                      ref
                          .read(sharedPreferencesProvider)
                          .getStringList(orderPrefsKey) ??
                      const <String>[],
                  idOf: (d) => d.id,
                );
                final visible = ordered
                    .take(kReviewCardMaxItems)
                    .toList(growable: false);
                return KnowledgeSection.group(
                  title: l10n.knowledgeReviewDecisionsTitle,
                  children: [
                    _ReviewCountHint(
                      visibleCount: visible.length,
                      totalCount: list.length,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    for (final decision in visible)
                      _DueDecisionRow(decision: decision),
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

class _DueDecisionRow extends ConsumerStatefulWidget {
  const _DueDecisionRow({required this.decision});

  final KnowledgeDecision decision;

  @override
  ConsumerState<_DueDecisionRow> createState() => _DueDecisionRowState();
}

class _DueDecisionRowState extends ConsumerState<_DueDecisionRow> {
  bool _busy = false;

  Future<bool> _markReviewed() async {
    if (_busy) return false;
    final reviewed = await showDecisionLifecycleSheet(
      context,
      ref,
      widget.decision,
    );
    if (reviewed != true || !mounted) return false;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context);
    try {
      final repo = await ref.read(knowledgeRepositoryProvider.future);
      final refreshed = await repo.findDecision(
        ownerUserId: widget.decision.sync.ownerUserId,
        id: widget.decision.id,
      );
      final next = await _upsertDecisionReviewDate(
        ref: ref,
        decision: refreshed ?? widget.decision,
      );
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.knowledgeReviewDecisionNextReview(
            knowledgeDate(context, next, long: true),
          ),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.knowledgeReviewDecisionReviewFailed('$e'),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final typography = context.theme.typography;
    final colors = context.theme.colors;
    final overdueDays =
        widget.decision.daysOverdue(DateTime.now().toUtc()) ?? 0;
    return _SwipeReviewAction(
      dismissKey: ValueKey<String>('decision-review-${widget.decision.id}'),
      label: l10n.knowledgeReviewDecisionReviewed,
      icon: FLucideIcons.calendarCheck,
      onComplete: _markReviewed,
      child: Semantics(
        button: true,
        label: widget.decision.question,
        child: AppTappable(
          onPress: () => context.pushNamed(
            KnowledgeRouteNames.decisionDetail,
            pathParameters: {'id': widget.decision.id},
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
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
                    widget.decision.question,
                    style: typography.body.sm,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.s4),
                Text(
                  l10n.knowledgeReviewDecisionOverdueDays(overdueDays),
                  style: context.captionStyle,
                ),
                const SizedBox(width: AppSpacing.s4),
                _ReviewIconButton(
                  icon: FLucideIcons.calendarCheck,
                  busy: _busy,
                  tooltip: l10n.knowledgeReviewDecisionReviewed,
                  onPress: _markReviewed,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<DateTime> _upsertDecisionReviewDate({
  required WidgetRef ref,
  required KnowledgeDecision decision,
}) async {
  final repo = await ref.read(knowledgeRepositoryProvider.future);
  final stamper = await ref.read(mutationStamperProvider.future);
  final stamp = await stamper.stamp();
  final nextReview = stamp.now
      .add(const Duration(days: _kDecisionReviewRescheduleDays))
      .toUtc();
  await repo.upsertDecision(
    KnowledgeDecision(
      id: decision.id,
      question: decision.question,
      options: decision.options,
      selectedLabel: decision.selectedLabel,
      rationaleMd: decision.rationaleMd,
      principleIds: decision.principleIds,
      assumptionIds: decision.assumptionIds,
      expectedOutcome: decision.expectedOutcome,
      reviewDate: nextReview,
      actualOutcomeMd: decision.actualOutcomeMd,
      status: decision.status,
      supersededByDecisionId: decision.supersededByDecisionId,
      contextSnapshot: decision.contextSnapshot,
      decidedAt: decision.decidedAt,
      mergedIntoId: decision.mergedIntoId,
      sync: SyncMeta(
        ownerUserId: stamp.ownerUserId,
        updatedAt: stamp.now,
        updatedByDevice: stamp.deviceId,
        hlc: stamp.hlc,
      ),
    ),
  );
  return nextReview;
}
