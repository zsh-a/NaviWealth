import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

import '../theme/app_theme_scope.dart';
import '../tokens/dimens_tokens.dart';
import 'app_interaction.dart';

/// The one pull-to-refresh affordance for every domain.
///
/// Wraps Material's drag mechanics (arming, physics, a11y) but skins the
/// indicator with app tokens — brand progress stroke on a raised surface
/// disc — so refresh reads identically on Finance, Health, Knowledge,
/// Execution and Life. Replaces both raw `RefreshIndicator` call sites and
/// KnowledgeOS's hand-rolled overscroll accumulator.
class AppRefreshIndicator extends StatelessWidget {
  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.edgeOffset = 0,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// Offset for surfaces with collapsed/floating headers.
  final double edgeOffset;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isDark = colors.brightness == Brightness.dark;
    final surfaces = context.appTheme.surfaces;
    return RefreshIndicator(
      onRefresh: () {
        // RefreshIndicator invokes this only once the drag crosses the
        // trigger threshold, so the haptic marks the actual commit — not
        // every drag tick.
        AppInteraction.signal(AppInteractionIntent.select);
        return onRefresh();
      },
      color: colors.primary,
      backgroundColor: isDark ? surfaces.raised : surfaces.card,
      strokeWidth: AppStroke.sparkline,
      displacement: AppSpacing.s40,
      edgeOffset: edgeOffset,
      child: child,
    );
  }
}
