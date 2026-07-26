import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/agents/agent_artifact_routes.dart';
import '../../../core/ai/agents/agent_run_controller.dart';
import '../../../core/ai/agents/ui/agent_result_card.dart';
import '../../../core/lifeos/action_outcome.dart';
import '../../../core/shell/shell_chrome.dart';
import '../../../core/shell/shell_visibility.dart';
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
import 'execution_source_route.dart';
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
      child: ShellTabPause(
        routePath: ExecutionRoutes.review,
        child: AppRefreshIndicator(
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
      ),
    );
  }
}

enum _ReviewWindow { sevenDays, thirtyDays, all }

class _ReviewBody extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ReviewBody> createState() => _ReviewBodyState();
}

class _ReviewBodyState extends ConsumerState<_ReviewBody> {
  _ReviewWindow _window = _ReviewWindow.sevenDays;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final progressAsync = ref.watch(executionRecentProgressProvider);
    final closedActionsAsync = ref.watch(executionClosedActionsProvider);
    final relations = ref.watch(executionReviewRelationsProvider).value;
    final outcomes = ref.watch(actionOutcomeSummariesProvider);
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

    final cutoff = switch (_window) {
      _ReviewWindow.sevenDays => DateTime.now().subtract(
        const Duration(days: 7),
      ),
      _ReviewWindow.thirtyDays => DateTime.now().subtract(
        const Duration(days: 30),
      ),
      _ReviewWindow.all => null,
    };
    final entries = (progressAsync.value ?? const <ExecutionProgressEntry>[])
        .where(
          (entry) =>
              cutoff == null || !entry.createdAt.toLocal().isBefore(cutoff),
        )
        .toList(growable: false);
    final closedActions =
        (closedActionsAsync.value ?? const <ExecutionAction>[])
            .where((action) {
              final at = action.completedAt ?? action.createdAt;
              return cutoff == null || !at.toLocal().isBefore(cutoff);
            })
            .toList(growable: false);
    final empty = entries.isEmpty && closedActions.isEmpty;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: shellTabContentPadding(context),
      children: [
        SegmentedRow<_ReviewWindow>(
          options: _ReviewWindow.values,
          value: _window,
          labelOf: (window) => switch (window) {
            _ReviewWindow.sevenDays => l10n.executionReviewWindow7d,
            _ReviewWindow.thirtyDays => l10n.executionReviewWindow30d,
            _ReviewWindow.all => l10n.executionReviewWindowAll,
          },
          iconOf: (window) => switch (window) {
            _ReviewWindow.sevenDays => FLucideIcons.calendarDays,
            _ReviewWindow.thirtyDays => FLucideIcons.calendarRange,
            _ReviewWindow.all => FLucideIcons.infinity,
          },
          onChanged: (window) => setState(() => _window = window),
        ),
        const SizedBox(height: AppSpacing.s12),
        _ReviewSummary(entries: entries, closedActions: closedActions),
        const SizedBox(height: AppSpacing.s16),
        const _ExecutionReviewAgentPanel(),
        if (empty)
          ExecutionStateView(
            icon: FLucideIcons.clipboardCheck,
            title: l10n.executionReviewEmptyTitle,
            message: l10n.executionReviewEmptyBody,
            action: FButton(
              onPress: () => showExecutionProgressSheet(context: context),
              child: Text(l10n.executionCreateProgressTitle),
            ),
          )
        else if (entries.isNotEmpty) ...[
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
              onEdit: () =>
                  showExecutionProgressSheet(context: context, progress: entry),
              onDelete: () => _deleteProgress(context, ref, entry),
              onActionOpen: entry.actionId == null
                  ? null
                  : () => context.push(ExecutionRoutes.action(entry.actionId!)),
              onProjectOpen: entry.projectId == null
                  ? null
                  : () =>
                        context.push(ExecutionRoutes.project(entry.projectId!)),
              onCommitmentOpen: entry.commitmentId == null
                  ? null
                  : () => context.push(
                      ExecutionRoutes.commitment(entry.commitmentId!),
                    ),
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
              onSourceOpen: executionSourceOpen(context, ref, action.source),
              onEdit: () =>
                  showExecutionActionSheet(context: context, action: action),
              onRecordProgress: () =>
                  showExecutionProgressSheet(context: context, action: action),
              blockedProgressNote: l10n.executionProgressBlockedDefault,
              doneProgressNote: l10n.executionProgressDoneDefault,
              droppedProgressNote: l10n.executionProgressDroppedDefault,
              outcome: outcomes[action.id],
            ),
            const SizedBox(height: AppSpacing.s8),
          ],
        ],
      ],
    );
  }
}

