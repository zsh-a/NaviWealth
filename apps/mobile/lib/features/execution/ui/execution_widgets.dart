import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../core/format/formatters.dart';
import '../../../core/lifeos/action_outcome.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../domain/execution_models.dart';

part 'execution_card_widgets.dart';
part 'execution_action_card.dart';
part 'execution_lifecycle_cards.dart';
part 'execution_progress_card.dart';
part 'execution_overview_widgets.dart';

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

String executionProjectStatusLabel(
  AppLocalizations l10n,
  ExecutionProjectStatus status,
) {
  return switch (status) {
    ExecutionProjectStatus.active => l10n.executionProjectStatusActive,
    ExecutionProjectStatus.paused => l10n.executionProjectStatusPaused,
    ExecutionProjectStatus.completed => l10n.executionProjectStatusCompleted,
    ExecutionProjectStatus.archived => l10n.executionProjectStatusArchived,
  };
}

String executionCommitmentStatusLabel(
  AppLocalizations l10n,
  ExecutionCommitmentStatus status,
) {
  return switch (status) {
    ExecutionCommitmentStatus.active => l10n.executionProjectStatusActive,
    ExecutionCommitmentStatus.paused => l10n.executionProjectStatusPaused,
    ExecutionCommitmentStatus.completed => l10n.executionProjectStatusCompleted,
    ExecutionCommitmentStatus.archived => l10n.executionProjectStatusArchived,
  };
}

String executionPriorityLabel(
  AppLocalizations l10n,
  ExecutionPriority priority,
) {
  return switch (priority) {
    ExecutionPriority.low => l10n.executionPriorityLow,
    ExecutionPriority.normal => l10n.executionPriorityNormal,
    ExecutionPriority.high => l10n.executionPriorityHigh,
  };
}

String executionHorizonLabel(AppLocalizations l10n, ExecutionHorizon horizon) {
  return switch (horizon) {
    ExecutionHorizon.week => l10n.executionHorizonWeek,
    ExecutionHorizon.month => l10n.executionHorizonMonth,
    ExecutionHorizon.quarter => l10n.executionHorizonQuarter,
    ExecutionHorizon.open => l10n.executionHorizonOpen,
  };
}

String executionProgressKindLabel(
  AppLocalizations l10n,
  ExecutionProgressKind kind,
) {
  return switch (kind) {
    ExecutionProgressKind.blocker => l10n.executionProgressKindBlocker,
    ExecutionProgressKind.completion => l10n.executionProgressKindCompletion,
    ExecutionProgressKind.dropped => l10n.executionProgressKindDropped,
    ExecutionProgressKind.scopeChange => l10n.executionProgressKindScope,
    ExecutionProgressKind.checkin => l10n.executionProgressKindCheckin,
  };
}

/// Today lens: focus (today's set), blocked, or all open work.
enum ExecutionTodayFilter { focus, blocked, open }

String executionTodayFilterLabel(
  AppLocalizations l10n,
  ExecutionTodayFilter filter,
) {
  return switch (filter) {
    ExecutionTodayFilter.focus => l10n.executionOverviewFocus,
    ExecutionTodayFilter.blocked => l10n.executionOverviewBlocked,
    ExecutionTodayFilter.open => l10n.executionOverviewOpen,
  };
}

IconData executionTodayFilterIcon(ExecutionTodayFilter filter) {
  return switch (filter) {
    ExecutionTodayFilter.focus => FLucideIcons.sun,
    ExecutionTodayFilter.blocked => FLucideIcons.octagonAlert,
    ExecutionTodayFilter.open => FLucideIcons.inbox,
  };
}

List<ExecutionAction> filteredExecutionActions({
  required ExecutionTodayFilter filter,
  required List<ExecutionAction> todayActions,
  required List<ExecutionAction> openActions,
  required DateTime now,
}) {
  final open = openActions
      .where((action) => action.isOpen)
      .toList(growable: false);
  return switch (filter) {
    ExecutionTodayFilter.focus => todayActions,
    ExecutionTodayFilter.blocked =>
      open
          .where((action) => action.status == ExecutionActionStatus.blocked)
          .toList(growable: false),
    ExecutionTodayFilter.open => open,
  };
}

String? executionProjectRelationLabel(
  List<ExecutionProject> projects,
  String? projectId,
) {
  if (projectId == null || projectId.isEmpty) return null;
  for (final project in projects) {
    if (project.id == projectId) return project.title;
  }
  return projectId;
}

String? executionCommitmentRelationLabel(
  List<ExecutionCommitment> commitments,
  String? commitmentId,
) {
  if (commitmentId == null || commitmentId.isEmpty) return null;
  for (final commitment in commitments) {
    if (commitment.id == commitmentId) return commitment.title;
  }
  return commitmentId;
}
