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
  return AppFormatters(locale: Localizations.localeOf(context))
      .date(date.toLocal());
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

String executionPlanStatusLabel(
  AppLocalizations l10n,
  ExecutionPlanStatus status,
) {
  return switch (status) {
    ExecutionPlanStatus.active => l10n.executionPlanStatusActive,
    ExecutionPlanStatus.paused => l10n.executionPlanStatusPaused,
    ExecutionPlanStatus.completed => l10n.executionPlanStatusCompleted,
    ExecutionPlanStatus.archived => l10n.executionPlanStatusArchived,
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

/// Today lens: scheduled work or blocked work.
enum ExecutionTodayFilter { today, blocked }

String executionTodayFilterLabel(
  AppLocalizations l10n,
  ExecutionTodayFilter filter,
) {
  return switch (filter) {
    ExecutionTodayFilter.today => l10n.executionOverviewFocus,
    ExecutionTodayFilter.blocked => l10n.executionOverviewBlocked,
  };
}

IconData executionTodayFilterIcon(ExecutionTodayFilter filter) {
  return switch (filter) {
    ExecutionTodayFilter.today => FLucideIcons.sun,
    ExecutionTodayFilter.blocked => FLucideIcons.octagonAlert,
  };
}

List<ExecutionAction> filteredExecutionActions({
  required ExecutionTodayFilter filter,
  required List<ExecutionAction> todayActions,
  required List<ExecutionAction> openActions,
}) {
  final open = openActions
      .where((action) => action.isOpen)
      .toList(growable: false);
  return switch (filter) {
    ExecutionTodayFilter.today => todayActions,
    ExecutionTodayFilter.blocked =>
      open
          .where((action) => action.status == ExecutionActionStatus.blocked)
          .toList(growable: false),
  };
}

String? executionRelationLabel({
  required AppLocalizations l10n,
  required String? planLabel,
}) {
  if (planLabel == null || planLabel.trim().isEmpty) return null;
  return '${l10n.executionRelationField}: ${planLabel.trim()}';
}

String? executionPlanRelationLabel(List<ExecutionPlan> plans, String? planId) {
  if (planId == null || planId.isEmpty) return null;
  for (final plan in plans) {
    if (plan.id == planId) return plan.title;
  }
  return planId;
}
