import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_scope.dart';

/// Single-pixel ribbon divider between rows in a [SoftCard] or settings list.
///
/// Replaces the per-feature `_Divider` / `_RowDivider` private widgets that
/// were copy-pasted across 4 settings files. Treatment comes from
/// `theme.divider` so every list rules the same way.
class AppDivider extends StatelessWidget {
  const AppDivider({super.key, this.horizontalPadding});

  /// Horizontal inset from the card edges. Defaults to the spec inset.
  final double? horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final spec = context.appTheme.divider;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding ?? spec.inset,
      ),
      child: Container(
        height: spec.thickness,
        color: context.theme.colors.foreground.withValues(alpha: spec.opacity),
      ),
    );
  }
}
