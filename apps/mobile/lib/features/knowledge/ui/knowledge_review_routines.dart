part of 'knowledge_review_page.dart';

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
          // loading: intentionally empty — the card only appears when routines
          // are due; a skeleton would flash for a usually-hidden section.
          loading: () => const SizedBox.shrink(),
          error: (e, stackTrace) => KnowledgeSection.group(
            title: l10n.knowledgeReviewRoutinesTitle,
            children: [
              KnowledgeErrorState(
                title: userSafeErrorMessage(
                  context,
                  e,
                  stackTrace: stackTrace,
                  operation: 'load routine reviews',
                ),
                onRetry: () => ref.invalidate(knowledgeRepositoryProvider),
                density: KnowledgeStateDensity.section,
              ),
            ],
          ),
          data: (repo) {
            return StreamBuilder<List<KnowledgeRoutine>>(
              stream: repo.watchRoutines(ownerUserId: owner),
              builder: (context, snap) {
                if (snap.hasError) {
                  return KnowledgeSection.group(
                    title: l10n.knowledgeReviewRoutinesTitle,
                    children: [
                      KnowledgeErrorState(
                        title: userSafeErrorMessage(
                          context,
                          snap.error!,
                          stackTrace: snap.stackTrace,
                          operation: 'load routine reviews',
                        ),
                        density: KnowledgeStateDensity.section,
                      ),
                    ],
                  );
                }
                // Quiet until the stream emits; empty due list hides the card.
                if (!snap.hasData) return const SizedBox.shrink();
                final now = DateTime.now();
                final due = (snap.data ?? const <KnowledgeRoutine>[])
                    .where((r) => shouldShowRoutineInReview(r, now))
                    .toList(growable: false);
                if (due.isEmpty) return const SizedBox.shrink();
                final ordered = _orderedReviewItems<KnowledgeRoutine>(
                  items: due,
                  order:
                      ref
                          .read(sharedPreferencesProvider)
                          .getStringList(_kReviewRoutineOrderPrefsKey) ??
                      const <String>[],
                  idOf: (r) => r.id,
                );
                final visible = ordered
                    .take(kReviewCardMaxItems)
                    .toList(growable: false);
                return KnowledgeSection.group(
                  title: l10n.knowledgeReviewRoutinesTitle,
                  trailing: _ReviewBulkActionButton(
                    label: l10n.knowledgeReviewMarkAllDone,
                    icon: FLucideIcons.checkCheck,
                    onPress: () => _markRoutinesDone(
                      context: context,
                      ref: ref,
                      routines: due,
                    ),
                  ),
                  children: [
                    _ReviewCountHint(
                      visibleCount: visible.length,
                      totalCount: due.length,
                    ),
                    const SizedBox(height: AppSpacing.s8),
                    _ReviewSelectableList<KnowledgeRoutine>(
                      items: visible,
                      idOf: (r) => r.id,
                      itemBuilder: (r) => _DueRoutineRow(routine: r),
                      actionLabel: l10n.knowledgeReviewMarkSelectedDone,
                      icon: FLucideIcons.checkCheck,
                      onBulkAction: (selected) => _markRoutinesDone(
                        context: context,
                        ref: ref,
                        routines: selected,
                      ),
                      orderPrefsKey: _kReviewRoutineOrderPrefsKey,
                      onOrderChanged: (ids) => _persistReviewOrder(
                        ref: ref,
                        prefsKey: _kReviewRoutineOrderPrefsKey,
                        visibleIds: ids,
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

Future<void> _markRoutinesDone({
  required BuildContext context,
  required WidgetRef ref,
  required List<KnowledgeRoutine> routines,
}) async {
  if (routines.isEmpty) return;
  final l10n = AppLocalizations.of(context);
  try {
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    final stamper = await ref.read(mutationStamperProvider.future);
    for (final r in routines) {
      final stamp = await stamper.stamp();
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
    }
    ref.read(_reviewActionsRefreshProvider.notifier).state++;
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.knowledgeReviewRoutinesBulkDone(routines.length),
      );
    }
  } catch (e) {
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.error,
        l10n.knowledgeReviewRoutineDoneFailed('$e'),
      );
    }
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

  Future<bool> _markDone() async {
    if (_busy) return false;
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
        ref.read(_reviewActionsRefreshProvider.notifier).state++;
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.knowledgeReviewRoutineDone(
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
          l10n.knowledgeReviewRoutineDoneFailed('$e'),
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
    final now = DateTime.now();
    final days = widget.routine.daysUntilDue(now);
    final dueLabel = days < 0
        ? l10n.knowledgeRoutineOverdueDays(-days)
        : days == 0
        ? l10n.knowledgeRoutineDueToday
        : l10n.knowledgeRoutineDueInDays(days);
    final dueColor = days < 0 ? colors.destructive : colors.mutedForeground;
    return _SwipeReviewAction(
      dismissKey: ValueKey<String>('routine-review-${widget.routine.id}'),
      label: l10n.knowledgeReviewMarkDone,
      icon: FLucideIcons.check,
      onComplete: _markDone,
      child: Padding(
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
                    style: typography.body.sm,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    l10n.knowledgeReviewRoutineMeta(
                      dueLabel,
                      widget.routine.intervalDays,
                    ),
                    style: context.captionStyle.copyWith(color: dueColor),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s4),
            _ReviewIconButton(
              icon: FLucideIcons.check,
              busy: _busy,
              tooltip: l10n.knowledgeReviewMarkDone,
              onPress: _markDone,
            ),
          ],
        ),
      ),
    );
  }
}
