import 'package:flutter/material.dart' show RefreshIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../app/shell_chrome.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';
import 'execution_action_sheet.dart';
import 'execution_commitment_sheet.dart';
import 'execution_widgets.dart';

class ExecutionCommitmentsPage extends ConsumerWidget {
  const ExecutionCommitmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.executionCommitmentsTitle,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.target),
          semanticsLabel: l10n.executionCreateCommitmentTitle,
          onPress: () =>
              showExecutionCommitmentSheet(context: context, ref: ref),
        ),
        FHeaderAction(
          icon: const Icon(FLucideIcons.plus),
          semanticsLabel: l10n.executionCreateActionTitle,
          onPress: () => showExecutionActionSheet(context: context, ref: ref),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(executionOpenActionsProvider);
          ref.invalidate(executionCommitmentsProvider);
          await ref.read(executionOpenActionsProvider.future);
        },
        child: _CommitmentsBody(),
      ),
    );
  }
}

class _CommitmentsBody extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final actionsAsync = ref.watch(executionOpenActionsProvider);
    final commitmentsAsync = ref.watch(executionCommitmentsProvider);
    return actionsAsync.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (e, _) => ExecutionStateView(
        icon: FLucideIcons.circleX,
        title: l10n.commonError,
        message: '$e',
      ),
      data: (actions) {
        final commitments = commitmentsAsync.value ?? const [];
        if (actions.isEmpty && commitments.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: shellTabContentPadding(context),
            children: [
              ExecutionStateView(
                icon: FLucideIcons.listTodo,
                title: l10n.executionCommitmentsEmptyTitle,
                message: l10n.executionCommitmentsEmptyBody,
                action: FButton(
                  onPress: () =>
                      showExecutionCommitmentSheet(context: context, ref: ref),
                  child: Text(l10n.executionCreateCommitmentTitle),
                ),
              ),
            ],
          );
        }
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: shellTabContentPadding(context),
          children: [
            if (commitments.isNotEmpty) ...[
              Text(l10n.executionCommitmentsSection, style: context.labelStyle),
              const SizedBox(height: AppSpacing.s8),
              for (final commitment in commitments) ...[
                SoftCard(
                  padding: const EdgeInsets.all(AppSpacing.s12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(commitment.title, style: context.labelStyle),
                      if (commitment.description.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.s4),
                        Text(
                          commitment.description,
                          style: context.captionStyle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
              ],
              const SizedBox(height: AppSpacing.s8),
            ],
            Text(l10n.executionActionsSection, style: context.labelStyle),
            const SizedBox(height: AppSpacing.s8),
            for (final action in actions) ...[
              ExecutionActionCard(
                action: action,
                onStart: () => updateExecutionActionStatus(
                  ref: ref,
                  action: action,
                  status: ExecutionActionStatus.doing,
                ),
                onBlock: () => updateExecutionActionStatus(
                  ref: ref,
                  action: action,
                  status: ExecutionActionStatus.blocked,
                  progressNote: l10n.executionProgressBlockedDefault,
                ),
                onResume: () => updateExecutionActionStatus(
                  ref: ref,
                  action: action,
                  status: ExecutionActionStatus.doing,
                ),
                onDone: () => updateExecutionActionStatus(
                  ref: ref,
                  action: action,
                  status: ExecutionActionStatus.done,
                  progressNote: l10n.executionProgressDoneDefault,
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
            ],
          ],
        );
      },
    );
  }
}
