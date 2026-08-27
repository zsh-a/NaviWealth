part of 'knowledge_review_page.dart';

class _StaleAssumptionsCard extends ConsumerWidget {
  const _StaleAssumptionsCard({required this.assumptions});

  final List<KnowledgeAssumption> assumptions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (assumptions.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now().toUtc();
    final orderPrefsKey = _reviewOrderPrefsKey(
      ref,
      _kReviewAssumptionOrderPrefsKey,
    );
    final ordered = _orderedReviewItems<KnowledgeAssumption>(
      items: assumptions,
      order:
          ref.read(sharedPreferencesProvider).getStringList(orderPrefsKey) ??
          const <String>[],
      idOf: (assumption) => assumption.id,
    );
    final visible = ordered.take(kReviewCardMaxItems).toList(growable: false);
    return KnowledgeSection.group(
      title: l10n.knowledgeReviewAssumptionsTitle,
      children: [
        _ReviewCountHint(
          visibleCount: visible.length,
          totalCount: assumptions.length,
        ),
        const SizedBox(height: AppSpacing.s8),
        for (final assumption in visible)
          _StaleAssumptionRow(assumption: assumption, now: now),
      ],
    );
  }
}

class _StaleAssumptionRow extends ConsumerStatefulWidget {
  const _StaleAssumptionRow({required this.assumption, required this.now});

  final KnowledgeAssumption assumption;
  final DateTime now;

  @override
  ConsumerState<_StaleAssumptionRow> createState() =>
      _StaleAssumptionRowState();
}

class _StaleAssumptionRowState extends ConsumerState<_StaleAssumptionRow> {
  bool _busy = false;

  Future<bool> _verify() async {
    if (_busy) return false;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context: context,
      title: Text(l10n.knowledgeReviewAssumptionConfirmTitle),
      body: Text(
        l10n.knowledgeReviewAssumptionConfirmBody(widget.assumption.statement),
      ),
      confirmLabel: l10n.knowledgeReviewAssumptionStillValid,
      cancelLabel: l10n.commonCancel,
      icon: FLucideIcons.badgeCheck,
    );
    if (confirmed != true || !mounted) return false;
    setState(() => _busy = true);
    try {
      final service = await ref.read(knowledgeLifecycleServiceProvider.future);
      final change = await service.verifyAssumption(
        ownerUserId: widget.assumption.sync.ownerUserId,
        id: widget.assumption.id,
      );
      if (change == null) return false;
      if (mounted) {
        ref.read(_reviewActionsRefreshProvider.notifier).state++;
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.knowledgeReviewAssumptionVerified,
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          l10n.knowledgeReviewAssumptionVerifyFailed('$e'),
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
    return _SwipeReviewAction(
      dismissKey: ValueKey<String>('assumption-review-${widget.assumption.id}'),
      label: l10n.knowledgeReviewVerifyAssumption,
      icon: FLucideIcons.badgeCheck,
      onComplete: _verify,
      child: Semantics(
        button: true,
        label: widget.assumption.statement,
        child: AppTappable(
          onPress: () => context.pushNamed(
            KnowledgeRouteNames.objectDetail,
            pathParameters: {'kind': 'assumption', 'id': widget.assumption.id},
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.knowledgeReviewAssumptionStaleSummary(
                      widget.assumption.statement,
                      widget.assumption.daysSinceVerify(widget.now),
                      widget.assumption.confidence.toStringAsFixed(2),
                    ),
                    style: typography.body.sm,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.s4),
                _ReviewIconButton(
                  icon: FLucideIcons.badgeCheck,
                  busy: _busy,
                  tooltip: l10n.knowledgeReviewVerifyAssumption,
                  onPress: _verify,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
