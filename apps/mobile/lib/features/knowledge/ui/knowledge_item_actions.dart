import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../core/sync/mutation_context.dart';
import '../../../core/sync/sync_meta.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/knowledge_repository.dart';
import '../data/providers.dart';
import '../domain/knowledge_models.dart';
import '_decision_lifecycle_sheet.dart';
import '_decision_writer.dart';
import '_object_writers.dart';
import '_routine_writer.dart';
import 'knowledge_capture_sheet.dart';

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
}) {
  final edit = _editAction(context: context, ref: ref, item: item);
  final contextual = _contextualAction(
    context: context,
    ref: ref,
    item: item,
    aiAvailable: aiAvailable,
  );
  final swipe = <AppSwipeAction>[edit, ?contextual];
  return KnowledgeItemActionSet(
    swipeActions: swipe,
    menuActions: [
      for (final action in swipe)
        AppAdaptiveAction(
          icon: action.icon,
          title: action.label,
          onPress: action.onPressed,
        ),
    ],
  );
}

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
    KnowledgeNote() => null,
    KnowledgeDecision value => AppSwipeAction(
      id: 'review',
      icon: FLucideIcons.gitBranch,
      label: l10n.knowledgeItemReview,
      tone: AppSwipeActionTone.primary,
      onPressed: () => showDecisionLifecycleSheet(context, ref, value),
    ),
    KnowledgePrinciple value => AppSwipeAction(
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
    KnowledgeAssumption() => null,
    KnowledgeConcept value => AppSwipeAction(
      id: 'copy-summary',
      icon: FLucideIcons.copy,
      label: l10n.knowledgeItemCopySummary,
      tone: AppSwipeActionTone.primary,
      onPressed: () => _copyConcept(context, value),
    ),
    KnowledgeExperiment value => _experimentAction(context, ref, value),
    KnowledgeRoutine value => AppSwipeAction(
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
      onPressed: () => _startExperiment(context, ref, experiment),
    ),
  };
}

Future<void> deleteKnowledgeEntry({
  required BuildContext context,
  required WidgetRef ref,
  required KnowledgeEntryKind kind,
  required String id,
  required String title,
  KnowledgeRepository? repository,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showConfirmDialog(
    context: context,
    title: Text(l10n.knowledgeLibraryDeleteTitle),
    body: Text(l10n.knowledgeLibraryDeleteBody(title)),
    confirmLabel: l10n.commonDelete,
    cancelLabel: l10n.commonCancel,
    destructive: true,
  );
  if (confirmed != true || !context.mounted) return;

  try {
    final KnowledgeRepository repo =
        repository ?? (await ref.read(knowledgeRepositoryProvider.future));
    final sync = await _stamp(ref);
    await repo.deleteEntry(
      kind: kind,
      id: id,
      sync: sync.copyWith(deletedAt: sync.updatedAt),
    );
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.success, l10n.knowledgeDeletedToast);
    }
  } catch (_) {
    if (context.mounted) {
      AppMessenger.show(context, ToastKind.error, l10n.commonDeleteFailed);
    }
  }
}

Future<SyncMeta> _stamp(WidgetRef ref) async {
  final stamper = await ref.read(mutationStamperProvider.future);
  final stamp = await stamper.stamp();
  return SyncMeta(
    ownerUserId: stamp.ownerUserId,
    updatedAt: stamp.now,
    updatedByDevice: stamp.deviceId,
    hlc: stamp.hlc,
  );
}

