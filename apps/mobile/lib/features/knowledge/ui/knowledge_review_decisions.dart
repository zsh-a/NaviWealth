part of 'knowledge_review_page.dart';

class _DueReviewsCard extends ConsumerWidget {
  const _DueReviewsCard({required this.decisions});

  final List<KnowledgeDecision> decisions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (decisions.isEmpty) return const SizedBox.shrink();
    final orderPrefsKey = _reviewOrderPrefsKey(
      ref,
      _kReviewDecisionOrderPrefsKey,
    );
    final ordered = _orderedReviewItems<KnowledgeDecision>(
      items: decisions,
      order:
          ref.read(sharedPreferencesProvider).getStringList(orderPrefsKey) ??
          const <String>[],
      idOf: (decision) => decision.id,
    );
    final visible = ordered.take(kReviewCardMaxItems).toList(growable: false);
    return KnowledgeSection.group(
      title: l10n.knowledgeReviewDecisionsTitle,
      children: [
        _ReviewCountHint(
          visibleCount: visible.length,
          totalCount: decisions.length,
        ),
        const SizedBox(height: AppSpacing.s8),
        for (final decision in visible) _DueDecisionRow(decision: decision),
      ],
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
      revisitConditions: decision.revisitConditions,
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
