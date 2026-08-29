part of 'execution_widgets.dart';

class ExecutionPlanCard extends StatelessWidget {
  const ExecutionPlanCard({
    super.key,
    required this.plan,
    required this.onEdit,
    required this.onCreateAction,
    required this.onPause,
    required this.onResume,
    required this.onComplete,
    required this.onArchive,
    required this.onRecordProgress,
    this.openActionCount,
    this.blockedActionCount,
    this.onOpen,
    this.busy = false,
    this.showActions = true,
    this.showTypeLabel = false,
  });

  final ExecutionPlan plan;
  final VoidCallback onEdit;
  final VoidCallback onCreateAction;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onComplete;
  final VoidCallback onArchive;
  final VoidCallback onRecordProgress;
  final int? openActionCount;
  final int? blockedActionCount;
  final VoidCallback? onOpen;
  final bool busy;
  final bool showActions;
  final bool showTypeLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final l10n = AppLocalizations.of(context);
    return SoftCard.flat(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _CardOpenRegion(
              onOpen: onOpen,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppIconTile(
                    icon: FLucideIcons.folder,
                    color: colors.primary,
                    size: 34,
                    iconSize: AppIconSizes.sm,
                    backgroundOpacity: AppOpacity.whisper,
                    foregroundOpacity: 1,
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: _PlanBody(
                      plan: plan,
                      openActionCount: openActionCount,
                      blockedActionCount: blockedActionCount,
                      showTypeLabel: showTypeLabel,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showActions) const SizedBox(width: AppSpacing.s8),
          if (showActions && busy)
            const SizedBox(
              width: AppIconSizes.xl,
              height: AppIconSizes.xl,
              child: Center(
                child: FCircularProgress(size: FCircularProgressSizeVariant.xs),
              ),
            )
          else if (showActions)
            _LifecycleQuickButtons(
              menuTitle: plan.title,
              canPause: plan.status == ExecutionPlanStatus.active,
              canResume:
                  plan.status == ExecutionPlanStatus.paused ||
                  plan.status == ExecutionPlanStatus.completed ||
                  plan.status == ExecutionPlanStatus.archived,
              canComplete:
                  plan.status == ExecutionPlanStatus.active ||
                  plan.status == ExecutionPlanStatus.paused,
              canArchive: plan.status != ExecutionPlanStatus.archived,
              canCreateAction: plan.status.isOpen,
              editTooltip: l10n.executionEditPlanTitle,
              onPause: onPause,
              onResume: onResume,
              onComplete: onComplete,
              onArchive: onArchive,
              onRecordProgress: onRecordProgress,
              onCreateAction: onCreateAction,
              onEdit: onEdit,
            ),
        ],
      ),
    );
  }
}

class _PlanBody extends StatelessWidget {
  const _PlanBody({
    required this.plan,
    required this.openActionCount,
    required this.blockedActionCount,
    required this.showTypeLabel,
  });

  final ExecutionPlan plan;
  final int? openActionCount;
  final int? blockedActionCount;
  final bool showTypeLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTypeLabel) ...[
          Text(l10n.executionPlanField, style: context.captionLabelStyle),
          const SizedBox(height: AppSpacing.s2),
        ],
        Text(
          plan.title,
          style: context.rowTitleStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (plan.description.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(
            plan.description.trim(),
            style: context.bodyCaptionStyle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: AppSpacing.s10),
        Wrap(
          spacing: AppSpacing.s6,
          runSpacing: AppSpacing.s6,
          children: [
            AppBadge(
              label: executionPlanStatusLabel(l10n, plan.status),
              tone: plan.status == ExecutionPlanStatus.paused
                  ? AppBadgeTone.warning
                  : AppBadgeTone.info,
              size: AppBadgeSize.compact,
            ),
            if (plan.targetDate != null)
              _ExecutionTargetBadge(date: plan.targetDate!),
            ..._rollupBadges(
              l10n,
              openActionCount: openActionCount,
              blockedActionCount: blockedActionCount,
            ),
          ],
        ),
      ],
    );
  }
}

