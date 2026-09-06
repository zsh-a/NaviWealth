import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:naviwealth/design_system/theme/app_forui_theme.dart';
import 'package:naviwealth/design_system/theme/app_theme.dart';

/// MaterialApp builder for isolated widgets that use the app's Forui controls.
/// Keep it above the Navigator so dialogs and sheets inherit the same theme,
/// accessibility preferences, and adaptive input scope as the page.
Widget buildTestAppTheme(BuildContext context, Widget? child) {
  final theme = Theme.of(context);
  return FTheme(
    data: buildAppForuiTheme(
      brightness: theme.brightness,
      touch: !useCompactDensity(
        theme.platform,
        kIsWeb,
        windowWidth: MediaQuery.sizeOf(context).width,
      ),
    ),
    child: child ?? const SizedBox.shrink(),
  );
}
