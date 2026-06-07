import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';

/// Single-pixel ribbon divider between rows in a [SoftCard] or settings list.
///
/// Replaces the per-feature `_Divider` / `_RowDivider` private widgets that
/// were copy-pasted across 4 settings files.
class AppDivider extends StatelessWidget {
  const AppDivider({super.key, this.horizontalPadding = AppSpacing.s14});

  /// Horizontal inset from the card edges. Defaults to [AppSpacing.s14].
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Container(
        height: 1,
        color: context.theme.colors.foreground.withValues(
          alpha: AppOpacity.whisper,
        ),
      ),
    );
  }
}
