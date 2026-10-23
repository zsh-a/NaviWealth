/// Task heading and actions for the domain home.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/shell_chrome.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/execution_route_paths.dart';
import 'execution_action_sheet.dart';

class ExecutionGreetingHeader extends StatelessWidget {
  const ExecutionGreetingHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return ShellPageHeading(
      title: l10n.executionTodayActionsTitle,
      actions: [
        ShellHeaderActionSpec(
          icon: FLucideIcons.plus,
          label: l10n.executionCreateActionTitle,
          onPress: () => showExecutionActionSheet(context: context),
          order: -10,
        ),
        ShellHeaderActionSpec(
          icon: FLucideIcons.history,
          label: l10n.executionReviewTitle,
          onPress: () => context.push(ExecutionRoutes.review),
          order: 10,
        ),
      ],
    );
  }
}
