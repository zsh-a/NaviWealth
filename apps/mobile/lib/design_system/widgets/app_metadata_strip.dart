import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/text_style_presets.dart';
import 'app_badge.dart';

/// A responsive, background-free band for secondary object information.
///
/// Metadata is supporting content, not a collection of actions. Keeping it on
/// the parent surface avoids the visual noise of one tinted card per value.
class AppMetadataStrip extends StatelessWidget {
  const AppMetadataStrip({
    super.key,
    required this.children,
    this.spacing = AppSpacing.s20,
    this.runSpacing = AppSpacing.s10,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        crossAxisAlignment: WrapCrossAlignment.start,
        children: children,
      ),
    );
  }
}

/// One label/value pair inside an [AppMetadataStrip].
class AppMetadataItem extends StatelessWidget {
  const AppMetadataItem({
    super.key,
    required this.label,
    required this.value,
    this.maxWidth = 260,
  });

  final String label;
  final String value;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.captionStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            value,
            style: context.mediumLabelStyle.copyWith(color: colors.foreground),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// A metadata field whose values are semantic tags rather than prose.
class AppMetadataTags extends StatelessWidget {
  const AppMetadataTags({
    super.key,
    required this.label,
    required this.values,
    this.maxWidth = 320,
  });

  final String label;
  final List<String> values;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.captionStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.s4),
          Wrap(
            spacing: AppSpacing.s4,
            runSpacing: AppSpacing.s4,
            children: [
              for (final value in values)
                AppBadge(
                  label: value,
                  size: AppBadgeSize.compact,
                  outlined: true,
                  foregroundColor: colors.mutedForeground,
                  containerColor: colors.background.withValues(
                    alpha: AppOpacity.transparent,
                  ),
                  borderColor: colors.border.withValues(
                    alpha: AppOpacity.muted,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
