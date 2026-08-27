part of 'knowledge_review_page.dart';

class _DueRoutinesCard extends ConsumerWidget {
  const _DueRoutinesCard({required this.routines});

  final List<KnowledgeRoutine> routines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (routines.isEmpty) return const SizedBox.shrink();
    final orderPrefsKey = _reviewOrderPrefsKey(
      ref,
      _kReviewRoutineOrderPrefsKey,
    );
    final ordered = _orderedReviewItems<KnowledgeRoutine>(
      items: routines,
      order:
          ref.read(sharedPreferencesProvider).getStringList(orderPrefsKey) ??
          const <String>[],
      idOf: (routine) => routine.id,
    );
    final visible = ordered.take(kReviewCardMaxItems).toList(growable: false);
    return KnowledgeSection.group(
      title: l10n.knowledgeReviewRoutinesTitle,
      trailing: _ReviewBulkActionButton(
        label: l10n.knowledgeReviewMarkAllDone,
        icon: FLucideIcons.checkCheck,
        onPress: () =>
            _markRoutinesDone(context: context, ref: ref, routines: routines),
      ),
      children: [
        _ReviewCountHint(
          visibleCount: visible.length,
          totalCount: routines.length,
        ),
        const SizedBox(height: AppSpacing.s8),
        _ReviewSelectableList<KnowledgeRoutine>(
          items: visible,
          idOf: (routine) => routine.id,
          itemBuilder: (routine) => _DueRoutineRow(routine: routine),
          actionLabel: l10n.knowledgeReviewMarkSelectedDone,
          icon: FLucideIcons.checkCheck,
          onBulkAction: (selected) =>
              _markRoutinesDone(context: context, ref: ref, routines: selected),
          orderPrefsKey: orderPrefsKey,
          onOrderChanged: (ids) => _persistReviewOrder(
            ref: ref,
            prefsKey: orderPrefsKey,
            visibleIds: ids,
          ),
        ),
      ],
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
    final service = await ref.read(knowledgeLifecycleServiceProvider.future);
    for (final r in routines) {
      await service.completeOrResumeRoutine(
        ownerUserId: r.sync.ownerUserId,
        id: r.id,
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
      final service = await ref.read(knowledgeLifecycleServiceProvider.future);
      final change = await service.completeOrResumeRoutine(
        ownerUserId: widget.routine.sync.ownerUserId,
        id: widget.routine.id,
      );
      if (change == null) return false;
      if (mounted) {
        ref.read(_reviewActionsRefreshProvider.notifier).state++;
        final repo = await ref.read(knowledgeRepositoryProvider.future);
        final updated = await repo.findRoutine(
          ownerUserId: widget.routine.sync.ownerUserId,
          id: widget.routine.id,
        );
        if (!mounted || updated == null) return true;
        AppMessenger.show(
          context,
          ToastKind.success,
          l10n.knowledgeReviewRoutineDone(
            knowledgeDate(context, updated.nextDueAt, long: true),
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
      child: Semantics(
        button: true,
        label: widget.routine.statement,
        child: AppTappable(
          onPress: () => context.pushNamed(
            KnowledgeRouteNames.objectDetail,
            pathParameters: {'kind': 'routine', 'id': widget.routine.id},
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
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
                const SizedBox(width: AppSpacing.s2),
                Icon(
                  FLucideIcons.chevronRight,
                  size: AppIconSizes.xs,
                  color: colors.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
