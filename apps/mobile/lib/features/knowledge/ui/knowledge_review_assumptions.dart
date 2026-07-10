part of 'knowledge_review_page.dart';

Future<void> _verifyAssumptions({
  required BuildContext context,
  required WidgetRef ref,
  required List<KnowledgeAssumption> assumptions,
}) async {
  if (assumptions.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  try {
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final stamper = await ref.read(mutationStamperProvider.future);
    for (final a in assumptions) {
      final stamp = await stamper.stamp();
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
    }
    ref.read(_reviewActionsRefreshProvider.notifier).state++;
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.knowledgeReviewAssumptionsBulkVerified(assumptions.length),
      );
    }
  } catch (e) {
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.knowledgeReviewAssumptionVerifyFailed('$e'),
      );
    }
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
        if (!ownerSnap.hasData) {
          return KnowledgeSection.group(
            title: l10n.knowledgeReviewAssumptionsTitle,
            children: const [
              KnowledgeLoadingState(density: KnowledgeStateDensity.section),
            ],
          );
        }
        final owner = ownerSnap.data!;
        final repoAsync = ref.watch(knowledgeRepositoryProvider);
        return repoAsync.when(
          loading: () => KnowledgeSection.group(
            title: l10n.knowledgeReviewAssumptionsTitle,
            children: const [
              KnowledgeLoadingState(density: KnowledgeStateDensity.section),
            ],
          ),
          error: (e, _) => KnowledgeSection.group(
            title: l10n.knowledgeReviewAssumptionsTitle,
            children: [
              KnowledgeErrorState(
                title: l10n.knowledgeReviewLoadFailed('$e'),
                onRetry: () => ref.invalidate(knowledgeRepositoryProvider),
                density: KnowledgeStateDensity.section,
              ),
            ],
          ),
          data: (repo) {
            final tick = ref.watch(_reviewActionsRefreshProvider);
            return FutureBuilder(
              key: ValueKey<int>(tick),
              future: repo.listOpenAssumptions(ownerUserId: owner),
              builder: (context, snap) {
                if (snap.hasError) {
                  return KnowledgeSection.group(
                    title: l10n.knowledgeReviewAssumptionsTitle,
                    children: [
                      KnowledgeErrorState(
                        title: userSafeErrorMessage(
                          context,
                          snap.error!,
                          stackTrace: snap.stackTrace,
                          operation: 'load assumption reviews',
                        ),
                        density: KnowledgeStateDensity.section,
                      ),
                    ],
                  );
                }
                final all = snap.data ?? const [];
                final now = DateTime.now().toUtc();
                final stale = all
                    .where(
                      (a) => a.daysSinceVerify(now) >= kAssumptionStaleDays,
                    )
                    .toList();
                final ordered = _orderedReviewItems<KnowledgeAssumption>(
                  items: stale,
                  order:
                      ref
                          .read(sharedPreferencesProvider)
                          .getStringList(_kReviewAssumptionOrderPrefsKey) ??
                      const <String>[],
                  idOf: (a) => a.id,
                );
                final visible = ordered
                    .take(kReviewCardMaxItems)
                    .toList(growable: false);
                return KnowledgeSection.group(
                  title: l10n.knowledgeReviewAssumptionsTitle,
                  trailing: stale.isEmpty
                      ? null
                      : _ReviewBulkActionButton(
                          label: l10n.knowledgeReviewVerifyAllAssumptions,
                          icon: FLucideIcons.badgeCheck,
                          onPress: () => _verifyAssumptions(
                            context: context,
                            ref: ref,
                            assumptions: stale,
                          ),
                        ),
                  children: [
                    if (stale.isEmpty)
                      KnowledgeEmptyState(
                        icon: FLucideIcons.badgeCheck,
                        title: l10n.knowledgeReviewAssumptionsEmpty(
                          kAssumptionStaleDays,
                        ),
                        density: KnowledgeStateDensity.section,
                      )
                    else ...[
                      _ReviewCountHint(
                        visibleCount: visible.length,
                        totalCount: stale.length,
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      _ReviewSelectableList<KnowledgeAssumption>(
                        items: visible,
                        idOf: (a) => a.id,
                        itemBuilder: (a) =>
                            _StaleAssumptionRow(assumption: a, now: now),
                        actionLabel:
                            l10n.knowledgeReviewVerifySelectedAssumptions,
                        icon: FLucideIcons.badgeCheck,
                        onBulkAction: (selected) => _verifyAssumptions(
                          context: context,
                          ref: ref,
                          assumptions: selected,
                        ),
                        orderPrefsKey: _kReviewAssumptionOrderPrefsKey,
                        onOrderChanged: (ids) => _persistReviewOrder(
                          ref: ref,
                          prefsKey: _kReviewAssumptionOrderPrefsKey,
                          visibleIds: ids,
                        ),
                      ),
                    ],
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
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
    );
  }
}
