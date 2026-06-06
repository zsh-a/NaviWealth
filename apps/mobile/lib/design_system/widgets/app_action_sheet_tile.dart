import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';

/// One row in a bottom-sheet action list.
///
/// Mixes in [FTileMixin] so it can be dropped straight into an
/// [AppActionSheetList] / [FTileGroup] — the panel then reads as a
/// single grouped surface with hairline dividers (calm, iOS-style)
/// instead of a stack of heavy floating cards.
class AppActionSheetTile extends StatelessWidget with FTileMixin {
  const AppActionSheetTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPress,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FTile(
      onPress: onPress,
      // Accent-tinted chip — readable contrast and on-brand, versus the
      // old washed-out grey-on-grey square.
      prefix: Container(
        width: AppSpacing.s40,
        height: AppSpacing.s40,
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: AppIconSizes.md, color: colors.primary),
      ),
      title: Text(
        title,
        style: context.theme.typography.sm.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      // Single line keeps every row the same height — uneven 1-vs-2
      // line subtitles were a big part of the "messy" read.
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.theme.typography.xs.copyWith(
          color: colors.mutedForeground,
        ),
      ),
      suffix: Icon(
        FLucideIcons.chevronRight,
        size: AppIconSizes.md,
        color: colors.mutedForeground.withValues(alpha: AppOpacity.scrim),
      ),
    );
  }
}

/// Groups [AppActionSheetTile]s into one rounded surface with indented
/// hairline dividers. This is the elegant, unified look for every
/// bottom-sheet action panel — use it instead of a raw `Column`.
class AppActionSheetList extends StatelessWidget {
  const AppActionSheetList({super.key, required this.children});

  final List<AppActionSheetTile> children;

  @override
  Widget build(BuildContext context) {
    // intrinsicWidth → renders as a Column (not a Sliver) so it nests
    // inside the sheet's SingleChildScrollView.
    return FTileGroup(intrinsicWidth: true, children: children);
  }
}
