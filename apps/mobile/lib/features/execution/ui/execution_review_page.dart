import 'package:flutter/material.dart' show RefreshIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/agents/agent_artifact.dart';
import '../../../core/ai/agents/agent_run_controller.dart';
import '../../../core/ai/agents/ui/agent_result_card.dart';
import '../../../core/shell/shell_chrome.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../agents/providers.dart' as execution_agent_providers;
import '../agents/review_agent.dart' show kExecutionReviewAgentId;
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
        ShellHeaderActionSpec(
          icon: FLucideIcons.plus,
          label: l10n.executionCreateProgressTitle,
          onPress: () => showExecutionProgressSheet(context: context),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(
            execution_agent_providers.latestExecutionReviewResultsProvider,
          );
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
      return AppEmptyState.error(
        title: l10n.commonLoadFailed,
        message: userSafeErrorMessage(context, error),
        retryLabel: l10n.commonRetry,
        onRetry: () {
          ref.invalidate(executionRecentProgressProvider);
          ref.invalidate(executionClosedActionsProvider);
        },
      );
    }
    if ((progressAsync.isLoading && !progressAsync.hasValue) ||
        (closedActionsAsync.isLoading && !closedActionsAsync.hasValue)) {
      return AppListPageSkeleton(padding: shellTabContentPadding(context));
    }

    final entries = progressAsync.value ?? const <ExecutionProgressEntry>[];
    final closedActions = closedActionsAsync.value ?? const <ExecutionAction>[];
    if (entries.isEmpty && closedActions.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: shellTabContentPadding(context),
        children: [
          const _ExecutionReviewAgentPanel(),
          ExecutionStateView(
            icon: FLucideIcons.clipboardCheck,
            title: l10n.executionReviewEmptyTitle,
            message: l10n.executionReviewEmptyBody,
            action: FButton(
              onPress: () => showExecutionProgressSheet(context: context),
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
        const _ExecutionReviewAgentPanel(),
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
              onEdit: () =>
                  showExecutionActionSheet(context: context, action: action),
              onRecordProgress: () =>
                  showExecutionProgressSheet(context: context, action: action),
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

class _ExecutionReviewAgentPanel extends ConsumerWidget {
  const _ExecutionReviewAgentPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultsAsync = ref.watch(
      execution_agent_providers.latestExecutionReviewResultsProvider,
    );
    final l10n = AppLocalizations.of(context);
    if (resultsAsync.isLoading && !resultsAsync.hasValue) {
      return _ExecutionReviewAgentPanelFrame(
        child: AgentResultPanelStateCard(
          icon: FLucideIcons.loaderCircle,
          title: l10n.commonLoading,
          message: l10n.agentResultLoadingBody,
          loading: true,
        ),
      );
    }
    if (resultsAsync.hasError && !resultsAsync.hasValue) {
      return _ExecutionReviewAgentPanelFrame(
        child: AgentResultPanelStateCard(
          icon: FLucideIcons.triangleAlert,
          title: l10n.commonError,
          message: userSafeErrorMessage(context, resultsAsync.error!),
          error: true,
          onRetry: () => ref.invalidate(
            execution_agent_providers.latestExecutionReviewResultsProvider,
          ),
        ),
      );
    }
    final bundle = resultsAsync.value;
    final runToShowBeforeArtifacts = bundle?.runToShowBeforeArtifacts;
    if (runToShowBeforeArtifacts != null) {
      return _ExecutionReviewAgentPanelFrame(
        child: AgentRunStatusCard(
          record: runToShowBeforeArtifacts,
          metaLabel: _executionAgentMetaLabel(
            context,
            runToShowBeforeArtifacts.startedAt,
          ),
          onRetry: () => _retryExecutionReview(ref),
        ),
      );
    }

    final artifacts = bundle?.artifacts ?? const <AgentArtifact>[];
    final artifact = artifacts.isEmpty ? null : artifacts.first;
    if (artifact != null) {
      return _ExecutionReviewAgentPanelFrame(
        child: _ExecutionReviewArtifactCard(artifact: artifact),
      );
    }
    final run = bundle?.latestRun;
    if (run == null) return const SizedBox.shrink();
    return _ExecutionReviewAgentPanelFrame(
      child: AgentRunStatusCard(
        record: run,
        metaLabel: _executionAgentMetaLabel(context, run.startedAt),
        onRetry: () => _retryExecutionReview(ref),
      ),
    );
  }
}

class _ExecutionReviewAgentPanelFrame extends StatelessWidget {
  const _ExecutionReviewAgentPanelFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        const SizedBox(height: AppSpacing.s16),
      ],
    );
  }
}

class _ExecutionReviewArtifactCard extends ConsumerWidget {
  const _ExecutionReviewArtifactCard({required this.artifact});

  final AgentArtifact artifact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metaLabel = _executionAgentMetaLabel(context, artifact.createdAt);
    return AgentResultCard(
      artifact: artifact,
      metaLabel: metaLabel,
      onOpen: () => showAgentArtifactSheet(
        context: context,
        artifact: artifact,
        subtitle: metaLabel,
        onVisibilityChanged: () => ref.invalidate(
          execution_agent_providers.latestExecutionReviewResultsProvider,
        ),
      ),
    );
  }
}

Future<void> _retryExecutionReview(WidgetRef ref) async {
  final controller = await ref.read(agentRunControllerProvider.future);
  await controller.runOnceById(kExecutionReviewAgentId);
  ref.invalidate(
    execution_agent_providers.latestExecutionReviewResultsProvider,
  );
}

String _executionAgentMetaLabel(BuildContext context, DateTime at) {
  final l10n = AppLocalizations.of(context);
  final local = at.toLocal();
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  return '${l10n.executionReviewTitle} · $mm-$dd';
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
