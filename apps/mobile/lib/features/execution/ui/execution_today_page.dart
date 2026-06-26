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
import 'execution_widgets.dart';

class ExecutionTodayPage extends ConsumerWidget {
  const ExecutionTodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ShellTabScaffold(
      title: l10n.executionTodayTitle,
      actions: [
        FHeaderAction(
          icon: const Icon(FLucideIcons.plus),
          semanticsLabel: l10n.executionCreateActionTitle,
          onPress: () => showExecutionActionSheet(context: context, ref: ref),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(executionTodayActionsProvider);
          await ref.read(executionTodayActionsProvider.future);
        },
        child: _TodayList(),
      ),
    );
  }
}

class _TodayList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final actionsAsync = ref.watch(executionTodayActionsProvider);
    return actionsAsync.when(
      loading: () => const Center(child: FCircularProgress()),
      error: (e, _) => ExecutionStateView(
        icon: FLucideIcons.circleX,
        title: l10n.commonError,
        message: '$e',
      ),
      data: (actions) {
        if (actions.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: shellTabContentPadding(context),
            children: [
              ExecutionStateView(
                icon: FLucideIcons.checkCheck,
                title: l10n.executionTodayEmptyTitle,
                message: l10n.executionTodayEmptyBody,
                action: FButton(
                  onPress: () =>
                      showExecutionActionSheet(context: context, ref: ref),
                  child: Text(l10n.executionCreateActionTitle),
                ),
              ),
            ],
          );
        }
        return ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: shellTabContentPadding(context),
          itemCount: actions.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s8),
          itemBuilder: (context, index) {
            final action = actions[index];
            return ExecutionActionCard(
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
            );
          },
        );
      },
    );
  }
}
