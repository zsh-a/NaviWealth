import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'execution_action_sheet.dart';
import 'execution_project_sheet.dart';

/// The single ExecutionOS creation entry.
///
/// Users choose only between a concrete next action and a multi-step plan.
/// Commitments remain readable for existing data, but are no longer a separate
/// concept users must understand before capturing work.
Future<void> showExecutionCreateSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showAppSheet<void>(
    context: context,
    title: l10n.executionCreatePlanTitle,
    builder: (sheetContext) => AppActionSheetList(
      children: [
        AppActionSheetTile(
          icon: FLucideIcons.listPlus,
          title: l10n.executionCreateActionTitle,
          subtitle: l10n.executionActionTitleHint,
          onPress: () {
            Navigator.of(sheetContext).pop();
            showExecutionActionSheet(context: context);
          },
        ),
        AppActionSheetTile(
          icon: FLucideIcons.folder,
          title: l10n.executionCreateProjectTitle,
          subtitle: l10n.executionProjectTitleHint,
          onPress: () {
            Navigator.of(sheetContext).pop();
            showExecutionProjectSheet(context: context);
          },
        ),
      ],
    ),
  );
}
