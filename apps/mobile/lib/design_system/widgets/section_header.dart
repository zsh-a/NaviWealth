import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';

import '../tokens/dimens_tokens.dart';
import '../tokens/typography_tokens.dart';

/// Neutral section header used above grouped cards / lists.
///
/// [titleColor] remains available for the rare semantic section that needs
/// emphasis; interactive trailing actions should carry the accent by default.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.s16,
      AppSpacing.s24,
      AppSpacing.s16,
      AppSpacing.s10,
    ),
  });

  final String title;
  final String? subtitle;
  final Color? titleColor;
  final EdgeInsetsGeometry padding;

  /// Optional trailing widget (e.g. an action button) placed to the right
  /// of the title row.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final foreground = titleColor ?? colors.foreground;
    final titleStyle = TypographyTokens.sectionHeaderTitle(foreground);
    final subtitleStyle = TypographyTokens.sectionHeaderSubtitle(
      colors.mutedForeground,
    );
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: titleStyle),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(subtitle!, style: subtitleStyle),
        ],
      ],
    );
    return Padding(
      padding: padding,
      child: trailing != null
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: titleBlock),
                trailing!,
              ],
            )
          : titleBlock,
    );
  }
}