class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({required this.entries, required this.closedActions});

  final List<ExecutionProgressEntry> entries;
  final List<ExecutionAction> closedActions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = context.appTheme.status;
    final completed = closedActions
        .where((action) => action.status == ExecutionActionStatus.done)
        .length;
    final blockers = entries
        .where((entry) => entry.kind == ExecutionProgressKind.blocker)
        .length;
    return Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.s8,
      children: [
        AppBadge(
          label: '${l10n.executionReviewCompletedMetric} $completed',
          icon: FLucideIcons.checkCheck,
          foregroundColor: status.success.fg,
        ),
        AppBadge(
          label: '${l10n.executionReviewBlockedMetric} $blockers',
          icon: FLucideIcons.octagonAlert,
          foregroundColor: blockers > 0 ? status.danger.fg : null,
        ),
        AppBadge(
          label: '${l10n.executionReviewProgressMetric} ${entries.length}',
          icon: FLucideIcons.messageSquareText,
        ),
      ],
    );
  }
}

class _ExecutionReviewAgentPanel extends ConsumerStatefulWidget {
  const _ExecutionReviewAgentPanel();

  @override
  ConsumerState<_ExecutionReviewAgentPanel> createState() =>
      _ExecutionReviewAgentPanelState();
}

class _ExecutionReviewAgentPanelState
    extends ConsumerState<_ExecutionReviewAgentPanel> {
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(
      execution_agent_providers.latestExecutionReviewResultsProvider,
    );
    final l10n = AppLocalizations.of(context);
    // Quiet while loading — no status shells on Review.
    if (resultsAsync.isLoading && !resultsAsync.hasValue) {
      return const SizedBox.shrink();
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
    if (bundle == null || bundle.visibleEntries.isEmpty) {
      return _ExecutionReviewAgentPanelFrame(
        child: SoftCard.flat(
          padding: const EdgeInsets.all(AppSpacing.s12),
          child: Row(
            children: [
              AppIconTile(
                icon: FLucideIcons.sparkles,
                color: context.theme.colors.primary,
                size: 34,
                iconSize: AppIconSizes.sm,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.executionReviewGenerateTitle,
                      style: context.rowTitleStyle,
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      l10n.executionReviewGenerateBody,
                      style: context.captionStyle,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.s12),
              FButton(
                onPress: _running ? null : _runReview,
                child: _running
                    ? const FCircularProgress(
                        size: FCircularProgressSizeVariant.xs,
                      )
                    : Text(l10n.executionReviewGenerateAction),
              ),
            ],
          ),
        ),
      );
    }
    return _ExecutionReviewAgentPanelFrame(
      child: AgentResultsSection(
        bundle: bundle,
        metaLabelBuilder: (at) => _executionAgentMetaLabel(context, at),
        onOpen: (artifact) =>
            context.push(AgentArtifactRoutes.detail(artifact.id)),
        onRetry: (_) => _retryExecutionReview(ref),
      ),
    );
  }

  Future<void> _runReview() async {
    setState(() => _running = true);
    try {
      await _retryExecutionReview(ref);
    } catch (error, stackTrace) {
      if (mounted) {
        AppMessenger.show(
          context,
          ToastKind.error,
          userSafeErrorMessage(context, error, stackTrace: stackTrace),
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
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
