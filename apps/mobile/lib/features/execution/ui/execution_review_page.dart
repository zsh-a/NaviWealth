import 'package:flutter/material.dart' show RefreshIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell_chrome.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/execution_route_paths.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';
import 'execution_action_card_controller.dart';
import 'execution_action_sheet.dart';
import 'execution_delete_confirm.dart';
import 'execution_progress_sheet.dart';
import 'execution_widgets.dart';

class ExecutionReviewPage extends ConsumerWidget {
  const ExecutionReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.executionReviewTitle,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.plus),
          semanticsLabel: l10n.executionCreateProgressTitle,
          onPress: () => showExecutionProgressSheet(context: context, ref: ref),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(executionRecentProgressProvider);
          ref.invalidate(executionClosedActionsProvider);
          ref.invalidate(executionReviewRelationsProvider);
          await Future.wait([
            ref.read(executionRecentProgressProvider.future),
            ref.read(executionClosedActionsProvider.future),
          ]);
        },
        child: _ReviewBody(),
      ),
    );
  }
}

class _ReviewBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final progressAsync = ref.watch(executionRecentProgressProvider);
    final closedActionsAsync = ref.watch(executionClosedActionsProvider);
    final relations = ref.watch(executionReviewRelationsProvider).value;
    final error = progressAsync.error ?? closedActionsAsync.error;
    if (error != null) {
      return ExecutionStateView(
        icon: FLucideIcons.circleX,
        title: l10n.commonError,
        message: '$error',
      );
    }
    if ((progressAsync.isLoading && !progressAsync.hasValue) ||
        (closedActionsAsync.isLoading && !closedActionsAsync.hasValue)) {
      return const Center(child: FCircularProgress());
    }

    final entries = progressAsync.value ?? const <ExecutionProgressEntry>[];
    final closedActions = closedActionsAsync.value ?? const <ExecutionAction>[];
    if (entries.isEmpty && closedActions.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: shellTabContentPadding(context),
        children: [
          ExecutionStateView(
            icon: FLucideIcons.clipboardCheck,
            title: l10n.executionReviewEmptyTitle,
            message: l10n.executionReviewEmptyBody,
            action: FButton(
              onPress: () =>
                  showExecutionProgressSheet(context: context, ref: ref),
              child: Text(l10n.executionCreateProgressTitle),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: shellTabContentPadding(context),
      children: [
        if (entries.isNotEmpty) ...[
          ExecutionSectionHeader(
            title: l10n.executionReviewTitle,
            count: entries.length,
            icon: FLucideIcons.clipboardCheck,
          ),
          const SizedBox(height: AppSpacing.s8),
          for (final entry in entries) ...[
            ExecutionProgressCard(
              entry: entry,
              actionLabel:
                  relations?.actionLabel(entry.actionId) ??
                  _fallbackRelationLabel(entry.actionId),
              projectLabel:
                  relations?.projectLabel(entry.projectId) ??
                  _fallbackRelationLabel(entry.projectId),
              commitmentLabel:
                  relations?.commitmentLabel(entry.commitmentId) ??
                  _fallbackRelationLabel(entry.commitmentId),
              onDelete: () => _deleteProgress(context, ref, entry),
            ),
            const SizedBox(height: AppSpacing.s8),
          ],
          const SizedBox(height: AppSpacing.s8),
        ],
        if (closedActions.isNotEmpty) ...[
          ExecutionSectionHeader(
            title: l10n.executionClosedActionsSection,
            count: closedActions.length,
            icon: FLucideIcons.archive,
          ),
          const SizedBox(height: AppSpacing.s8),
          for (final action in closedActions) ...[
            ExecutionActionCardController(
              action: action,
              projectLabel:
                  relations?.projectLabel(action.projectId) ??
                  _fallbackRelationLabel(action.projectId),
              commitmentLabel:
                  relations?.commitmentLabel(action.commitmentId) ??
                  _fallbackRelationLabel(action.commitmentId),
              onOpen: () => context.push(ExecutionRoutes.action(action.id)),
              onEdit: () => showExecutionActionSheet(
                context: context,
                ref: ref,
                action: action,
              ),
              onRecordProgress: () => showExecutionProgressSheet(
                context: context,
                ref: ref,
                action: action,
              ),
              blockedProgressNote: l10n.executionProgressBlockedDefault,
              doneProgressNote: l10n.executionProgressDoneDefault,
              droppedProgressNote: l10n.executionProgressDroppedDefault,
            ),
            const SizedBox(height: AppSpacing.s8),
          ],
        ],
      ],
    );
  }
}

String? _fallbackRelationLabel(String? id) {
  return id == null || id.isEmpty ? null : id;
}

Future<void> _deleteProgress(
  BuildContext context,
  WidgetRef ref,
  ExecutionProgressEntry entry,
) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await confirmExecutionDelete(
    context: context,
    item: _progressDeleteLabel(l10n, entry),
  );
  if (!confirmed || !context.mounted) return;

  final repo = await ref.read(executionRepositoryProvider.future);
  final sync = await stampExecutionSync(ref);
  await repo.softDeleteProgress(progress: entry, sync: sync);
}

String _progressDeleteLabel(
  AppLocalizations l10n,
  ExecutionProgressEntry entry,
) {
  final note = entry.note.trim();
  if (note.isEmpty) {
    return executionProgressKindLabel(l10n, entry.kind);
  }
  if (note.length <= 36) return note;
  return '${note.substring(0, 36)}...';
}
