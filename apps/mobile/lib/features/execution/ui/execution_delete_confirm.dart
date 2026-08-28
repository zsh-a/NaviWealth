import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../../../design_system/design_system.dart';
import '../../../l10n/gen/app_localizations.dart';

Future<bool> confirmExecutionDelete({
  required BuildContext context,
  required String item,
  String? body,
}) async {
  final l10n = AppLocalizations.of(context);
  final confirmed = await showConfirmDialog(
    context: context,
    title: Text(l10n.executionDeleteConfirmTitle(item)),
    body: Text(body ?? l10n.executionDeleteConfirmBody),
    confirmLabel: l10n.commonDelete,
    cancelLabel: l10n.commonCancel,
    destructive: true,
    icon: FLucideIcons.trash2,
  );
  return confirmed == true;
}
