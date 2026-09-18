import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../../../../design_system/design_system.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// Detail drill-ins keep their parent overview and scroll position intact.
Future<T?> showFinanceDetailSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  String? subtitle,
  bool scrollable = true,
}) => showAppSheet<T>(
  context: context,
  title: title,
  subtitle: subtitle,
  scrollable: scrollable,
  actions: [
    Builder(
      builder: (context) => AppIconButton(
        key: const ValueKey('finance-detail-close'),
        icon: FLucideIcons.x,
        tooltip: AppLocalizations.of(context).commonClose,
        onPress: () => Navigator.of(context).pop(),
      ),
    ),
  ],
  builder: builder,
);
