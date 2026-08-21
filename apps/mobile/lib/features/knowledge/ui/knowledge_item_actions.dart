import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../application/knowledge_deletion_service.dart';
import '../application/knowledge_lifecycle_service.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_decision_lifecycle_sheet.dart';
import '_decision_writer.dart';
import '_object_writers.dart';
import '_routine_writer.dart';
import 'knowledge_capture_sheet.dart';
import 'knowledge_relation_sheet.dart';

class KnowledgeItemActionSet {
  const KnowledgeItemActionSet({
    required this.swipeActions,
    required this.menuActions,
  });

  final List<AppSwipeAction> swipeActions;
  final List<AppAdaptiveAction> menuActions;
}

/// Resolves the two high-frequency commands for a KnowledgeOS row and mirrors
/// them into its discoverable overflow menu.
KnowledgeItemActionSet knowledgeItemActions({
  required BuildContext context,
  required WidgetRef ref,
  required Object item,
  required bool aiAvailable,
  bool includeEditInMenu = true,
}) {
  final edit = _editAction(context: context, ref: ref, item: item);
  final contextual = _contextualAction(
    context: context,
    ref: ref,
    item: item,
    aiAvailable: aiAvailable,
  );
  final swipe = <AppSwipeAction>[edit, ?contextual];
  final link = _relationAction(context: context, ref: ref, item: item);
  return KnowledgeItemActionSet(
    swipeActions: swipe,
    menuActions: [
      for (final action in swipe)
        if (includeEditInMenu || action.id != edit.id)
          AppAdaptiveAction(
            icon: action.icon,
            title: action.label,
            onPress: action.onPressed,
          ),
      if (contextual?.id != link.id)
        AppAdaptiveAction(
          icon: link.icon,
          title: link.label,
          onPress: link.onPressed,
        ),
    ],
  );
}

AppSwipeAction _relationAction({
  required BuildContext context,
  required WidgetRef ref,
  required Object item,
}) => AppSwipeAction(
  id: 'link',
  icon: FLucideIcons.link,
  label: AppLocalizations.of(context).knowledgeItemLink,
  tone: AppSwipeActionTone.primary,
  onPressed: () => showKnowledgeRelationSheet(context, ref, item),
);

AppSwipeAction _editAction({
  required BuildContext context,
  required WidgetRef ref,
  required Object item,
}) {
  return AppSwipeAction(
    id: 'edit',
    icon: FLucideIcons.pencil,
    label: AppLocalizations.of(context).knowledgeMarkdownEdit,
    onPressed: () => switch (item) {
      KnowledgeNote value => showEditNoteSheet(context, ref, value),
      KnowledgeDecision value => showEditDecisionSheet(context, ref, value),
      KnowledgePrinciple value => showEditPrincipleSheet(context, ref, value),
      KnowledgeAssumption value => showEditAssumptionSheet(context, ref, value),
      KnowledgeConcept value => showEditConceptSheet(context, ref, value),
      KnowledgeExperiment value => showEditExperimentSheet(context, ref, value),
      KnowledgeRoutine value => showEditRoutineSheet(context, ref, value),
      _ => Future<void>.value(),
    },
  );
}