List<Widget> _rollupBadges(
  AppLocalizations l10n, {
  required int? openActionCount,
  required int? blockedActionCount,
}) {
  return <Widget>[
    if (openActionCount != null)
      AppBadge(
        label: '${l10n.executionActionsSection}: $openActionCount',
        size: AppBadgeSize.compact,
        icon: FLucideIcons.listTodo,
      ),
    if (blockedActionCount != null && blockedActionCount > 0)
      AppBadge(
        label: '${l10n.executionOverviewBlocked}: $blockedActionCount',
        tone: AppBadgeTone.error,
        size: AppBadgeSize.compact,
        icon: FLucideIcons.octagonAlert,
      ),
  ];
}

class _ExecutionTargetBadge extends StatelessWidget {
  const _ExecutionTargetBadge({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final local = date.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final overdue = day.isBefore(today);
    return AppBadge(
      label: overdue
          ? l10n.executionOverdueBadge(executionDate(context, date))
          : l10n.executionTargetBadge(executionDate(context, date)),
      tone: overdue ? AppBadgeTone.error : AppBadgeTone.info,
      size: AppBadgeSize.compact,
      icon: overdue ? FLucideIcons.triangleAlert : FLucideIcons.calendarDays,
    );
  }
}

class _LifecycleQuickButtons extends StatelessWidget {
  const _LifecycleQuickButtons({
    required this.menuTitle,
    required this.canPause,
    required this.canResume,
    required this.canComplete,
    required this.canArchive,
    required this.canCreateAction,
    required this.editTooltip,
    required this.onPause,
    required this.onResume,
    required this.onComplete,
    required this.onArchive,
    required this.onRecordProgress,
    required this.onCreateAction,
    required this.onEdit,
  });

  final String menuTitle;
  final bool canPause;
  final bool canResume;
  final bool canComplete;
  final bool canArchive;
  final bool canCreateAction;
  final String editTooltip;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onComplete;
  final VoidCallback onArchive;
  final VoidCallback onRecordProgress;
  final VoidCallback onCreateAction;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final primaryIcon = canResume
        ? FLucideIcons.play
        : canCreateAction
        ? FLucideIcons.plus
        : FLucideIcons.messageSquareText;
    final primaryTooltip = canResume
        ? l10n.executionLifecycleResume
        : canCreateAction
        ? l10n.executionCreateActionTitle
        : l10n.executionCreateProgressTitle;
    final primaryAction = canResume
        ? onResume
        : canCreateAction
        ? onCreateAction
        : onRecordProgress;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton.softPrimary(
          icon: primaryIcon,
          tooltip: primaryTooltip,
          onPress: primaryAction,
        ),
        const SizedBox(width: AppSpacing.s2),
        AppAdaptiveActionMenu(
          title: menuTitle,
          actions: <AppAdaptiveAction>[
            AppAdaptiveAction(
              icon: FLucideIcons.pencil,
              title: editTooltip,
              onPress: onEdit,
            ),
            if (canCreateAction || canResume)
              AppAdaptiveAction(
                icon: FLucideIcons.messageSquareText,
                title: l10n.executionCreateProgressTitle,
                onPress: onRecordProgress,
              ),
            if (canCreateAction && canResume)
              AppAdaptiveAction(
                icon: FLucideIcons.plus,
                title: l10n.executionCreateActionTitle,
                onPress: onCreateAction,
              ),
            if (canPause)
              AppAdaptiveAction(
                icon: FLucideIcons.pause,
                title: l10n.executionLifecyclePause,
                onPress: onPause,
              ),
            if (canComplete)
              AppAdaptiveAction(
                icon: FLucideIcons.check,
                title: l10n.executionLifecycleComplete,
                onPress: onComplete,
              ),
            if (canArchive)
              AppAdaptiveAction(
                icon: FLucideIcons.archive,
                title: l10n.executionLifecycleArchive,
                onPress: onArchive,
              ),
          ],
          triggerBuilder: (context, openMenu, focusNode) => Focus(
            focusNode: focusNode,
            child: AppIconButton(
              icon: FLucideIcons.ellipsis,
              tooltip: l10n.shellMoreActions,
              onPress: openMenu,
              size: 32,
              iconSize: AppIconSizes.xs,
              iconColor: colors.mutedForeground,
              surface: AppIconButtonSurface.softMuted,
            ),
          ),
        ),
      ],
    );
  }
}