Future<void> _runUndoableMutation({
  required BuildContext context,
  required WidgetRef ref,
  required Future<void> Function(KnowledgeRepository repo, SyncMeta sync) apply,
  required Future<void> Function(KnowledgeRepository repo, SyncMeta sync) undo,
  required String successMessage,
}) async {
  final l10n = AppLocalizations.of(context);
  try {
    final repo = await ref.read(knowledgeRepositoryProvider.future);
    await apply(repo, await _stamp(ref));
    if (!context.mounted) return;
    AppMessenger.show(
      context,
      ToastKind.success,
      successMessage,
      actionLabel: l10n.commonUndo,
      onAction: () => unawaited(
        _undoMutation(
          context: context,
          ref: ref,
          repository: repo,
          undo: undo,
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
  required WidgetRef ref,
  required KnowledgeRepository repository,
  required Future<void> Function(KnowledgeRepository repo, SyncMeta sync) undo,
  required String successMessage,
  required String failureMessage,
}) async {
  try {
    await undo(repository, await _stamp(ref));
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
  final next = principle.status == PrincipleStatus.active
      ? PrincipleStatus.paused
      : PrincipleStatus.active;
  return _runUndoableMutation(
    context: context,
    ref: ref,
    successMessage: AppLocalizations.of(context).knowledgeItemUpdatedToast,
    apply: (repo, sync) => repo.upsertPrinciple(
      _principleWith(principle, status: next, sync: sync),
    ),
    undo: (repo, sync) => repo.upsertPrinciple(
      _principleWith(principle, status: principle.status, sync: sync),
    ),
  );
}

KnowledgePrinciple _principleWith(
  KnowledgePrinciple value, {
  required PrincipleStatus status,
  required SyncMeta sync,
}) => KnowledgePrinciple(
  id: value.id,
  statement: value.statement,
  rationaleMd: value.rationaleMd,
  scope: value.scope,
  status: status,
  declaredAt: value.declaredAt,
  mergedIntoId: value.mergedIntoId,
  sync: sync,
);

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
  await _runUndoableMutation(
    context: context,
    ref: ref,
    successMessage: l10n.knowledgeReviewAssumptionVerified,
    apply: (repo, sync) => repo.upsertAssumption(
      _assumptionWith(assumption, lastVerifiedAt: sync.updatedAt, sync: sync),
    ),
    undo: (repo, sync) => repo.upsertAssumption(
      _assumptionWith(
        assumption,
        lastVerifiedAt: assumption.lastVerifiedAt,
        sync: sync,
      ),
    ),
  );
}

KnowledgeAssumption _assumptionWith(
  KnowledgeAssumption value, {
  required DateTime? lastVerifiedAt,
  required SyncMeta sync,
}) => KnowledgeAssumption(
  id: value.id,
  statement: value.statement,
  confidence: value.confidence,
  scope: value.scope,
  evidenceIds: value.evidenceIds,
  status: value.status,
  declaredAt: value.declaredAt,
  lastVerifiedAt: lastVerifiedAt,
  mergedIntoId: value.mergedIntoId,
  sync: sync,
);

Future<void> _startExperiment(
  BuildContext context,
  WidgetRef ref,
  KnowledgeExperiment experiment,
) {
  return _runUndoableMutation(
    context: context,
    ref: ref,
    successMessage: AppLocalizations.of(context).knowledgeItemUpdatedToast,
    apply: (repo, sync) => repo.upsertExperiment(
      _experimentWith(
        experiment,
        status: ExperimentStatus.running,
        endedAt: null,
        sync: sync,
      ),
    ),
    undo: (repo, sync) => repo.upsertExperiment(
      _experimentWith(
        experiment,
        status: experiment.status,
        endedAt: experiment.endedAt,
        sync: sync,
      ),
    ),
  );
}

KnowledgeExperiment _experimentWith(
  KnowledgeExperiment value, {
  required ExperimentStatus status,
  required DateTime? endedAt,
  required SyncMeta sync,
}) => KnowledgeExperiment(
  id: value.id,
  hypothesis: value.hypothesis,
  methodMd: value.methodMd,
  metrics: value.metrics,
  status: status,
  resultMd: value.resultMd,
  conclusionMd: value.conclusionMd,
  targetAssumptionId: value.targetAssumptionId,
  startedAt: value.startedAt,
  endedAt: endedAt,
  mergedIntoId: value.mergedIntoId,
  sync: sync,
);

Future<void> _runRoutineAction(
  BuildContext context,
  WidgetRef ref,
  KnowledgeRoutine routine,
) {
  return _runUndoableMutation(
    context: context,
    ref: ref,
    successMessage: AppLocalizations.of(context).knowledgeItemUpdatedToast,
    apply: (repo, sync) {
      final active = routine.status == RoutineStatus.active;
      return repo.upsertRoutine(
        _routineWith(
          routine,
          status: RoutineStatus.active,
          nextDueAt: active
              ? sync.updatedAt.add(Duration(days: routine.intervalDays))
              : routine.nextDueAt,
          lastDoneAt: active ? sync.updatedAt : routine.lastDoneAt,
          sync: sync,
        ),
      );
    },
    undo: (repo, sync) => repo.upsertRoutine(
      _routineWith(
        routine,
        status: routine.status,
        nextDueAt: routine.nextDueAt,
        lastDoneAt: routine.lastDoneAt,
        sync: sync,
      ),
    ),
  );
}

KnowledgeRoutine _routineWith(
  KnowledgeRoutine value, {
  required RoutineStatus status,
  required DateTime nextDueAt,
  required DateTime? lastDoneAt,
  required SyncMeta sync,
}) => KnowledgeRoutine(
  id: value.id,
  statement: value.statement,
  intervalDays: value.intervalDays,
  nextDueAt: nextDueAt,
  lastDoneAt: lastDoneAt,
  scope: value.scope,
  status: status,
  createdAt: value.createdAt,
  sync: sync,
);

Future<void> _copyConcept(
  BuildContext context,
  KnowledgeConcept concept,
) async {
  await Clipboard.setData(
    ClipboardData(
      text: [
        concept.name,
        if (concept.summaryMd.trim().isNotEmpty) concept.summaryMd.trim(),
      ].join('\n\n'),
    ),
  );
  if (context.mounted) {
    AppMessenger.show(
      context,
      ToastKind.success,
      AppLocalizations.of(context).knowledgeItemCopiedToast,
    );
  }
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