AppSwipeAction? _contextualAction({
  required BuildContext context,
  required WidgetRef ref,
  required Object item,
  required bool aiAvailable,
}) {
  final l10n = AppLocalizations.of(context);
  return switch (item) {
    KnowledgeNote value when aiAvailable => AppSwipeAction(
      id: 'organize',
      icon: FLucideIcons.sparkles,
      label: l10n.knowledgeItemOrganize,
      tone: AppSwipeActionTone.primary,
      onPressed: () => showOrganizeKnowledgeNoteSheet(context, value),
    ),
    KnowledgeNote value => _relationAction(
      context: context,
      ref: ref,
      item: value,
    ),
    KnowledgeDecision value => AppSwipeAction(
      id: 'review',
      icon: FLucideIcons.gitBranch,
      label: l10n.knowledgeItemReview,
      tone: AppSwipeActionTone.primary,
      onPressed: () => showDecisionLifecycleSheet(context, ref, value),
    ),
    KnowledgePrinciple value when value.status != PrincipleStatus.retired =>
      AppSwipeAction(
        id: value.status == PrincipleStatus.active ? 'pause' : 'resume',
        icon: value.status == PrincipleStatus.active
            ? FLucideIcons.pause
            : FLucideIcons.play,
        label: value.status == PrincipleStatus.active
            ? l10n.knowledgeItemPause
            : l10n.knowledgeItemResume,
        tone: AppSwipeActionTone.primary,
        onPressed: () => _togglePrinciple(context, ref, value),
      ),
    KnowledgePrinciple value => _relationAction(
      context: context,
      ref: ref,
      item: value,
    ),
    KnowledgeAssumption value
        when value.status == AssumptionStatus.active ||
            value.status == AssumptionStatus.weakened =>
      AppSwipeAction(
        id: 'verify',
        icon: FLucideIcons.badgeCheck,
        label: l10n.knowledgeReviewVerifyAssumption,
        tone: AppSwipeActionTone.primary,
        onPressed: () => _verifyAssumption(context, ref, value),
      ),
    KnowledgeAssumption value => _relationAction(
      context: context,
      ref: ref,
      item: value,
    ),
    KnowledgeConcept value => _relationAction(
      context: context,
      ref: ref,
      item: value,
    ),
    KnowledgeExperiment value => _experimentAction(context, ref, value),
    KnowledgeRoutine value when value.status != RoutineStatus.archived =>
      AppSwipeAction(
        id: value.status == RoutineStatus.active ? 'complete' : 'resume',
        icon: value.status == RoutineStatus.active
            ? FLucideIcons.circleCheck
            : FLucideIcons.play,
        label: value.status == RoutineStatus.active
            ? l10n.knowledgeReviewMarkDone
            : l10n.knowledgeItemResume,
        tone: AppSwipeActionTone.primary,
        onPressed: () => _runRoutineAction(context, ref, value),
      ),
    KnowledgeRoutine value => _relationAction(
      context: context,
      ref: ref,
      item: value,
    ),
    _ => null,
  };
}

AppSwipeAction _experimentAction(
  BuildContext context,
  WidgetRef ref,
  KnowledgeExperiment experiment,
) {
  final l10n = AppLocalizations.of(context);
  return switch (experiment.status) {
    ExperimentStatus.planned => AppSwipeAction(
      id: 'start-experiment',
      icon: FLucideIcons.play,
      label: l10n.knowledgeItemStartExperiment,
      tone: AppSwipeActionTone.primary,
      onPressed: () => _startExperiment(context, ref, experiment),
    ),
    ExperimentStatus.running => AppSwipeAction(
      id: 'record-result',
      icon: FLucideIcons.notebookPen,
      label: l10n.knowledgeItemRecordResult,
      tone: AppSwipeActionTone.primary,
      onPressed: () => showEditExperimentSheet(
        context,
        ref,
        experiment,
        focusEvidence: true,
      ),
    ),
    ExperimentStatus.done => AppSwipeAction(
      id: 'copy-result',
      icon: FLucideIcons.copy,
      label: l10n.knowledgeItemCopyResult,
      tone: AppSwipeActionTone.primary,
      onPressed: () => _copyExperimentResult(context, experiment),
    ),
    ExperimentStatus.abandoned => AppSwipeAction(
      id: 'restart-experiment',
      icon: FLucideIcons.rotateCcw,
      label: l10n.knowledgeItemRestartExperiment,
      tone: AppSwipeActionTone.primary,
      onPressed: () => showRestartExperimentSheet(context, ref, experiment),
    ),
  };
}

Future<void> deleteKnowledgeEntry({
  required BuildContext context,
  required WidgetRef ref,
  required KnowledgeEntryKind kind,
  required String id,
  required String title,
  required String ownerUserId,
  KnowledgeRepository? repository,
}) async {
  final l10n = AppLocalizations.of(context);
  late final KnowledgeDeletionService deletionService;
  late final KnowledgeDeleteImpact impact;
  try {
    final KnowledgeRepository repo =
        repository ?? (await ref.read(knowledgeRepositoryProvider.future));
    deletionService = KnowledgeDeletionService(
      repository: repo,
      stamper: await ref.read(mutationStamperProvider.future),
    );
    impact = await deletionService.analyze(
      ownerUserId: ownerUserId,
      kind: kind,
      id: id,
    );
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.error, l10n.commonDeleteFailed);
    }
    return;
  }
  if (!context.mounted) return;
  final confirmed = await showConfirmDialog(
    context: context,
    title: Text(l10n.knowledgeLibraryDeleteTitle),
    body: Text(
      impact.hasDependencies
          ? l10n.knowledgeLibraryDeleteImpactBody(
              title,
              impact.relationCount,
              impact.referenceCount,
              impact.attachmentCount,
            )
          : l10n.knowledgeLibraryDeleteBody(title),
    ),
    confirmLabel: l10n.commonDelete,
    cancelLabel: l10n.commonCancel,
    destructive: true,
  );
  if (confirmed != true || !context.mounted) return;

  try {
    final change = await deletionService.delete(
      ownerUserId: ownerUserId,
      kind: kind,
      id: id,
    );
    if (change == null) return;
    if (context.mounted) {
      AppMessenger.show(
        context,
        ToastKind.success,
        l10n.knowledgeDeletedToast,
        actionLabel: l10n.commonUndo,
        onAction: () => unawaited(
          _undoMutation(
            context: context,
            undo: change.undo,
            successMessage: l10n.commonUndoSucceeded,
            failureMessage: l10n.commonUndoFailed,
          ),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.error, l10n.commonDeleteFailed);
    }
  }
}

