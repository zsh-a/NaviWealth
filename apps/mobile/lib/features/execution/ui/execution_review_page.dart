import 'package:flutter/material.dart' show RefreshIndicator;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';

import '../../../app/shell_chrome.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/providers.dart';
import '../domain/execution_models.dart';
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
          await ref.read(executionRecentProgressProvider.future);
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
    final actions =
        ref.watch(executionOpenActionsProvider).value ??
        const <ExecutionAction>[];
    final projects =
        ref.watch(executionProjectsProvider).value ??
        const <ExecutionProject>[];
    final commitments =
        ref.watch(executionCommitmentsProvider).value ??
        const <ExecutionCommitment>[];
    return progressAsync.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (e, _) => ExecutionStateView(
        icon: FLucideIcons.circleX,
        title: l10n.commonError,
        message: '$e',
      ),
      data: (entries) {
        if (entries.isEmpty) {
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
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: shellTabContentPadding(context),
          itemCount: entries.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return ExecutionSectionHeader(
                title: l10n.executionReviewTitle,
                count: entries.length,
                icon: FLucideIcons.clipboardCheck,
              );
            }
            final entry = entries[index - 1];
            return ExecutionProgressCard(
              entry: entry,
              actionLabel: _actionLabel(actions, entry.actionId),
              projectLabel: _projectLabel(projects, entry.projectId),
              commitmentLabel: _commitmentLabel(
                commitments,
                entry.commitmentId,
              ),
            );
          },
        );
      },
    );
  }
}

String? _actionLabel(List<ExecutionAction> actions, String? id) {
  if (id == null || id.isEmpty) return null;
  for (final action in actions) {
    if (action.id == id) return action.title;
  }
  return id;
}

String? _projectLabel(List<ExecutionProject> projects, String? id) {
  if (id == null || id.isEmpty) return null;
  for (final project in projects) {
    if (project.id == id) return project.title;
  }
  return id;
}

String? _commitmentLabel(List<ExecutionCommitment> commitments, String? id) {
  if (id == null || id.isEmpty) return null;
  for (final commitment in commitments) {
    if (commitment.id == id) return commitment.title;
  }
  return id;
}
