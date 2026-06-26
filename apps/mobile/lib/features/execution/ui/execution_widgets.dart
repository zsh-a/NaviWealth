import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/execution_models.dart';

String executionDate(BuildContext context, DateTime date) {
  return AppFormatters(
    locale: Localizations.localeOf(context),
  ).date(date.toLocal());
}

String executionStatusLabel(
  AppLocalizations l10n,
  ExecutionActionStatus status,
) {
  return switch (status) {
    ExecutionActionStatus.todo => l10n.executionStatusTodo,
    ExecutionActionStatus.doing => l10n.executionStatusDoing,
    ExecutionActionStatus.blocked => l10n.executionStatusBlocked,
    ExecutionActionStatus.done => l10n.executionStatusDone,
    ExecutionActionStatus.dropped => l10n.executionStatusDropped,
  };
}

class ExecutionStateView extends StatelessWidget {
  const ExecutionStateView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: icon,
      title: title,
      message: message,
      action: action,
    );
  }
}

class ExecutionActionCard extends StatelessWidget {
  const ExecutionActionCard({
    super.key,
    required this.action,
    required this.onStart,
    required this.onBlock,
    required this.onResume,
    required this.onDone,
  });

  final ExecutionAction action;
  final VoidCallback onStart;
  final VoidCallback onBlock;
  final VoidCallback onResume;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.theme.colors;
    final isBlocked = action.status == ExecutionActionStatus.blocked;
    return SoftCard(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIconTile(
                icon: isBlocked
                    ? FLucideIcons.octagonAlert
                    : FLucideIcons.circle,
                color: isBlocked ? colors.destructive : colors.primary,
                size: 32,
                iconSize: AppIconSizes.h18,
                backgroundOpacity: AppOpacity.whisper,
                foregroundOpacity: 1,
              ),
              const SizedBox(width: AppSpacing.s10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      style: context.labelStyle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (action.note.trim().isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.s4),
                      Text(
                        action.note.trim(),
                        style: context.captionStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.s8),
                    Wrap(
                      spacing: AppSpacing.s6,
                      runSpacing: AppSpacing.s6,
                      children: [
                        AppBadge(
                          label: executionStatusLabel(l10n, action.status),
                          outlined: true,
                        ),
                        if (action.priority == ExecutionPriority.high)
                          AppBadge(
                            label: l10n.executionPriorityHigh,
                            outlined: true,
                          ),
                        if (action.dueAt != null)
                          AppBadge(
                            label: l10n.executionDueBadge(
                              executionDate(context, action.dueAt!),
                            ),
                            outlined: true,
                          ),
                        if (action.source.labelSnapshot != null &&
                            action.source.labelSnapshot!.isNotEmpty)
                          AppBadge(
                            label: action.source.labelSnapshot!,
                            outlined: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s10),
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              if (action.status == ExecutionActionStatus.todo)
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: onStart,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FLucideIcons.play, size: AppIconSizes.xs),
                      const SizedBox(width: AppSpacing.s6),
                      Text(l10n.executionActionStart),
                    ],
                  ),
                ),
              if (action.status == ExecutionActionStatus.blocked)
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: onResume,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FLucideIcons.rotateCcw, size: AppIconSizes.xs),
                      const SizedBox(width: AppSpacing.s6),
                      Text(l10n.executionActionResume),
                    ],
                  ),
                )
              else
                FButton(
                  variant: FButtonVariant.outline,
                  onPress: onBlock,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FLucideIcons.pause, size: AppIconSizes.xs),
                      const SizedBox(width: AppSpacing.s6),
                      Text(l10n.executionActionBlock),
                    ],
                  ),
                ),
              FButton(
                onPress: onDone,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FLucideIcons.check, size: AppIconSizes.xs),
                    const SizedBox(width: AppSpacing.s6),
                    Text(l10n.executionActionDone),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
