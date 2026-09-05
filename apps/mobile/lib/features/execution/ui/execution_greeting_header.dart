/// Task heading and actions for the domain home.
library;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shell/shell_chrome.dart';
import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../composition/execution_route_paths.dart';

class ExecutionGreetingHeader extends StatelessWidget {
  const ExecutionGreetingHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.s8,
        bottom: AppSpacing.s16,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              l10n.executionTodayActionsTitle,
              style: context.briefGreetingTitleStyle,
            ),
          ),
          AppIconButton(
            icon: FLucideIcons.history,
            tooltip: l10n.executionReviewTitle,
            onPress: () => context.push(ExecutionRoutes.review),
          ),
          const ShellActionRow(),
        ],
      ),
    );
  }
}