Future<void> _runLifecycleMutation({
  required BuildContext context,
  required WidgetRef ref,
  required Future<KnowledgeLifecycleChange?> Function(
    KnowledgeLifecycleService service,
  )
  apply,
  required String successMessage,
}) async {
  final l10n = AppLocalizations.of(context);
  try {
    final service = await ref.read(knowledgeLifecycleServiceProvider.future);
    final change = await apply(service);
    if (change == null) return;
    if (!context.mounted) return;
    AppMessenger.show(
      context,
      ToastKind.success,
      successMessage,
      actionLabel: l10n.commonUndo,
      onAction: () => unawaited(
        _undoMutation(
          context: context,
          undo: change.undo,
          successMessage: l10n.commonUndoSucceeded,
          failureMessage: l10n.commonUndoFailed,
        ),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.error, l10n.commonSaveFailed);
    }
  }
}

Future<void> _undoMutation({
  required BuildContext context,
  required Future<bool> Function() undo,
  required String successMessage,
  required String failureMessage,
}) async {
  try {
    final undone = await undo();
    if (!undone) {
      if (context.mounted) {
        AppMessenger.show(context, ToastKind.warning, failureMessage);
      }
      return;
    }
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.success, successMessage);
    }
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.error, failureMessage);
    }
  }
}

Future<void> _togglePrinciple(
  BuildContext context,
  WidgetRef ref,
  KnowledgePrinciple principle,
) {
  return _runLifecycleMutation(
    context: context,
    ref: ref,
    successMessage: AppLocalizations.of(context).knowledgeItemUpdatedToast,
    apply: (service) => service.togglePrinciple(
      ownerUserId: principle.sync.ownerUserId,
      id: principle.id,
    ),
  );
}

Future<void> _verifyAssumption(
  BuildContext context,
  WidgetRef ref,
  KnowledgeAssumption assumption,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showConfirmDialog(
    context: context,
    title: Text(l10n.knowledgeReviewAssumptionConfirmTitle),
    body: Text(l10n.knowledgeReviewAssumptionConfirmBody(assumption.statement)),
    confirmLabel: l10n.knowledgeReviewAssumptionStillValid,
    cancelLabel: l10n.commonCancel,
    icon: FLucideIcons.badgeCheck,
  );
  if (confirmed != true || !context.mounted) return;
  await _runLifecycleMutation(
    context: context,
    ref: ref,
    successMessage: l10n.knowledgeReviewAssumptionVerified,
    apply: (service) => service.verifyAssumption(
      ownerUserId: assumption.sync.ownerUserId,
      id: assumption.id,
    ),
  );
}

Future<void> _startExperiment(
  BuildContext context,
  WidgetRef ref,
  KnowledgeExperiment experiment,
) {
  return _runLifecycleMutation(
    context: context,
    ref: ref,
    successMessage: AppLocalizations.of(context).knowledgeItemUpdatedToast,
    apply: (service) => service.startExperiment(
      ownerUserId: experiment.sync.ownerUserId,
      id: experiment.id,
    ),
  );
}

Future<void> _runRoutineAction(
  BuildContext context,
  WidgetRef ref,
  KnowledgeRoutine routine,
) {
  return _runLifecycleMutation(
    context: context,
    ref: ref,
    successMessage: AppLocalizations.of(context).knowledgeItemUpdatedToast,
    apply: (service) => service.completeOrResumeRoutine(
      ownerUserId: routine.sync.ownerUserId,
      id: routine.id,
    ),
  );
}

Future<void> _copyExperimentResult(
  BuildContext context,
  KnowledgeExperiment experiment,
) async {
  final text = <String>[
    experiment.hypothesis,
    if (experiment.resultMd?.trim() case final result? when result.isNotEmpty)
      result,
    if (experiment.conclusionMd?.trim() case final conclusion?
        when conclusion.isNotEmpty)
      conclusion,
  ].join('\n\n');
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) {
    AppMessenger.show(
      context,
      ToastKind.success,
      AppLocalizations.of(context).knowledgeItemCopiedToast,
    );
  }
}
